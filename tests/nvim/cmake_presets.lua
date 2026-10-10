-- Run with the configured Neovim environment and tests/nvim/run_contract.lua.
-- Both entry points compile real C/C++ sources through a recording launcher.
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
root = assert(vim.uv.fs_realpath(root))
local original_cwd = vim.fn.getcwd()
local join = vim.fs.joinpath
local cmake
local tasks = {}
local overseer, new_task
local observe_task
local buffers = {}
local select, input = vim.ui.select, vim.ui.input

local function command(argv, cwd)
	local result = vim.system(argv, { cwd = cwd, text = true }):wait(30000)
	assert(result.code == 0, table.concat(argv, " ") .. "\n" .. result.stdout .. result.stderr)
end

local function editor_result(method)
	local result
	cmake[method]({ fargs = {} }, function(value)
		result = value
	end)
	assert(
		vim.wait(30000, function()
			return result ~= nil
		end, 20),
		"CMakeTools " .. method .. " timed out"
	)
	return result
end

local function editor_command(method)
	local result = editor_result(method)
	assert(result:is_ok(), "CMakeTools " .. method .. ": " .. tostring(result.message))
end

local function editor_ex(command, expected_tasks)
	local before = #tasks
	vim.cmd(command)
	assert(
		vim.wait(30000, function()
			return #tasks >= before + expected_tasks and tasks[#tasks].status == "SUCCESS"
		end, 20),
		command .. " did not complete its tasks"
	)
	assert(#tasks == before + expected_tasks, command .. " started unexpected tasks")
end

local function edit_buffer(path, lines)
	local buf = path and vim.fn.bufadd(path) or vim.api.nvim_create_buf(true, false)
	vim.fn.bufload(buf)
	buffers[#buffers + 1] = buf
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	return buf
end

local function fixture(dir, managed)
	vim.fn.mkdir(dir, "p")
	vim.fn.writefile({
		"cmake_minimum_required(VERSION 3.25)",
		"project(preset_ownership LANGUAGES C CXX)",
		"add_executable(probe main.cpp helper.c)",
	}, join(dir, "CMakeLists.txt"))
	vim.fn.writefile({
		"#include <cstdio>",
		'extern "C" int helper(void);',
		"int main(int argc, char** argv) {",
		"  if (argc > 1) {",
		'    auto* file = std::fopen(argv[1], "r");',
		"    if (!file) return 47;",
		"    std::fclose(file);",
		"  }",
		"  return helper();",
		"}",
	}, join(dir, "main.cpp"))
	vim.fn.writefile({ "fixture = true" }, join(dir, "config.toml"))
	vim.fn.writefile({ "int helper(void) { return 0; }" }, join(dir, "helper.c"))
	vim.fn.writefile({
		"#!/bin/sh",
		'printf "%s\\n" "$*" >> "$(dirname "$0")/launcher.log"',
		'exec "$@"',
	}, join(dir, "project-launcher"))
	assert(vim.fn.setfperm(join(dir, "project-launcher"), "rwx------") == 1)
	if managed then
		vim.fn.writefile({ "schema_version = 1" }, join(dir, ".cxx.toml"))
	end
	vim.fn.writefile({ "CompileFlags:", "  CompilationDatabase: build/dev" }, join(dir, ".clangd"))
	local presets = { version = 6, configurePresets = {}, buildPresets = {} }
	for _, name in ipairs({ "dev", "san" }) do
		table.insert(presets.configurePresets, {
			name = name,
			generator = "Ninja",
			binaryDir = "${sourceDir}/build/" .. name,
			cacheVariables = {
				CMAKE_BUILD_TYPE = "Debug",
				CMAKE_C_COMPILER_LAUNCHER = "${sourceDir}/project-launcher",
				CMAKE_CXX_COMPILER_LAUNCHER = "${sourceDir}/project-launcher",
				CMAKE_EXPORT_COMPILE_COMMANDS = { type = "BOOL", value = name == "dev" and "ON" or "OFF" },
			},
		})
		table.insert(presets.buildPresets, { name = name, configurePreset = name })
	end
	vim.fn.writefile({ vim.json.encode(presets) }, join(dir, "CMakePresets.json"))
end

local function verify(dir, preset)
	local cache = {}
	for _, line in ipairs(vim.fn.readfile(join(dir, "build", preset, "CMakeCache.txt"))) do
		local key, value = line:match("^(CMAKE_[A-Z_]+):[^=]+=(.*)$")
		if key then
			cache[key] = value
		end
	end
	for _, language in ipairs({ "C", "CXX" }) do
		local launcher = cache["CMAKE_" .. language .. "_COMPILER_LAUNCHER"]
		assert(launcher == join(dir, "project-launcher"), language .. " launcher was replaced: " .. tostring(launcher))
	end
	assert(cache.CMAKE_EXPORT_COMPILE_COMMANDS == (preset == "dev" and "ON" or "OFF"))
	assert((vim.uv.fs_stat(join(dir, "build", preset, "compile_commands.json")) ~= nil) == (preset == "dev"))
	assert(vim.uv.fs_lstat(join(dir, "compile_commands.json")) == nil, "Unexpected root compile database")
	local log = table.concat(vim.fn.readfile(join(dir, "launcher.log")), "\n")
	assert(log:find("main.cpp", 1, true), "Project launcher did not compile C++")
	assert(log:find("helper.c", 1, true), "Project launcher did not compile C")
	command({ join(dir, "build", preset, "probe") }, dir)
end

local ok, err = xpcall(function()
	require("lazy").load({ plugins = { "cmake-tools.nvim" } })
	cmake = require("cmake-tools")
	local guarded_run = cmake.run
	require("config.cmake_workflow").setup()
	assert(cmake.run == guarded_run, "Workflow guard setup is not idempotent")
	overseer = require("overseer")
	new_task = overseer.new_task
	overseer.new_task = function(opts)
		local task = new_task(opts)
		tasks[#tasks + 1] = task
		if observe_task then
			observe_task(task)
		end
		return task
	end
	local effective = require("cmake-tools.const")
	assert(vim.deep_equal(cmake.get_generate_options(), {}), "Plugin defaults still override presets")
	assert(effective.cmake_compile_commands_options.action == "none")
	assert(effective.cmake_regenerate_on_save == true, "Save-time configure preference changed")
	assert(effective.cmake_executor.name == "overseer" and effective.cmake_runner.name == "overseer")
	assert(effective.cmake_dap_configuration.type == "codelldb")
	assert(not effective.cmake_notifications.executor.enabled and not effective.cmake_notifications.runner.enabled)
	assert(type(vim.fn.maparg(" od", "n", false, true).callback) == "function", "Missing run directory shortcut")
	local output = require("config.cmake_output")
	for key, command in pairs({
		ob = "CMakeBuild",
		["or"] = "CMakeRun",
		oc = "CMakeGenerate",
		os = "CMakeSelectLaunchTarget",
		oa = "CMakeLaunchArgs",
	}) do
		assert(vim.fn.maparg(" " .. key, "n"):find(command, 1, true), "Missing CMake shortcut: " .. key)
	end
	for _, case in ipairs({
		{ name = "managed-dev", managed = true, preset = "dev" },
		{ name = "managed-san", managed = true, preset = "san" },
		{ name = "unmanaged-dev", managed = false, preset = "dev" },
	}) do
		for _, entry in ipairs({ "terminal", "editor" }) do
			local dir = join(root, case.name, entry)
			fixture(dir, case.managed)
			if entry == "terminal" then
				command({ "cmake", "--preset", case.preset }, dir)
				command({ "cmake", "--build", "--preset", case.preset }, dir)
			else
				vim.cmd.cd(vim.fn.fnameescape(dir))
				local config = cmake.get_config()
				config.configure_preset = case.preset
				config.build_preset = case.preset
				assert(vim.deep_equal(cmake.get_generate_options(), {}), "Project switch restored global overrides")
				overseer.close()
				local windows = #vim.api.nvim_list_wins()
				editor_command("generate")
				assert(tasks[#tasks].name:find("Configure", 1, true), tasks[#tasks].name)
				editor_command("build")
				assert(#vim.api.nvim_list_wins() == windows, "Successful build opened an output panel")
				local built = tasks[#tasks]
				assert(built.name:find("Build", 1, true), built.name)
				assert(built.exit_code == 0 and built.status == "SUCCESS")
				assert(built:get_component("on_exit_set_status"), "Exit-code authority removed")
				assert(built:get_component("on_output_quickfix"), "Missing build diagnostics")
				assert(vim.bo[built:get_bufnr()].buftype ~= "terminal", "Build diagnostics can be hard-wrapped")
				local rendered = require("config.cmake_output").render(built)
				assert(
					#rendered == 2 and not vim.inspect(rendered):find("exit 0", 1, true),
					"Success summary too noisy"
				)
				assert(#vim.api.nvim_buf_get_lines(built:get_bufnr(), 0, -1, false) > 0, "Raw build log lost")
				config.launch_target = "probe"
				config.target_settings.probe = { args = { "config.toml" }, env = { KEEP_ME = "yes" } }
				local choice
				vim.ui.select = function(_, _, callback)
					choice = callback
				end
				output.select_run_directory()
				choice(nil)
				assert(config.target_settings.probe.working_dir == nil, "Cancel changed the working directory")
				output.select_run_directory()
				choice("Executable directory")
				assert(config.target_settings.probe.working_dir == "${dir.binary}")
				local missing = vim.system({ join(dir, "build", case.preset, "probe"), "config.toml" }, {
					cwd = cmake.get_launch_path("probe"),
				}):wait(10000)
				assert(missing.code == 47, "Missing runtime configuration was not detected")
				output.select_run_directory()
				choice("Project root")
				assert(config.target_settings.probe.working_dir == dir)
				assert(
					config.target_settings.probe.env.KEEP_ME == "yes",
					"Directory selection replaced target settings"
				)
				local session = require("cmake-tools.session")
				session.save(config.cwd, config)
				assert(session.load(config.cwd).target_settings.probe.working_dir == dir, "Run directory not persisted")
				vim.ui.select = select
				local editor_window = vim.api.nvim_get_current_win()
				editor_command("run")
				assert(
					tasks[#tasks].name:find("Run", 1, true) and vim.inspect(tasks[#tasks].cmd):find("probe", 1, true)
				)
				assert(vim.api.nvim_get_current_win() == editor_window, "Run stole editing focus")
				assert(#vim.fn.win_findbuf(tasks[#tasks]:get_bufnr()) > 0, "Program output was not opened")
				assert(tasks[#tasks].exit_code == 0)
				assert(tasks[#tasks].cwd == dir, "Run working_dir was ignored")
				assert(vim.inspect(tasks[#tasks].cmd):find("config.toml", 1, true), "Run arguments were ignored")
				local run_windows = #vim.api.nvim_list_wins()
				editor_command("run")
				assert(#vim.api.nvim_list_wins() == run_windows, "Repeated run created another output window")
			end
			verify(dir, case.preset)
			print("CMake preset ownership passed: " .. case.name .. " / " .. entry)
		end
	end
	local config = cmake.get_config()
	local directory = config.target_settings.probe.working_dir
	local choose, enter
	vim.ui.select = function(_, _, callback)
		choose = callback
	end
	vim.ui.input = function(_, callback)
		enter = callback
	end
	output.select_run_directory()
	choose("Custom directory")
	enter(root .. "/missing")
	assert(config.target_settings.probe.working_dir == directory)
	output.select_run_directory()
	choose("Custom directory")
	enter("relative/path")
	assert(config.target_settings.probe.working_dir == directory)
	output.select_run_directory()
	choose("Custom directory")
	enter(nil)
	assert(config.target_settings.probe.working_dir == directory)
	output.select_run_directory()
	choose("Custom directory")
	enter(root)
	assert(config.target_settings.probe.working_dir == root)
	output.select_run_directory()
	config.launch_target = "different"
	choose("Project root")
	assert(config.target_settings.probe.working_dir == root and config.target_settings.different == nil)
	config.launch_target = "probe"
	config.target_settings.probe.working_dir = directory
	vim.ui.select, vim.ui.input = select, input
	-- Program I/O stays on the native terminal strategy; presentation must not
	-- consume stdin or replace the application's exit-code authority.
	local dir = vim.fn.getcwd()
	vim.fn.writefile({
		"#include <cstdio>",
		'int main() { int value = 0; if (std::scanf("%d", &value) != 1) return 41;',
		'std::printf("RESULT %d\\n", value); return value == 17 ? 0 : 42; }',
	}, join(dir, "main.cpp"))
	local count, result = #tasks, nil
	cmake.run({ fargs = {} }, function(value)
		result = value
	end)
	assert(
		vim.wait(30000, function()
			return #tasks == count + 2 and tasks[#tasks]:is_running()
		end, 20),
		"Interactive program did not start"
	)
	local interactive = tasks[#tasks]
	assert(vim.bo[interactive:get_bufnr()].buftype == "terminal")
	vim.api.nvim_chan_send(interactive.strategy.job_id, "17\n")
	assert(
		vim.wait(10000, function()
			return result ~= nil
		end, 20),
		"Interactive program timed out"
	)
	assert(result:is_ok() and interactive.exit_code == 0)
	assert(
		table.concat(vim.api.nvim_buf_get_lines(interactive:get_bufnr(), 0, -1, false), "\n"):find("RESULT 17", 1, true)
	)
	-- A real compiler failure must never continue into the previously built executable.
	vim.fn.writefile({ "this is not C++" }, join(dir, "main.cpp"))
	count, result = #tasks, nil
	cmake.run({ fargs = {} }, function(value)
		result = value
	end)
	assert(
		vim.wait(30000, function()
			return result ~= nil
		end, 20),
		"Failed build timeout"
	)
	assert(not result:is_ok(), "Failed build reported success")
	assert(#tasks == count + 1, "Failed build launched the old binary")
	local failed = tasks[#tasks]
	assert(failed.status == "FAILURE" and failed.exit_code ~= 0)
	assert(failed:get_component("on_exit_set_status"))
	assert(vim.inspect(require("config.cmake_output").render(failed)):find("exit " .. failed.exit_code, 1, true))
	local navigable = false
	for _, item in ipairs(vim.fn.getqflist()) do
		if item.valid == 1 and vim.api.nvim_buf_get_name(item.bufnr) == join(dir, "main.cpp") then
			navigable = true
		end
	end
	assert(navigable, "Compiler error has no navigable quickfix location: " .. vim.inspect({
		items = vim.fn.getqflist(),
		cwd = dir,
		output = vim.api.nvim_buf_get_lines(failed:get_bufnr(), 0, -1, false),
	}))
	vim.fn.writefile({ "int main() { return 47; }" }, join(dir, "main.cpp"))
	result = nil
	cmake.run({ fargs = {} }, function(value)
		result = value
	end)
	assert(
		vim.wait(30000, function()
			return result ~= nil
		end, 20),
		"Failed run timeout"
	)
	assert(not result:is_ok(), "Nonzero program exit reported success")
	assert(tasks[#tasks - 1].status == "SUCCESS", "Runtime failure was confused with compiler failure")
	assert(tasks[#tasks].name:find("Run", 1, true) and tasks[#tasks].exit_code == 47)
	assert(tasks[#tasks].status == "FAILURE")
	assert(vim.inspect(require("config.cmake_output").render(tasks[#tasks])):find("exit 47", 1, true))

	-- Start without a cache/codemodel or selected target. One command must
	-- configure, select, build and actually run the freshly saved program.
	local fresh = join(root, "first-run")
	fixture(fresh, true)
	vim.cmd.cd(vim.fn.fnameescape(fresh))
	config = cmake.get_config()
	config.configure_preset, config.build_preset = "dev", "dev"
	assert(vim.uv.fs_stat(join(fresh, "build")) == nil)
	assert(config.launch_target == nil)
	vim.ui.select = function(items, _, callback)
		assert(#items == 1, "Expected one executable target: " .. vim.inspect(items))
		callback(items[1], 1)
	end
	local source = join(fresh, "main.cpp")
	local source_buf = edit_buffer(source, {
		"#include <cstdio>",
		'int main() { auto* f = std::fopen("ran.txt", "w"); if (!f) return 41;',
		'std::fputs("FRESH SOURCE", f); std::fclose(f); }',
	})
	local new_header = join(fresh, "new.hpp")
	local header_buf = edit_buffer(new_header, { "#pragma once" })
	local other = fresh .. "-other"
	fixture(other, true)
	local draft = join(other, "main.cpp")
	local old_draft = vim.fn.readfile(draft)
	-- A prefix sibling and a symlink escape must both stay outside ownership.
	local draft_buf = edit_buffer(draft, { "UNSAVED OTHER PROJECT" })
	assert(vim.uv.fs_symlink(other, join(fresh, "external")))
	local linked_buf = edit_buffer(join(fresh, "external", "helper.c"), { "UNSAVED LINKED FILE" })
	local dangling = join(fresh, "dangling.cpp")
	assert(vim.uv.fs_symlink(join(other, "new.cpp"), dangling))
	local dangling_buf = edit_buffer(dangling, { "UNSAVED DANGLING LINK" })
	local unnamed = edit_buffer(nil, { "UNTITLED DRAFT" })
	count = #tasks
	editor_ex("CMakeRun", 3)
	assert(#tasks == count + 3, "First Run did not execute exactly Configure -> Build -> Run")
	for index, stage in ipairs({ "Configure", "Build", "Run" }) do
		assert(tasks[count + index].name:find(stage, 1, true) and tasks[count + index].status == "SUCCESS")
	end
	assert(not vim.bo[source_buf].modified)
	assert(not vim.bo[header_buf].modified and vim.fn.readfile(new_header)[1] == "#pragma once")
	assert(vim.fn.readfile(join(cmake.get_launch_path("probe"), "ran.txt"))[1] == "FRESH SOURCE")
	local function drafts_untouched()
		assert(vim.deep_equal(vim.fn.readfile(draft), old_draft), "Other project draft was written")
		assert(vim.bo[draft_buf].modified and vim.bo[linked_buf].modified and vim.bo[unnamed].modified)
		assert(vim.bo[dangling_buf].modified and not vim.uv.fs_stat(join(other, "new.cpp")))
		assert(vim.fn.readfile(join(other, "helper.c"))[1] == "int helper(void) { return 0; }")
	end
	drafts_untouched()

	-- Failed saves return a failure Result and start no task, not even Build.
	-- Exercise all entry points rather than just a shortcut or a stub backend.
	local saved_source = vim.fn.readfile(source)
	vim.api.nvim_buf_set_lines(source_buf, 0, -1, false, { "int main() { return 47; }" })
	vim.bo[source_buf].readonly = true
	local confirm = vim.o.confirm
	vim.o.confirm = true
	for _, method in ipairs({ "generate", "build", "run" }) do
		count = #tasks
		result = editor_result(method)
		assert(not result:is_ok() and result.message:find("save failed", 1, true), method .. " ignored readonly save")
		assert(#tasks == count, method .. " launched work despite failed save")
		assert(vim.bo[source_buf].modified and vim.deep_equal(vim.fn.readfile(source), saved_source))
		drafts_untouched()
	end
	for _, cmd in ipairs({ "CMakeGenerate", "CMakeBuild", "CMakeRun" }) do
		count = #tasks
		local command_ok, command_error = pcall(vim.cmd, cmd)
		assert(
			command_ok or tostring(command_error):find("CMake stopped: save failed", 1, true),
			tostring(command_error)
		)
		vim.wait(50)
		assert(#tasks == count and vim.bo[source_buf].modified, cmd .. " ignored failed save")
	end
	assert(vim.o.confirm, "Save guard leaked its temporary confirm setting")
	vim.o.confirm = confirm
	vim.bo[source_buf].readonly = false
	for _, event in ipairs({ "BufWritePre", "BufWriteCmd" }) do
		local hook = vim.api.nvim_create_autocmd(event, {
			buffer = source_buf,
			callback = function()
				if event == "BufWritePre" then
					error("INJECTED_SAVE_FAILURE")
				end
				-- BufWriteCmd returning without writing must fail closed too.
			end,
		})
		count = #tasks
		result = editor_result("run")
		vim.api.nvim_del_autocmd(hook)
		assert(not result:is_ok() and result.message:find("save failed", 1, true), event .. " falsely succeeded")
		assert(#tasks == count and vim.bo[source_buf].modified)
		assert(vim.deep_equal(vim.fn.readfile(source), saved_source))
	end

	-- Recovery saves source and CMake edits without recursively configuring
	-- during BufWritePost; normal user-triggered regeneration stays enabled.
	vim.api.nvim_buf_set_lines(source_buf, 0, -1, false, saved_source)
	local cmake_buf = edit_buffer(join(fresh, "CMakeLists.txt"), {
		"cmake_minimum_required(VERSION 3.25)",
		"project(preset_ownership LANGUAGES C CXX)",
		"add_executable(probe main.cpp helper.c)",
		"# unsaved build-system edit",
	})
	count = #tasks
	editor_command("run")
	assert(#tasks == count + 2, "Automatic project save started a nested configure")
	assert(not vim.bo[cmake_buf].modified and not vim.bo[source_buf].modified)
	drafts_untouched()
	for _, cmd in ipairs({ "CMakeBuild", "CMakeGenerate" }) do
		vim.api.nvim_buf_set_lines(source_buf, -1, -1, false, { "// edited before " .. cmd })
		editor_ex(cmd, 1)
		assert(not vim.bo[source_buf].modified, cmd .. " bypassed the save guard")
		drafts_untouched()
	end
	saved_source = vim.fn.readfile(source)

	-- An edit arriving while Build finishes cannot be silently saved just
	-- before Run: that would execute a binary built from older source.
	observe_task = function(task)
		task:subscribe("on_complete", function()
			vim.api.nvim_buf_set_lines(source_buf, 0, -1, false, { "int main() { return 47; }" })
		end)
	end
	count = #tasks
	result = editor_result("run")
	observe_task = nil
	assert(not result:is_ok() and result.message:find("unsaved project changes", 1, true))
	assert(#tasks == count + 1 and tasks[#tasks].status == "SUCCESS", "Late edit still launched an old binary")
	assert(vim.bo[source_buf].modified and vim.deep_equal(vim.fn.readfile(source), saved_source))
	drafts_untouched()

	-- First-run cancellation and real configure errors never progress to Run.
	for _, case in ipairs({ "cancel", "target-cancel", "configure-failure" }) do
		local project = join(root, case)
		fixture(project, true)
		vim.cmd.cd(vim.fn.fnameescape(project))
		config = cmake.get_config()
		local cancelled = false
		vim.ui.select = function(_, _, callback)
			cancelled = true
			callback(nil)
		end
		if case ~= "cancel" then
			config.configure_preset, config.build_preset = "dev", "dev"
			if case == "configure-failure" then
				vim.fn.writefile(
					{ 'message(FATAL_ERROR "INJECTED_CONFIGURE_FAILURE")' },
					join(project, "CMakeLists.txt")
				)
			end
		end
		count = #tasks
		if case == "target-cancel" then
			-- Upstream returns without a callback on target cancel.
			-- Observe the actual picker and completed Configure, not a fabricated Result.
			local completed = false
			cmake.run({ fargs = {} }, function()
				completed = true
			end)
			assert(
				vim.wait(30000, function()
					return cancelled
				end, 20),
				"Target picker was not reached"
			)
			vim.wait(50)
			assert(not completed, "Cancelled target unexpectedly continued")
			assert(tasks[#tasks].status == "SUCCESS")
		else
			result = editor_result("run")
			assert(not result:is_ok(), case .. " falsely succeeded")
		end
		assert(#tasks == count + (case == "cancel" and 0 or 1), case .. " continued into build/run")
	end
	print(
		"CMake build/run safety passed: first run, save failures, isolated drafts, late edits, configure failure/cancel"
	)
end, debug.traceback)

vim.ui.select, vim.ui.input = select, input
if overseer then
	overseer.new_task = new_task
end
for _, buf in ipairs(buffers) do
	if vim.api.nvim_buf_is_valid(buf) then
		vim.api.nvim_buf_delete(buf, { force = true })
	end
end
vim.cmd.cd(vim.fn.fnameescape(original_cwd))
vim.fn.delete(root, "rf")
if not ok then
	vim.api.nvim_err_writeln(err)
	vim.cmd("cquit 1")
end
print("CMake terminal/Neovim preset integration passed: project launchers, database ON/OFF, no root links")
