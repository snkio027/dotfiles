require("lazy").load({ plugins = { "nvim-dap" } })
local dap = require("dap")
local workflow = require("config.zig_debug")
local root = assert(vim.uv.fs_mkdtemp(vim.fs.joinpath(assert(vim.uv.os_tmpdir()), "zig-workflow-XXXXXX")))
root = assert(vim.uv.fs_realpath(root))
local cwd = vim.fn.getcwd()
local function file(path, lines)
	vim.fn.mkdir(vim.fs.dirname(path), "p")
	vim.fn.writefile(lines, path)
end
local function wait(predicate, message)
	-- Match the existing Zig compile contract: cold compilation can take up to
	-- 120 seconds; debugger event deadlines remain 30 seconds.
	local budget = message:find("ZIG_BUILD_TIMEOUT", 1, true) and 120000 or 30000
	local completed = vim.wait(budget, predicate, 20)
	if not completed then
		file(root .. "/failure-output.log", workflow.last_log or {})
	end
	assert(completed, message)
end
local function config(project, argv)
	file(project .. "/.nvim/zig.json", {
		vim.json.encode({
			build = { argv = argv or { "zig", "build" } },
			debug = { program = "zig-out/bin/probe", cwd = "." },
		}),
	})
end
local projects, buffers = {}, {}
for _, name in ipairs({ "a", "b" }) do
	local project = root .. "/" .. name
	projects[#projects + 1] = project
	file(project .. "/build.zig", {
		'const std=@import("std");',
		"pub fn build(b:*std.Build) void {",
		'  const exe=b.addExecutable(.{.name="probe",.root_module=b.createModule(.{.root_source_file=b.path("main.zig"),.target=b.standardTargetOptions(.{}),.optimize=.debug,.link_libc=true})});',
		'  const delay=b.addSystemCommand(&.{"sleep","0.5"});',
		"  exe.step.dependOn(&delay.step);",
		"  b.installArtifact(exe);",
		"}",
	})
	file(project .. "/main.zig", {
		'extern "c" fn fopen([*:0]const u8, [*:0]const u8) ?*anyopaque;',
		'extern "c" fn fclose(*anyopaque) c_int;',
		"pub fn main() void {",
		'  const handle=fopen("fixture.txt", "r") orelse @panic("wrong project cwd");',
		"  _=fclose(handle);",
		"}",
	})
	file(project .. "/fixture.txt", { name })
	config(project)
	local buf = vim.fn.bufadd(project .. "/main.zig")
	vim.fn.bufload(buf)
	buffers[#buffers + 1] = buf
end
vim.cmd.cd(root)
for index, project in ipairs(projects) do
	vim.api.nvim_set_current_buf(buffers[index])
	vim.bo.filetype = "zig"
	require("dap.breakpoints").clear()
	require("dap.breakpoints").set({}, buffers[index], 5)
	local stopped, exited = false, nil
	dap.listeners.after.event_stopped.zig_build_workflow = function()
		stopped = true
	end
	dap.listeners.after.event_exited.zig_build_workflow = function(_, body)
		exited = body.exitCode
	end
	workflow.build_debug()
	local concurrent = pcall(workflow.build_debug)
	assert(not concurrent, "ZIG_BUILD_CONCURRENT_LAUNCH_ALLOWED")
	wait(function()
		return workflow.last_result ~= nil
	end, "ZIG_BUILD_TIMEOUT")
	assert(workflow.last_result.launched, "ZIG_BUILD_NOT_LAUNCHED: " .. vim.inspect(workflow.last_result))
	wait(function()
		return stopped or exited ~= nil
	end, "ZIG_BUILD_BREAKPOINT_TIMEOUT")
	assert(stopped, "ZIG_BUILD_EXITED_BEFORE_BREAKPOINT")
	local session = assert(dap.session())
	wait(function()
		return session.current_frame ~= nil
	end, "ZIG_BUILD_FRAME_TIMEOUT")
	assert(
		session.config.program == project .. "/zig-out/bin/probe" and session.config.cwd == project,
		"ZIG_BUILD_PROJECT_CHANGED"
	)
	assert(
		session.current_frame.source.path == project .. "/main.zig" and session.current_frame.line == 5,
		"ZIG_BUILD_BREAKPOINT_WRONG"
	)
	dap.continue()
	wait(function()
		return exited ~= nil and dap.session() == nil
	end, "ZIG_BUILD_EXIT_TIMEOUT")
	assert(exited == 0, "ZIG_BUILD_RESOURCE_FAILED")
end
print("ZIG_BUILD_DEBUG_REAL_COMPLETE")
local project = projects[1]
vim.api.nvim_set_current_buf(buffers[1])
config(project, { "zig", "build", "not-a-step" })
workflow.build_debug()
wait(function()
	return workflow.last_result ~= nil
end, "ZIG_BUILD_FAIL_TIMEOUT")
assert(
	not workflow.last_result.launched and workflow.last_result.code ~= 0 and not dap.session(),
	"ZIG_FAILED_BUILD_LAUNCHED_STALE_BINARY"
)
config(project)
workflow.build_debug()
workflow.stop()
wait(function()
	return workflow.last_result ~= nil
end, "ZIG_BUILD_CANCEL_TIMEOUT")
assert(not workflow.last_result.launched and not dap.session(), "ZIG_CANCEL_LAUNCHED")
workflow.build_debug()
vim.defer_fn(function()
	file(project .. "/main.zig", vim.list_extend(vim.fn.readfile(project .. "/main.zig"), { "// late save" }))
end, 100)
wait(function()
	return workflow.last_result ~= nil
end, "ZIG_BUILD_LATE_SAVE_TIMEOUT")
assert(
	not workflow.last_result.launched and workflow.last_result.error:find("changed", 1, true),
	"ZIG_LATE_SAVE_NOT_REJECTED"
)
vim.cmd.checktime()
workflow.build_debug()
vim.defer_fn(function()
	config(project, { "zig", "build", "install" })
end, 100)
wait(function()
	return workflow.last_result ~= nil
end, "ZIG_BUILD_CONFIG_RACE_TIMEOUT")
assert(
	not workflow.last_result.launched and workflow.last_result.error:find("changed", 1, true),
	"ZIG_CONFIG_RACE_NOT_REJECTED"
)
config(project)
workflow.build_debug()
vim.api.nvim_set_current_buf(buffers[2])
wait(function()
	return workflow.last_result ~= nil
end, "ZIG_BUILD_PROJECT_RACE_TIMEOUT")
assert(
	not workflow.last_result.launched and workflow.last_result.error:find("project changed", 1, true),
	"ZIG_PROJECT_RACE_NOT_REJECTED"
)
assert(vim.fn.getcwd() == root, "ZIG_BUILD_CHANGED_EDITOR_CWD")
dap.listeners.after.event_stopped.zig_build_workflow = nil
dap.listeners.after.event_exited.zig_build_workflow = nil
require("dap.breakpoints").clear()
vim.cmd.cd(cwd)
io.stdout:write("ZIG_BUILD_WORKFLOW_COMPLETE\n")
