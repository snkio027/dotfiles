-- Real Zig 0.17 execution: pinned discovery, owned build artifacts and codelldb.
local contract_dir = vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p"))
dofile(contract_dir .. "/zig_helper_ownership.lua")
local public_results, public_count = {}, 0
local plugin = require("lazy.core.config").plugins.neotest
local configure = plugin.config
plugin.config = function(spec, opts)
	opts.consumers = opts.consumers or {}
	opts.consumers.zig_workflow = function(client)
		client.listeners.results = function(adapter_id, results, partial)
			if not partial and adapter_id:find("neotest-zig", 1, true) then
				public_results = results
				public_count = public_count + 1
			end
		end
		return {}
	end
	local replacement
	for _, value in ipairs(opts.adapters) do
		if value.name == "neotest-zig" then
			replacement = value
		end
	end
	assert(
		replacement and debug.getinfo(replacement.build_spec).source:find("config/zig_test.lua", 1, true),
		"ZIG_REPLACEMENT_ADAPTER_NOT_CONFIGURED"
	)
	configure(spec, opts)
end
require("lazy").load({ plugins = { "neotest", "nvim-dap" } })
plugin.config = configure
local neotest = require("neotest")
local nio = require("nio")
local adapter = require("config.zig_test").adapter()
local root = assert(vim.uv.fs_mkdtemp(vim.fs.joinpath(assert(vim.uv.os_tmpdir()), "zig-workflow-XXXXXX")))
root = assert(vim.uv.fs_realpath(root))
local cwd = vim.fn.getcwd()
local function file(path, lines)
	vim.fn.mkdir(vim.fs.dirname(path), "p")
	vim.fn.writefile(lines, path)
end
local function async(fn)
	local done, output, failure
	nio.run(function()
		local ok, value = xpcall(fn, debug.traceback)
		if ok then
			output = value
		else
			failure = value
		end
		done = true
	end)
	assert(
		vim.wait(120000, function()
			return done
		end, 20),
		"ZIG_WORKFLOW_ASYNC_TIMEOUT"
	)
	assert(not failure, failure)
	return output
end
local function tree(path)
	return async(function()
		return assert(adapter.discover_positions(path))
	end)
end
local function run(selected, debugger, stop)
	return async(function()
		local spec = adapter.build_spec({ tree = selected, strategy = debugger and "dap" or "integrated" })
		local process = spec.strategy(spec, { adapter = adapter, position = selected:data() })
		if stop then
			stop(process, spec)
		end
		local code = process.result()
		local results = adapter.results(spec, { code = code, output = process.output() }, selected)
		assert(not spec.context.helper or not vim.uv.fs_stat(spec.context.helper.path), "ZIG_HELPER_LEAKED")
		return { spec = spec, code = code, results = results }
	end)
end
local function by_name(selected, name)
	for _, node in selected:iter_nodes() do
		if node:data().name == '"' .. name .. '"' then
			return node
		end
	end
	error("missing selected test " .. name)
end
local function status(result, selected, name, expected)
	assert(
		result.results[by_name(selected, name):data().id].status == expected,
		"ZIG_STATUS " .. name .. " expected " .. expected .. ": " .. vim.inspect(result.results)
	)
end
local standalone = root .. "/standalone/tests.zig"
file(standalone, {
	'const std = @import("std");',
	'test "pass" { try std.testing.expect(true); }',
	'test "fail" { try std.testing.expect(false); }',
	'test "skip" { return error.SkipZigTest; }',
})
local standalone_tree = tree(standalone)
local all = run(standalone_tree)
assert(all.code ~= 0, "ZIG_FAILURE_NOT_PROPAGATED")
status(all, standalone_tree, "pass", "passed")
status(all, standalone_tree, "fail", "failed")
status(all, standalone_tree, "skip", "skipped")
local nearest = run(by_name(standalone_tree, "pass"))
assert(nearest.code == 0, "ZIG_NEAREST_FAILED: " .. table.concat(vim.fn.readfile(nearest.spec.context.output), "\n"))
status(nearest, standalone_tree, "pass", "passed")
vim.cmd.cd(vim.fs.dirname(standalone))
vim.cmd.edit(standalone)
vim.bo.filetype = "zig"
local public_before = public_count
neotest.run.run(standalone)
assert(
	vim.wait(120000, function()
		return public_count > public_before
	end, 20),
	"ZIG_PUBLIC_FILE_RUN_TIMEOUT"
)
status({ results = public_results }, standalone_tree, "pass", "passed")
status({ results = public_results }, standalone_tree, "fail", "failed")
status({ results = public_results }, standalone_tree, "skip", "skipped")
print("ZIG_NATIVE_FILE_NEAREST_COMPLETE")
-- An abnormal process exit cannot be reported as an entirely skipped suite.
local result_dir = assert(vim.uv.fs_mkdtemp(root .. "/result-check-XXXXXX"))
local result_id = "owned-result"
file(
	result_dir .. "/result-0.json",
	{ vim.json.encode({ { id = result_id, status = "skipped", short = "SkipZigTest" } }) }
)
local abnormal = adapter.results(
	{ context = { directory = result_dir, output = result_dir .. "/output.log", inputs = { { id = result_id } } } },
	{ code = 1 }
)
assert(abnormal[result_id].status == "failed", "ZIG_ABNORMAL_EXIT_REPORTED_SKIPPED")

local project = root .. "/project"
file(project .. "/build.zig", {
	'const std = @import("std");',
	"pub fn build(b: *std.Build) void {",
	"  const target = b.standardTargetOptions(.{});",
	"  const optimize = b.standardOptimizeOption(.{});",
	'  const tests = b.addTest(.{.root_module=b.createModule(.{.root_source_file=b.path("src/root.zig"),.target=target,.optimize=optimize})});',
	"  const run = b.addRunArtifact(tests);",
	'  run.setCwd(b.path("src"));',
	'  run.setEnvironmentVariable("DOTFILES_ZIG_FIXTURE", "owned-project");',
	'  b.step("test", "Run project tests").dependOn(&run.step);',
	"}",
})
local source = project .. "/src/root.zig"
file(source, {
	'const std = @import("std");',
	'extern "c" fn getenv([*:0]const u8) ?[*:0]const u8;',
	'extern "c" fn fopen([*:0]const u8, [*:0]const u8) ?*anyopaque;',
	'extern "c" fn fclose(*anyopaque) c_int;',
	'test "resource" {',
	'  const value = getenv("DOTFILES_ZIG_FIXTURE") orelse return error.MissingProjectEnvironment;',
	'  try std.testing.expectEqualStrings("owned-project", std.mem.span(value));',
	'  const handle = fopen("fixture.txt", "r") orelse return error.WrongProjectCwd;',
	"  _ = fclose(handle);",
	"}",
	'test "skip" { return error.SkipZigTest; }',
})
-- The project's native module owns its link configuration too.
local build = vim.fn.readfile(project .. "/build.zig")
table.insert(build, 6, "  tests.root_module.link_libc = true;")
file(project .. "/build.zig", build)
file(project .. "/src/fixture.txt", { "resource" })
file(project .. "/neotest_build.zig", { "USER-OWNED-SENTINEL" })
vim.cmd.cd(root)
local project_tree = tree(source)
assert(adapter.root(source) == project, "ZIG_PROJECT_ROOT_WRONG")
local project_result = run(project_tree)
assert(
	project_result.code == 0,
	"ZIG_PROJECT_FAILED: " .. table.concat(vim.fn.readfile(project_result.spec.context.output), "\n")
)
status(project_result, project_tree, "resource", "passed")
status(project_result, project_tree, "skip", "skipped")
assert(vim.fn.readfile(project .. "/neotest_build.zig")[1] == "USER-OWNED-SENTINEL", "ZIG_USER_HELPER_TOUCHED")
print("ZIG_NATIVE_PROJECT_COMPLETE")

-- Replacing an owned helper revokes ownership; cleanup cannot delete it.
local owner = require("config.zig_test")._helper_create(project, "owned")
assert(vim.uv.fs_unlink(owner.path))
file(owner.path, { "new-user-file" })
require("config.zig_test")._helper_remove(owner)
assert(vim.fn.readfile(owner.path)[1] == "new-user-file", "ZIG_REPLACED_HELPER_DELETED")
local cancelled = run(by_name(project_tree, "resource"), false, function(process)
	process.stop()
end)
assert(cancelled.code ~= 0, "ZIG_CANCEL_IGNORED")
status(cancelled, project_tree, "resource", "failed")
print("ZIG_ARTIFACT_OWNERSHIP_CANCEL_COMPLETE")
-- Two simultaneous runs in different projects must never share artifacts or
-- use the editor cwd. The same test names intentionally occur in both trees.
local second_project = root .. "/other-project"
file(second_project .. "/build.zig", vim.fn.readfile(project .. "/build.zig"))
file(second_project .. "/src/root.zig", vim.fn.readfile(source))
file(second_project .. "/src/fixture.txt", { "other-resource" })
local second_tree = tree(second_project .. "/src/root.zig")
async(function()
	local trees = { by_name(project_tree, "resource"), by_name(second_tree, "resource") }
	local specs, processes = {}, {}
	for index, selected in ipairs(trees) do
		specs[index] = adapter.build_spec({ tree = selected })
		processes[index] = specs[index].strategy(specs[index], { adapter = adapter, position = selected:data() })
	end
	assert(specs[1].context.directory ~= specs[2].context.directory, "ZIG_CONCURRENT_ARTIFACT_COLLISION")
	assert(specs[1].context.helper.path ~= specs[2].context.helper.path, "ZIG_CONCURRENT_HELPER_COLLISION")
	for index, process in ipairs(processes) do
		local code = process.result()
		assert(
			code == 0,
			"ZIG_CONCURRENT_RUN_FAILED: " .. table.concat(vim.fn.readfile(specs[index].context.output), "\n")
		)
		local results = adapter.results(specs[index], { code = code }, trees[index])
		assert(results[trees[index]:data().id].status == "passed", "ZIG_CONCURRENT_RESULT_WRONG")
		assert(not vim.uv.fs_stat(specs[index].context.helper.path), "ZIG_CONCURRENT_HELPER_LEAK")
	end
end)
print("ZIG_CONCURRENT_PROJECT_COMPLETE")

local dap = require("dap")
local buf = vim.fn.bufadd(source)
vim.fn.bufload(buf)
vim.api.nvim_set_current_buf(buf)
vim.bo[buf].filetype = "zig"
require("dap.breakpoints").clear()
require("dap.breakpoints").set({}, buf, 9)
local hit, exited = false, nil
local listener = "zig_workflow_contract"
dap.listeners.after.event_stopped[listener] = function()
	local session = dap.session()
	vim.defer_fn(function()
		assert(session and session.config.type == "codelldb", "ZIG_TEST_DAP_TYPE")
		assert(session.config.cwd == project .. "/src", "ZIG_TEST_DAP_CWD")
		assert(session.current_frame and session.current_frame.line == 9, "ZIG_TEST_BREAKPOINT_LINE")
		assert(session.current_frame.source.path == source, "ZIG_TEST_BREAKPOINT_SOURCE")
		hit = true
		dap.continue()
	end, 50)
end
dap.listeners.after.event_exited[listener] = function(_, body)
	exited = body.exitCode
end
vim.api.nvim_win_set_cursor(0, { 6, 0 })
async(function()
	for _ = 1, 100 do
		if neotest.run.get_tree_from_args({ source }) then
			return
		end
		nio.sleep(50)
	end
	error("ZIG_PUBLIC_PROJECT_DISCOVERY_TIMEOUT")
end)
public_before = public_count
neotest.run.run({ strategy = "dap" })
assert(
	vim.wait(120000, function()
		return public_count > public_before
	end, 20),
	"ZIG_PUBLIC_TEST_DAP_TIMEOUT"
)
assert(hit and exited == 0, "ZIG_PUBLIC_TEST_DAP_FAILED: " .. vim.inspect(public_results))
status({ results = public_results }, project_tree, "resource", "passed")
dap.listeners.after.event_stopped[listener] = nil
dap.listeners.after.event_exited[listener] = nil
require("dap.breakpoints").clear()
vim.cmd.cd(cwd)
print("ZIG_TEST_DAP_COMPLETE")
io.stdout:write("ZIG_WORKFLOW_COMPLETE\n")
