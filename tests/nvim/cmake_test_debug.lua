-- Real configure/build/CTest/codelldb coverage. Run via run_contract.lua in an
-- isolated configured Neovim; all project files are temporary fixtures.
local root = assert(vim.uv.fs_realpath(vim.fn.tempname():match("^(.*)/[^/]+$"))) .. "/cmake-chain-" .. vim.fn.getpid()
vim.fn.mkdir(root, "p")
local project = vim.fs.joinpath(root, "project")
vim.fn.mkdir(project, "p")
local cwd, select, input = vim.fn.getcwd(), vim.ui.select, vim.ui.input
local tasks, buffers = {}, {}
local overseer, original_task, dap
local observe_task
local function wait_for(predicate, message)
	assert(vim.wait(30000, predicate, 20), message)
end
local function write(name, lines)
	vim.fn.writefile(lines, vim.fs.joinpath(project, name))
end
local function edit(name, lines)
	local buf = vim.fn.bufadd(vim.fs.joinpath(project, name))
	vim.fn.bufload(buf)
	buffers[#buffers + 1] = buf
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	return buf
end
local function completed(count, status)
	wait_for(function()
		return #tasks >= count and tasks[count]:is_complete()
	end, "CMake task did not finish")
	assert(
		tasks[count].status == status,
		vim.inspect({
			tasks[count].cmd,
			tasks[count].status,
			vim.api.nvim_buf_get_lines(tasks[count]:get_bufnr(), 0, -1, false),
		})
	)
end
local ok, err = xpcall(function()
	write("CMakeLists.txt", {
		"cmake_minimum_required(VERSION 3.25)",
		"project(chain LANGUAGES CXX)",
		"enable_testing()",
		"add_executable(first first.cpp)",
		"add_executable(second second.cpp)",
		"add_test(NAME selected COMMAND second test)",
		"add_test(NAME excluded COMMAND first)",
		'set_tests_properties(selected PROPERTIES WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")',
	})
	write("first.cpp", { "int main() { return 0; }" })
	local source = {
		"#include <cstdio>",
		"#include <cstdlib>",
		"#include <cstring>",
		"int main(int argc, char** argv) {",
		'  auto* resource = std::fopen("resource.txt", "r");',
		"  if (!resource) return 41;",
		"  std::fclose(resource);",
		"  int value = 17;", -- Real source breakpoint, before marker/exit.
		'  if (argc != 2 || !std::getenv("CHAIN_ENV")) return 42;',
		'  auto* marker = std::fopen(argv[1], "w");',
		"  if (!marker) return 43;",
		'  std::fprintf(marker, "%d", value);',
		"  std::fclose(marker);",
		"  return value == 17 ? 0 : 44;",
		"}",
	}
	write("second.cpp", source)
	write("resource.txt", { "fixture" })
	local presets = {
		version = 6,
		configurePresets = {
			{
				name = "dev",
				generator = "Ninja",
				binaryDir = "${sourceDir}/build/dev",
				cacheVariables = { CMAKE_BUILD_TYPE = "Debug" },
			},
			{ name = "another", generator = "Ninja", binaryDir = "${sourceDir}/build/another" },
		},
		buildPresets = {
			{ name = "dev", configurePreset = "dev" },
			{ name = "another", configurePreset = "another" },
			{
				name = "focused",
				configurePreset = "dev",
				targets = { "$env{TEST_BUILD_TARGET}" },
				environment = { TEST_BUILD_TARGET = "second" },
			},
		},
		testPresets = {
			{
				name = "dev",
				configurePreset = "dev",
				environment = { CHAIN_ENV = "preset" },
				filter = { include = { name = "^selected$" } },
				output = { outputOnFailure = true },
			},
			{ name = "inherited", inherits = "dev" },
			{ name = "different", configurePreset = "another" },
		},
	}
	write("CMakePresets.json", { vim.json.encode(presets) })
	require("lazy").load({ plugins = { "cmake-tools.nvim", "nvim-dap" } })
	local cmake = require("cmake-tools")
	dap = require("dap")
	overseer = require("overseer")
	original_task = overseer.new_task
	overseer.new_task = function(opts)
		local task = original_task(opts)
		tasks[#tasks + 1] = task
		if observe_task then
			observe_task(task)
		end
		return task
	end
	local discovered
	vim.ui.select = function(items, opts, callback)
		assert(opts.prompt == "select test to run", "Unexpected picker: " .. tostring(opts.prompt))
		discovered = items
		for index, item in ipairs(items) do
			if item == "all" then
				callback(item, index)
				return
			end
		end
		error("Missing native test picker")
	end
	vim.ui.input = function()
		error("Target debug must not ask for an executable")
	end
	-- Select a project while Neovim remains in its parent. Native discovery
	-- must find the project's test preset without changing global cwd.
	vim.cmd.cd(vim.fn.fnameescape(root))
	local config = cmake.get_config()
	config.configure_preset, config.build_preset, config.test_preset = "dev", "dev", "dev"
	cmake.select_cwd({ args = project })
	completed(1, "SUCCESS")
	assert(vim.fn.getcwd() == root and config.cwd == project)
	local source_buf = edit("second.cpp", source)
	vim.api.nvim_buf_set_lines(source_buf, -1, -1, false, { "// unsaved before BuildTest" })
	config.build_target = { "first" }
	vim.cmd("CMakeBuildTest")
	completed(3, "SUCCESS")
	assert(not vim.bo[source_buf].modified)
	assert(tasks[2].name:find("Build", 1, true))
	assert(vim.inspect(tasks[3].cmd):find("--preset", 1, true))
	assert(tasks[3].cwd == project and vim.fn.getcwd() == root)
	assert(vim.deep_equal(discovered, { "all", "selected" }), "CTest preset filter was lost")
	assert(vim.fn.readfile(vim.fs.joinpath(project, "test"))[1] == "17", "CTest env/cwd/program failed")
	assert(vim.fn.executable(vim.fs.joinpath(project, "build/dev/first")) == 1)
	assert(vim.fn.executable(vim.fs.joinpath(project, "build/dev/second")) == 1)
	assert(vim.deep_equal(config.build_target, { "first" }), "BuildTest changed the editor's target selection")
	-- Do not infer inherited or mismatched build ownership. Native RunTest
	-- remains available and still lets CTest resolve the inherited preset.
	for _, preset in ipairs({ "inherited", "different" }) do
		config.test_preset = preset
		local count = #tasks
		local accepted, message = pcall(vim.cmd, "CMakeBuildTest")
		assert(accepted or tostring(message):find("native cmake --workflow", 1, true), tostring(message))
		vim.wait(60)
		assert(#tasks == count, "Unprovable preset pair was built/tested")
	end
	config.test_preset = "inherited"
	vim.cmd("CMakeRunTest")
	completed(4, "SUCCESS")
	assert(not tasks[4].name:find("Build", 1, true), "Manual RunTest unexpectedly built")
	config.test_preset = "dev"
	config.base_settings.use_preset = false
	local accepted_disabled, disabled_message = pcall(vim.cmd, "CMakeBuildTest")
	assert(accepted_disabled or tostring(disabled_message):find("native cmake --workflow", 1, true))
	vim.wait(60)
	assert(#tasks == 4, "Disabled preset mode entered the automatic test chain")
	config.base_settings.use_preset = true
	config.build_preset = "focused"
	local focused_count = #tasks
	vim.cmd("CMakeBuildTest")
	completed(focused_count + 2, "SUCCESS")
	assert(vim.inspect(tasks[focused_count + 1].cmd):find("--preset focused", 1, true), "Build preset was lost")
	assert(
		not vim.inspect(tasks[focused_count + 1].cmd):find("--target", 1, true),
		"Native preset targets were overridden"
	)
	config.build_preset = "dev"
	config.build_target = { "first" }
	-- A preset picker opened before a build can return while it is running.
	-- Compare the actual submitted build identity, not the eventual selection.
	local preset_pickers = {}
	vim.ui.select = function(items, opts, callback)
		preset_pickers[opts.prompt] = { items = items, choose = callback }
	end
	cmake.select_build_preset(function() end)
	cmake.select_test_preset(function() end)
	observe_task = function(task)
		task:subscribe("on_start", function()
			preset_pickers["Select cmake build presets"].choose("another")
			preset_pickers["Select cmake test preset"].choose("different")
			wait_for(function()
				return config.configure_preset == "another" and config.test_preset == "different"
			end, "Pending preset selection did not change the in-flight build context")
		end)
	end
	local preset_count = #tasks
	vim.cmd("CMakeBuildTest")
	completed(preset_count + 1, "SUCCESS")
	observe_task = nil
	vim.wait(100)
	assert(#tasks == preset_count + 1, "Changed presets ran tests for a different build")
	assert(
		config.build_preset == "another" and config.test_preset == "different",
		"New user preset selection was overwritten"
	)
	config.configure_preset, config.build_preset, config.test_preset = "dev", "dev", "dev"
	-- Changing the selected build target during a build must also survive.
	observe_task = function(task)
		task:subscribe("on_start", function()
			vim.ui.select = function(items, _, callback)
				for index, item in ipairs(items) do
					if item:find("second", 1, true) then
						callback(item, index)
						return
					end
				end
				error("Missing second build target")
			end
			cmake.select_build_target(false, function() end)
			wait_for(function()
				return vim.deep_equal(config.build_target, { "second" })
			end, "Target picker did not apply")
		end)
	end
	preset_count = #tasks
	vim.cmd("CMakeBuildTest")
	completed(preset_count + 1, "SUCCESS")
	observe_task = nil
	vim.wait(100)
	assert(
		#tasks == preset_count + 1 and vim.deep_equal(config.build_target, { "second" }),
		"New build target was lost or tested"
	)
	local choose
	vim.ui.select = function(_, _, callback)
		choose = callback
	end
	local count = #tasks
	vim.cmd("CMakeBuildTest")
	wait_for(function()
		return choose ~= nil
	end, "Unsaved-edit test picker did not open")
	vim.api.nvim_buf_set_lines(source_buf, -1, -1, false, { "// unsaved after build" })
	local accepted, message = pcall(choose, "all", 1)
	assert(accepted or tostring(message):find("unsaved project changes", 1, true), tostring(message))
	vim.wait(60)
	assert(#tasks == count + 1 and vim.bo[source_buf].modified, "Unsaved late edit ran stale tests")
	-- A saved edit while the test picker is open invalidates the preceding
	-- build, even though modified has returned to false.
	choose = nil
	vim.ui.select = function(_, _, callback)
		choose = callback
	end
	count = #tasks
	vim.cmd("CMakeBuildTest")
	wait_for(function()
		return choose ~= nil
	end, "Test picker did not open")
	vim.api.nvim_buf_set_lines(source_buf, -1, -1, false, { "// saved after build" })
	vim.api.nvim_buf_call(source_buf, function()
		vim.cmd("silent write")
	end)
	accepted, message = pcall(choose, "all", 1)
	assert(accepted or tostring(message):find("changed after build", 1, true), tostring(message))
	vim.wait(60)
	assert(#tasks == count + 1, "Saved late edit ran stale tests")
	choose = nil
	count = #tasks
	vim.cmd("CMakeBuildTest")
	wait_for(function()
		return choose ~= nil
	end, "Second test picker did not open")
	local other = vim.fs.joinpath(root, "other")
	vim.fn.mkdir(other, "p")
	for _, name in ipairs({ "CMakeLists.txt", "CMakePresets.json", "first.cpp", "second.cpp", "resource.txt" }) do
		vim.fn.writefile(vim.fn.readfile(vim.fs.joinpath(project, name)), vim.fs.joinpath(other, name))
	end
	cmake.select_cwd({ args = other })
	completed(count + 2, "SUCCESS")
	accepted, message = pcall(choose, "all", 1)
	assert(accepted or tostring(message):find("changed after build", 1, true), tostring(message))
	vim.wait(60)
	assert(#tasks == count + 2, "Project switch ran tests for an unrelated build")
	cmake.select_cwd({ args = project })
	completed(count + 3, "SUCCESS")
	vim.ui.select = function(items, _, callback)
		callback(items[1], 1)
	end
	-- A compiler failure must leave the old test marker untouched.
	write("test", { "OLD" })
	vim.api.nvim_buf_set_lines(source_buf, 0, -1, false, { "invalid C++" })
	count = #tasks
	vim.cmd("CMakeBuildTest")
	completed(count + 1, "FAILURE")
	vim.wait(60)
	assert(#tasks == count + 1 and vim.fn.readfile(vim.fs.joinpath(project, "test"))[1] == "OLD")
	vim.api.nvim_buf_set_lines(source_buf, 0, -1, false, source)

	-- Break in the selected second target; first exists as a real wrong-target
	-- alternative. Verify stack source, args, env, cwd and runtime exit.
	config.launch_target = "second"
	config.target_settings.second = { args = { "debug" }, env = { CHAIN_ENV = "debug" }, working_dir = project }
	vim.api.nvim_set_current_buf(source_buf)
	vim.cmd("silent write") -- Normal format-on-save may move the breakpoint line.
	local breakpoint_line
	for line, text in ipairs(vim.api.nvim_buf_get_lines(source_buf, 0, -1, false)) do
		if text:find("int value = 17;", 1, true) then
			breakpoint_line = line
		end
	end
	assert(breakpoint_line, "Missing breakpoint statement")
	require("dap.breakpoints").set({}, source_buf, breakpoint_line)
	local stopped, terminated, started = nil, false, 0
	dap.listeners.after.event_initialized.cmake_chain = function()
		started = started + 1
	end
	dap.listeners.after.event_stopped.cmake_chain = function(session, body)
		stopped = { session = session, body = body }
	end
	dap.listeners.after.event_terminated.cmake_chain = function()
		terminated = true
	end
	vim.cmd("CMakeDebug")
	wait_for(function()
		return stopped ~= nil
	end, "codelldb did not reach a source breakpoint")
	assert(stopped.body.reason == "breakpoint", vim.inspect(stopped.body))
	assert(
		vim.uv.fs_realpath(stopped.session.config.program)
			== vim.uv.fs_realpath(vim.fs.joinpath(project, "build/dev/second")),
		vim.inspect(stopped.session.config)
	)
	assert(stopped.session.config.cwd == project)
	local stack
	stopped.session:request("stackTrace", { threadId = stopped.body.threadId }, function(error, response)
		assert(not error, vim.inspect(error))
		stack = response
	end)
	wait_for(function()
		return stack ~= nil
	end, "No DAP stack")
	assert(
		vim.uv.fs_realpath(stack.stackFrames[1].source.path)
			== vim.uv.fs_realpath(vim.fs.joinpath(project, "second.cpp"))
	)
	assert(stack.stackFrames[1].line == breakpoint_line, vim.inspect(stack.stackFrames[1]))
	dap.continue()
	wait_for(function()
		return terminated
	end, "Debug target did not terminate")
	assert(vim.fn.readfile(vim.fs.joinpath(project, "debug"))[1] == "17")
	-- Failed compilation cannot start a second DAP session on the old binary.
	vim.api.nvim_buf_set_lines(source_buf, 0, -1, false, { "invalid C++" })
	count = #tasks
	vim.cmd("CMakeDebug")
	completed(count + 1, "FAILURE")
	vim.wait(100)
	assert(started == 1, "Failed build launched the previous debug binary")
	for _, change in ipairs({ "target", "settings" }) do
		vim.api.nvim_buf_set_lines(source_buf, 0, -1, false, source)
		config.launch_target = "second"
		config.target_settings.second = { args = { "debug" }, env = { CHAIN_ENV = "debug" }, working_dir = project }
		observe_task = function(task)
			task:subscribe("on_start", function()
				if change == "target" then
					vim.ui.select = function(items, _, callback)
						for index, item in ipairs(items) do
							if item:find("first", 1, true) then
								callback(item, index)
								return
							end
						end
						error("Missing first launch target")
					end
					cmake.select_launch_target(false, function() end)
					wait_for(function()
						return config.launch_target == "first"
					end, "Launch target picker did not apply")
				else
					config.target_settings.second.env.CHAIN_ENV = "changed during build"
				end
			end)
		end
		count = #tasks
		vim.cmd("CMakeDebug")
		completed(count + 1, "SUCCESS")
		observe_task = nil
		vim.wait(100)
		assert(started == 1, "Changed debug " .. change .. " launched an old binary")
	end
	config.launch_target = "second"
	config.target_settings.second = { args = { "debug" }, env = { CHAIN_ENV = "debug" }, working_dir = project }
	for _, save in ipairs({ false, true }) do
		vim.api.nvim_buf_set_lines(source_buf, 0, -1, false, source)
		observe_task = function(task)
			task:subscribe("on_complete", function()
				vim.api.nvim_buf_set_lines(source_buf, -1, -1, false, { "// changed during debug build" })
				if save then
					vim.api.nvim_buf_call(source_buf, function()
						vim.cmd("silent write")
					end)
				end
			end)
		end
		count = #tasks
		vim.cmd("CMakeDebug")
		completed(count + 1, "SUCCESS")
		observe_task = nil
		vim.wait(100)
		assert(started == 1, "Changed source launched an old debug binary")
	end
	config.build_type = "Release"
	local cancelled = 0
	vim.ui.select = function(_, opts, callback)
		assert(opts.prompt == "Select build type")
		cancelled = cancelled + 1
		callback(nil)
	end
	count = #tasks
	vim.cmd("CMakeDebug")
	wait_for(function()
		return cancelled > 0
	end, "Debug build-type picker did not open")
	vim.wait(150)
	assert(
		cancelled == 1 and #tasks == count and started == 1,
		"Cancelled debug selection restarted the picker or debugger"
	)
	config.build_type = "Debug"
	print(
		"CMake chain passed: parent cwd, paired presets/filter/env, build failure, late save, real second-target breakpoint"
	)
end, debug.traceback)
vim.ui.select, vim.ui.input = select, input
if dap then
	dap.listeners.after.event_initialized.cmake_chain = nil
	dap.listeners.after.event_stopped.cmake_chain = nil
	dap.listeners.after.event_terminated.cmake_chain = nil
	if dap.session() then
		dap.terminate()
	end
end
if overseer then
	overseer.new_task = original_task
end
for _, buf in ipairs(buffers) do
	if vim.api.nvim_buf_is_valid(buf) then
		vim.api.nvim_buf_delete(buf, { force = true })
	end
end
vim.cmd.cd(vim.fn.fnameescape(cwd))
vim.fn.delete(root, "rf")
if not ok then
	vim.api.nvim_err_writeln(err)
	vim.cmd("cquit 1")
end
io.stdout:write("CMAKE_TEST_DEBUG_COMPLETE\n")
