-- Real native CMake presets, builds and CTest, plus editor/Overseer boundaries.
-- Every source, build and output belongs to this disposable fixture.
local function eq(actual, expected, label)
	assert(vim.deep_equal(actual, expected), label .. ": " .. vim.inspect(actual))
end
local function wait_for(predicate, label)
	assert(vim.wait(30000, predicate, 20), label)
end
local function feed(keys)
	vim.fn.feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "xt")
end
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
root = assert(vim.uv.fs_realpath(root))
local a, b = root .. "/project a", root .. "/project b"
local cwd, input, notify = vim.fn.getcwd(), vim.ui.input, vim.notify
local buffers, tasks, messages, submitted = {}, {}, {}, {}
local original_task, overseer
local function write(project, name, lines)
	local path = project .. "/" .. name
	vim.fn.mkdir(vim.fs.dirname(path), "p")
	vim.fn.writefile(type(lines) == "table" and lines or { vim.json.encode(lines) }, path)
end
local function json(project, name, value)
	write(project, name, { vim.json.encode(value) })
end
local function modified(project, name, lines)
	local buf = vim.fn.bufadd(project .. "/" .. name)
	vim.fn.bufload(buf)
	buffers[#buffers + 1] = buf
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	return buf
end
local function completed(task, expected)
	assert(task, "workflow was not created")
	wait_for(function()
		return task:is_complete()
	end, "native CMake workflow did not complete")
	eq(
		task.status,
		expected,
		vim.inspect({ task.cmd, task.cwd, vim.api.nvim_buf_get_lines(task:get_bufnr(), 0, -1, false) })
	)
end
local cmake_source = {
	"cmake_minimum_required(VERSION 3.25)",
	"project(native_workflow LANGUAGES CXX)",
	'file(WRITE "${CMAKE_BINARY_DIR}/configure-env" "$ENV{WF_CONFIG}")',
	'if(EXISTS "${CMAKE_SOURCE_DIR}/slow.flag")',
	'  file(WRITE "${CMAKE_SOURCE_DIR}/entered-configure" "entered")',
	'  execute_process(COMMAND "${CMAKE_COMMAND}" -E sleep 2)',
	"endif()",
	"enable_testing()",
	"add_executable(probe main.cpp)",
	'add_test(NAME selected COMMAND probe "${CMAKE_SOURCE_DIR}/seen-$<CONFIG>" "$<CONFIG>")',
	'add_test(NAME excluded COMMAND "${CMAKE_COMMAND}" -E false)',
	'set_tests_properties(selected PROPERTIES WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")',
}
local source = {
	"#include <cstdio>",
	"#include <cstdlib>",
	"#define SAVED_VALUE 7",
	"int main(int argc, char **argv) {",
	'  auto *resource = std::fopen("resource.txt", "r");',
	"  if (!resource || argc != 3) return 41;",
	"  std::fclose(resource);",
	'  auto *environment = std::getenv("WF_ENV");',
	"  if (!environment) return 42;",
	'  auto *out = std::fopen(argv[1], "w");',
	"  if (!out) return 43;",
	'  std::fprintf(out, "%s %s %d", argv[2], environment, SAVED_VALUE);',
	"  return std::fclose(out);",
	"}",
}
local function fixture(project)
	vim.fn.mkdir(project, "p")
	write(project, "CMakeLists.txt", cmake_source)
	write(project, "main.cpp", source)
	write(project, "resource.txt", { "relative project resource" })
	json(project, "presets/shared.json", {
		version = 6,
		configurePresets = {
			{
				name = "common",
				hidden = true,
				generator = "Ninja Multi-Config",
				binaryDir = "${sourceDir}/build/multi",
				environment = { WF_CONFIG = "include-inherited" },
			},
		},
	})
	json(project, "CMakePresets.json", {
		version = 6,
		include = { "presets/shared.json" },
		configurePresets = { { name = "dev", inherits = "common" } },
		buildPresets = {
			{ name = "debug", configurePreset = "dev", configuration = "Debug" },
			{ name = "release", configurePreset = "dev", configuration = "Release" },
		},
		testPresets = {
			{
				name = "test-common",
				hidden = true,
				configurePreset = "dev",
				environment = { WF_ENV = "inherited" },
				filter = { include = { name = "^selected$" } },
				output = { outputOnFailure = true },
			},
			{ name = "debug-test", inherits = "test-common", configuration = "Debug" },
			{ name = "release-test", inherits = "test-common", configuration = "Release" },
		},
		workflowPresets = {
			{
				name = "debug-flow",
				steps = {
					{ type = "configure", name = "dev" },
					{ type = "build", name = "debug" },
					{ type = "test", name = "debug-test" },
				},
			},
		},
	})
	json(project, "CMakeUserPresets.json", {
		version = 6,
		testPresets = { { name = "user-test", inherits = "release-test", environment = { WF_ENV = "user" } } },
		workflowPresets = {
			{
				name = "user release",
				steps = {
					{ type = "configure", name = "dev" },
					{ type = "build", name = "release" },
					{ type = "test", name = "user-test" },
				},
			},
		},
	})
end
local ok, err = xpcall(function()
	fixture(a)
	fixture(b)
	require("lazy").load({ plugins = { "cmake-tools.nvim" } })
	vim.api.nvim_exec_autocmds("User", { pattern = "VeryLazy" })
	local cmake = require("cmake-tools")
	local native = require("config.cmake_native_workflow")
	overseer = require("overseer")
	original_task = overseer.new_task
	overseer.new_task = function(opts)
		local task = original_task(opts)
		tasks[#tasks + 1] = task
		submitted[task] = vim.deepcopy(opts)
		return task
	end
	vim.notify = function(message)
		messages[#messages + 1] = message
	end
	local function select_project(project)
		vim.cmd.cd(vim.fn.fnameescape(project))
		eq(vim.uv.fs_realpath(cmake.get_config().cwd), project, "actual selected CMake project")
	end
	select_project(a)
	local edited_source = vim.deepcopy(source)
	edited_source[3] = "#define SAVED_VALUE 8"
	local own = modified(a, "main.cpp", edited_source)
	local other = modified(b, "unrelated.txt", { "do not save another project's draft" })
	local selected_preset
	vim.ui.input = function(opts, callback)
		assert(opts.prompt:find(a, 1, true), "preset prompt lacks selected project")
		selected_preset = callback
	end
	feed("<leader>oW")
	assert(selected_preset, "native workflow key did not open its preset prompt")
	selected_preset("debug-flow")
	local debug_task = tasks[#tasks]
	completed(debug_task, "SUCCESS")
	eq(submitted[debug_task].args, { "--workflow", "--preset", "debug-flow" }, "native argv")
	eq(debug_task.cwd, a, "native cwd")
	eq(debug_task.metadata.cmake_workflow, { root = a, preset = "debug-flow" }, "project task metadata")
	eq(vim.fn.readfile(a .. "/seen-Debug"), { "Debug inherited 8" }, "real saved source, CTest env/config/cwd/filter")
	eq(vim.fn.readfile(a .. "/build/multi/configure-env"), { "include-inherited" }, "native include/inheritance")
	assert(vim.fn.executable(a .. "/build/multi/Debug/probe") == 1)
	assert(not vim.bo[own].modified and vim.bo[other].modified, "save ownership was lost")
	assert(vim.fn.filereadable(b .. "/unrelated.txt") == 0)
	assert(not native.is_active(a), "completed project still reserved")
	local release_task = native.run("user release")
	completed(release_task, "SUCCESS")
	eq(submitted[release_task].args[3], "user release", "literal user workflow preset argv")
	eq(vim.fn.readfile(a .. "/seen-Release"), { "Release user 8" }, "real UserPresets/Release test")
	assert(vim.fn.executable(a .. "/build/multi/Release/probe") == 1)

	-- Invalid names are CMake's error; shell syntax remains a literal argv item.
	local invalid = "missing;touch injected"
	local invalid_task = native.run(invalid)
	completed(invalid_task, "FAILURE")
	eq(submitted[invalid_task].args[3], invalid, "preset must remain one argument")
	assert(vim.fn.filereadable(a .. "/injected") == 0)
	-- Actual compiler failure must prevent the workflow's later CTest step.
	vim.fn.delete(a .. "/seen-Debug")
	vim.api.nvim_buf_set_lines(own, 0, -1, false, { "intentional compile failure" })
	completed(native.run("debug-flow"), "FAILURE")
	assert(vim.fn.filereadable(a .. "/seen-Debug") == 0, "failed native build still ran tests")
	vim.api.nvim_buf_set_lines(own, 0, -1, false, edited_source)
	completed(native.run("debug-flow"), "SUCCESS")

	-- No hidden work on cancel; changing the selected project during the prompt
	-- cannot run a formerly selected project's workflow.
	local count = #tasks
	native.run()
	selected_preset(nil)
	eq(#tasks, count, "canceled workflow prompt")
	native.run()
	select_project(b)
	selected_preset("debug-flow")
	eq(#tasks, count, "stale project prompt")
	completed(native.run("debug-flow"), "SUCCESS")
	eq(vim.fn.readfile(b .. "/seen-Debug"), { "Debug inherited 7" }, "second project attribution")
	assert(not vim.bo[other].modified, "second project's own draft was not saved")
	select_project(a)

	local function slow_task()
		vim.fn.delete(a .. "/entered-configure")
		vim.fn.delete(a .. "/seen-Debug")
		write(a, "slow.flag", { "delay for deterministic editor boundary" })
		local task = native.run("debug-flow")
		wait_for(function()
			return vim.fn.filereadable(a .. "/entered-configure") == 1
		end, "native configure barrier")
		assert(task:is_running() and native.is_active(a), "workflow is not active at barrier")
		return task
	end
	local active = slow_task()
	count = #tasks
	assert(native.run("debug-flow") == nil, "overlapping workflow accepted")
	local build_error
	cmake.build({ bang = false, fargs = {} }, function(result)
		build_error = result
	end)
	assert(build_error, "ordinary CMake build did not reject an active native workflow")
	eq(#tasks, count, "active workflow spawned competing build")
	-- A write outside this captured project must leave its task running.
	local outside = modified(b, "outside.txt", { "unrelated save" })
	vim.api.nvim_buf_call(outside, function()
		vim.cmd("silent write")
	end)
	assert(active:is_running(), "another project's save canceled this workflow")
	select_project(b)
	assert(active.cwd == a and native.is_active(a), "changing selected project rewrote the active task")
	local late = modified(a, "late.txt", { "saved during native execution" })
	vim.api.nvim_buf_call(late, function()
		vim.cmd("silent write")
	end)
	eq(active.status, "CANCELED", "late-save must stop the native workflow")
	assert(not native.is_active(a), "late-save cancellation leaked active state")
	vim.fn.jobwait({ active.strategy.job_id }, 5000)
	vim.fn.delete(a .. "/slow.flag")
	assert(vim.fn.filereadable(a .. "/seen-Debug") == 0, "late-save canceled workflow reached tests")

	-- Restart uses the same guard. A task from A cannot restart in B, then may
	-- restart successfully after the user deliberately selects A again.
	select_project(b)
	active:reset()
	assert(active:start() == false, "old project task restarted under another selected project")
	eq(active.status, "PENDING", "rejected restart status")
	assert(not native.is_active(a))
	select_project(a)
	assert(active:start())
	completed(active, "SUCCESS")
	-- Explicit stop also releases ownership and never reaches CTest.
	active = slow_task()
	assert(active:stop())
	eq(active.status, "CANCELED", "explicit task cancellation")
	vim.fn.jobwait({ active.strategy.job_id }, 5000)
	vim.fn.delete(a .. "/slow.flag")
	assert(not native.is_active(a) and vim.fn.filereadable(a .. "/seen-Debug") == 0)

	-- Existing CMakeTools executor jobs exclude native workflows too.
	local backend = require("cmake-tools.overseer")
	backend.run(
		"cmake",
		nil,
		nil,
		{ "-E", "sleep", "2" },
		a,
		{ new_task_opts = { strategy = { "jobstart", use_terminal = false }, components = { "default" } } }
	)
	count = #tasks
	assert(backend.job:is_running())
	assert(native.run("debug-flow") == nil, "native workflow raced the existing CMake executor")
	eq(#tasks, count, "native task during active executor")
	backend.job:stop()
	vim.fn.jobwait({ backend.job.strategy.job_id }, 5000)

	-- Startup errors and a later component veto never acquire the project.
	local failed = overseer.new_task({
		cmd = { "cmake", "--version" },
		cwd = a,
		components = { "default", { "cmake_workflow_guard", root = a } },
	})
	failed.strategy.start = function()
		error("intentional strategy startup failure")
	end
	assert(failed:start() == false)
	assert(not native.is_active(a), "strategy startup failure left a permanent active reservation")
	failed:dispose(true)
	local vetoed = overseer.new_task({
		cmd = { "cmake", "--version" },
		cwd = a,
		components = { "default", { "cmake_workflow_guard", root = a } },
	})
	table.insert(vetoed.components, {
		name = "fixture_veto",
		on_pre_start = function()
			return false
		end,
	})
	assert(vetoed:start() == false and not native.is_active(a), "component veto leaked active ownership")
	vetoed:dispose(true)

	-- A save can invoke a user autocmd that replaces CMakeTools' config object.
	-- Use real DirChanged, not a stubbed root, and reject before strategy start.
	local restart = overseer.new_task({
		cmd = { "cmake", "--version" },
		cwd = a,
		components = { "default", { "cmake_workflow_guard", root = a } },
	})
	local trigger = modified(a, "switch.txt", { "save hook changes selected project" })
	local before = cmake.get_config()
	vim.api.nvim_create_autocmd("BufWritePost", {
		buffer = trigger,
		once = true,
		nested = true,
		callback = function()
			select_project(b)
		end,
	})
	local dispatched = false
	restart.strategy.start = function()
		dispatched = true
		error("unexpected old-project strategy dispatch")
	end
	assert(restart:start() == false)
	assert(cmake.get_config() ~= before and cmake.get_config().cwd == b, "save did not change actual config object")
	assert(not dispatched and not native.is_active(a), "save-time project replacement passed restart guard")
	restart:dispose(true)
	select_project(a)
	-- A failing normal save cannot be bypassed by the workflow.
	local blocked = modified(a, "blocked.txt", { "must remain unsaved" })
	local blocker = vim.api.nvim_create_autocmd("BufWritePre", {
		buffer = blocked,
		callback = function()
			error("fixture save refused")
		end,
	})
	count = #tasks
	assert(native.run("debug-flow") == nil)
	eq(#tasks, count, "failed save still launched native task")
	assert(vim.bo[blocked].modified and vim.fn.filereadable(a .. "/blocked.txt") == 0)
	vim.api.nvim_del_autocmd(blocker)
	vim.bo[blocked].modified = false
	assert(#messages > 0, "rejections were not explained")
	print("CMAKE_NATIVE_WORKFLOW_COMPLETE")
end, debug.traceback)
vim.ui.input, vim.notify = input, notify
if overseer and original_task then
	overseer.new_task = original_task
end
for _, task in ipairs(tasks) do
	if not task:is_disposed() then
		pcall(task.dispose, task, true)
	end
end
for _, buf in ipairs(buffers) do
	if vim.api.nvim_buf_is_valid(buf) then
		pcall(vim.api.nvim_buf_delete, buf, { force = true })
	end
end
pcall(vim.cmd.cd, vim.fn.fnameescape(cwd))
assert(ok, err)
