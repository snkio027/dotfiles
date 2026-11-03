-- Compile real Zig programs and stop codelldb at a source breakpoint from a
-- parent cwd, then switch editing projects without changing that cwd.
require("lazy").load({ plugins = { "nvim-dap" } })
local dap = require("dap")
assert(dap.adapters.codelldb, "ZIG_DEBUG_ADAPTER_MISSING")
local original_cwd = vim.fn.getcwd()
local original_input = vim.fn.input
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
root = assert(vim.uv.fs_realpath(root))
local buffers = {}
local stopped, exited
local listener = "dotfiles_zig_debug_contract"
dap.listeners.after.event_stopped[listener] = function()
	stopped = true
end
dap.listeners.after.event_exited[listener] = function(_, body)
	exited = body.exitCode
end

local function wait_for(predicate, message)
	assert(vim.wait(30000, predicate, 20), message)
end

local ok, err = xpcall(function()
	vim.cmd.cd(root)
	for _, name in ipairs({ "project-a", "project-b" }) do
		local project = vim.fs.joinpath(root, name)
		vim.fn.mkdir(vim.fs.joinpath(project, "zig-out/bin"), "p")
		vim.fn.mkdir(vim.fs.joinpath(project, ".git"), "p")
		vim.fn.writefile({ name }, vim.fs.joinpath(project, "fixture.txt"))
		local source = vim.fs.joinpath(project, "main.zig")
		vim.fn.writefile({
			'extern "c" fn fopen([*:0]const u8, [*:0]const u8) ?*anyopaque;',
			'extern "c" fn fclose(*anyopaque) c_int;',
			"pub fn main() void {",
			'    const handle = fopen("fixture.txt", "r") orelse @panic("wrong working directory");',
			"    _ = fclose(handle);",
			"}",
		}, source)
		local executable = vim.fs.joinpath(project, "zig-out/bin/probe")
		local build = vim.system(
			{ "zig", "build-exe", "-O", "Debug", "-lc", source, "-femit-bin=" .. executable },
			{ cwd = project, text = true }
		):wait(120000)
		assert(build.code == 0, "ZIG_BUILD_FAILED: " .. build.stderr)
		local buf = vim.fn.bufadd(source)
		buffers[#buffers + 1] = buf
		vim.fn.bufload(buf)
		vim.api.nvim_set_current_buf(buf)
		vim.bo[buf].filetype = "zig"
		assert(LazyVim.root() == project, "ZIG_PROJECT_ROOT_MISMATCH")
		vim.fn.input = function(_, default)
			assert(default == project .. "/zig-out/bin/", "ZIG_PROMPT_ROOT_MISMATCH")
			-- Relative selection must resolve against the project, not editor cwd.
			return "zig-out/bin/probe"
		end
		require("dap.breakpoints").clear()
		require("dap.breakpoints").set({}, buf, 5)
		stopped, exited = false, nil
		dap.run(dap.configurations.zig[1])
		wait_for(function()
			return stopped or exited ~= nil
		end, "ZIG_BREAKPOINT_TIMEOUT")
		assert(stopped, "ZIG_EXITED_BEFORE_BREAKPOINT: " .. tostring(exited))
		local session = assert(dap.session(), "ZIG_SESSION_MISSING")
		assert(session.config.program == executable, "ZIG_PROGRAM_ROOT_MISMATCH")
		assert(session.config.cwd == project, "ZIG_CWD_MISMATCH")
		wait_for(function()
			return session.current_frame ~= nil
		end, "ZIG_STACK_FRAME_TIMEOUT")
		assert(session.current_frame.line == 5, "ZIG_BREAKPOINT_LINE_MISMATCH")
		assert(session.current_frame.source.path == source, "ZIG_BREAKPOINT_SOURCE_MISMATCH")
		dap.continue()
		wait_for(function()
			return exited ~= nil
		end, "ZIG_EXIT_TIMEOUT")
		assert(exited == 0, "ZIG_RESOURCE_CWD_FAILED")
		wait_for(function()
			return dap.session() == nil
		end, "ZIG_SESSION_CLOSE_TIMEOUT")
		assert(vim.fn.getcwd() == root, "ZIG_DEBUG_CHANGED_EDITOR_CWD")
		print("ZIG_DEBUG_PROJECT_COMPLETE: " .. name)
	end
	vim.fn.input = function()
		return ""
	end
	local cancelled = dap.configurations.zig[1]()
	assert(cancelled.program == dap.ABORT, "ZIG_CANCEL_MUST_ABORT")
end, debug.traceback)

vim.fn.input = original_input
dap.listeners.after.event_stopped[listener] = nil
dap.listeners.after.event_exited[listener] = nil
if dap.session() then
	dap.terminate()
	vim.wait(5000, function()
		return dap.session() == nil
	end, 20)
end
require("dap.breakpoints").clear()
vim.cmd.cd(original_cwd)
for _, buf in ipairs(buffers) do
	if vim.api.nvim_buf_is_valid(buf) then
		vim.api.nvim_buf_delete(buf, { force = true })
	end
end
if ok then
	vim.fn.delete(root, "rf")
end
assert(ok, err)
print("ZIG_DEBUG_COMPLETE: real build, breakpoints, resources, cross-project cwd and cancellation")
io.stdout:write("ZIG_DEBUG_COMPLETE\n")
