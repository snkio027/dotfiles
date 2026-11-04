-- Directory aliases and build-time cwd replacement must not escape ownership.
-- The cwd case invokes the real Zig compiler; only DAP dispatch is observed.
require("lazy").load({ plugins = { "nvim-dap" } })
local module = require("config.zig_debug")
local dap = require("dap")
local root = assert(vim.uv.fs_mkdtemp(vim.fs.joinpath(assert(vim.uv.os_tmpdir()), "zig-boundaries-XXXXXX")))
root = assert(vim.uv.fs_realpath(root))
local project, alias, outside = root .. "/project", root .. "/alias", root .. "/outside"
vim.fn.mkdir(project .. "/.nvim", "p")
vim.fn.mkdir(project .. "/run", "p")
vim.fn.mkdir(outside, "p")
vim.fn.mkdir(alias, "p")
vim.fn.writefile({ "// Root marker; the explicit build uses build-exe." }, project .. "/build.zig")
vim.fn.writefile({ "pub fn main() void {}" }, project .. "/main.zig")
vim.fn.writefile({
	vim.json.encode({
		build = { argv = { "zig", "build-exe", "main.zig", "-femit-bin=app" } },
		debug = { program = "app", cwd = "run" },
	}),
}, project .. "/.nvim/zig.json")
local initial_buffer = vim.api.nvim_get_current_buf()
local buffers = {}
local function buffer(path, lines)
	local buf = vim.api.nvim_create_buf(true, false)
	buffers[#buffers + 1] = buf
	vim.api.nvim_buf_set_name(buf, path)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_set_current_buf(buf)
	return buf
end
local jobstart, run, notify = vim.fn.jobstart, dap.run, vim.notify
local jobs, launches, messages = {}, {}, {}
local ok, err = xpcall(function()
	vim.notify = function(message)
		messages[#messages + 1] = message
	end
	local aliased = buffer(alias .. "/new.zig", { "pub fn main() void { unreachable; }" })
	-- Preserve an already opened pathname while a directory becomes an alias.
	assert(vim.uv.fs_rmdir(alias))
	assert(vim.uv.fs_symlink(project, alias, { dir = true }))
	assert(
		vim.api.nvim_buf_get_name(aliased) == alias .. "/new.zig",
		"fixture did not retain its alias path: " .. vim.api.nvim_buf_get_name(aliased)
	)
	local attempts = 0
	vim.fn.jobstart = function(argv, opts)
		if type(argv) == "table" and argv[1] == "zig" then
			attempts = attempts + 1
			return -1
		end
		return jobstart(argv, opts)
	end
	local accepted, message = pcall(vim.cmd, "ZigBuildDebug")
	assert(not accepted and tostring(message):find("Save project buffers", 1, true), "aliased draft was not rejected")
	assert(attempts == 0, "unsaved source through an alias reached the Zig build")
	assert(vim.bo[aliased].modified, "draft was silently written")
	assert(vim.fn.readfile(project .. "/main.zig")[1] == "pub fn main() void {}", "source file was altered")
	vim.bo[aliased].modified = false
	vim.api.nvim_buf_delete(aliased, { force = true })
	print("ZIG_BUILD_ALIAS_GUARD_COMPLETE")

	local actual = buffer(project .. "/main.zig", { "pub fn main() void {}" })
	vim.bo[actual].modified = false
	dap.run = function(config)
		launches[#launches + 1] = vim.deepcopy(config)
	end
	local replaced = false
	vim.fn.jobstart = function(argv, opts)
		local id = jobstart(argv, opts)
		if type(argv) == "table" and argv[1] == "zig" then
			assert(id > 0, "real Zig compiler did not start")
			jobs[#jobs + 1] = id
			assert(not replaced)
			assert(vim.uv.fs_rename(project .. "/run", project .. "/original-run"))
			assert(vim.uv.fs_symlink(outside, project .. "/run", { dir = true }))
			replaced = true
		end
		return id
	end
	vim.cmd("ZigBuildDebug")
	assert(replaced, "fixture did not change cwd after compilation started")
	assert(
		vim.wait(30000, function()
			return module.last_result ~= nil
		end, 20),
		"Zig boundary build did not finish"
	)
	assert(module.last_result.code == 0 and vim.fn.executable(project .. "/app") == 1, "fixture's actual build failed")
	assert(
		not module.last_result.launched and #launches == 0,
		"changed cwd dispatched the debugger outside the project"
	)
	assert(tostring(module.last_result.error):find("cwd changed", 1, true), vim.inspect(module.last_result))
	assert(vim.uv.fs_realpath(project .. "/run") == outside)
	print("ZIG_BUILD_CWD_GUARD_COMPLETE")

	-- A linked launch contract still participates in the freshness comparison.
	local snapshot
	for index = 1, 20 do
		local name, value = debug.getupvalue(module.build_debug, index)
		if name == "snapshot" then
			snapshot = value
			break
		end
		if not name then
			break
		end
	end
	assert(snapshot, "ZIG_SNAPSHOT_HELPER_MISSING")
	local linked = outside .. "/launch.json"
	vim.fn.writefile({ "first config" }, linked)
	assert(vim.uv.fs_unlink(project .. "/.nvim/zig.json"))
	assert(vim.uv.fs_symlink(linked, project .. "/.nvim/zig.json"))
	local before = snapshot(project)
	vim.fn.writefile({ "changed config" }, linked)
	assert(not vim.deep_equal(before, snapshot(project)), "ZIG_LINKED_CONFIG_CHANGE_MISSED")
	print("ZIG_LINKED_CONFIG_GUARD_COMPLETE")
	print("ZIG_BUILD_BOUNDARIES_COMPLETE")
end, debug.traceback)
vim.fn.jobstart, dap.run, vim.notify = jobstart, run, notify
module.stop()
for _, id in ipairs(jobs) do
	if vim.fn.jobwait({ id }, 0)[1] == -1 then
		vim.fn.jobstop(id)
	end
end
for _, buf in ipairs(buffers) do
	if vim.api.nvim_buf_is_valid(buf) then
		pcall(vim.api.nvim_buf_delete, buf, { force = true })
	end
end
if vim.api.nvim_buf_is_valid(initial_buffer) then
	vim.api.nvim_set_current_buf(initial_buffer)
end
assert(ok, err)
