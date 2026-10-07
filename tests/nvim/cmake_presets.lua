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

local function command(argv, cwd)
	local result = vim.system(argv, { cwd = cwd, text = true }):wait(30000)
	assert(result.code == 0, table.concat(argv, " ") .. "\n" .. result.stdout .. result.stderr)
end

local function editor_command(method)
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
	assert(result:is_ok(), "CMakeTools " .. method .. ": " .. tostring(result.message))
end

local function fixture(dir, managed)
	vim.fn.mkdir(dir, "p")
	vim.fn.writefile({
		"cmake_minimum_required(VERSION 3.25)",
		"project(preset_ownership LANGUAGES C CXX)",
		"add_executable(probe main.cpp helper.c)",
	}, join(dir, "CMakeLists.txt"))
	vim.fn.writefile({ 'extern "C" int helper(void);', "int main() { return helper(); }" }, join(dir, "main.cpp"))
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
	overseer = require("overseer")
	new_task = overseer.new_task
	overseer.new_task = function(opts)
		local task = new_task(opts)
		tasks[#tasks + 1] = task
		return task
	end
	local effective = require("cmake-tools.const")
	assert(vim.deep_equal(cmake.get_generate_options(), {}), "Plugin defaults still override presets")
	assert(effective.cmake_compile_commands_options.action == "none")
	assert(effective.cmake_regenerate_on_save == true, "Save-time configure preference changed")
	assert(effective.cmake_executor.name == "overseer" and effective.cmake_runner.name == "overseer")
	assert(effective.cmake_dap_configuration.type == "codelldb")
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
				editor_command("generate")
				assert(tasks[#tasks].name:find("配置", 1, true), tasks[#tasks].name)
				editor_command("build")
				local built = tasks[#tasks]
				assert(built.name:find("构建", 1, true), built.name)
				assert(built.exit_code == 0 and built.status == "SUCCESS")
				assert(built:get_component("on_exit_set_status"), "Exit-code authority removed")
				assert(built:get_component("on_output_quickfix"), "Missing build diagnostics")
				assert(vim.bo[built:get_bufnr()].buftype ~= "terminal", "Build diagnostics can be hard-wrapped")
				local rendered = require("config.cmake_output").render(built)
				assert(vim.inspect(rendered):find("exit 0", 1, true))
				assert(vim.inspect(rendered):find(dir, 1, true), "Working directory not visible")
				config.launch_target = "probe"
				config.target_settings.probe = { args = { "config.toml" }, working_dir = dir }
				editor_command("run")
				assert(
					tasks[#tasks].name:find("运行", 1, true) and vim.inspect(tasks[#tasks].cmd):find("probe", 1, true)
				)
				assert(tasks[#tasks].exit_code == 0)
				assert(tasks[#tasks].cwd == dir, "Run working_dir was ignored")
				assert(vim.inspect(tasks[#tasks].cmd):find("config.toml", 1, true), "Run arguments were ignored")
			end
			verify(dir, case.preset)
			print("CMake preset ownership passed: " .. case.name .. " / " .. entry)
		end
	end
	-- A real compiler failure must never continue into the previously built executable.
	local dir = vim.fn.getcwd()
	vim.fn.writefile({ "this is not C++" }, join(dir, "main.cpp"))
	local count, result = #tasks, nil
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
	assert(tasks[#tasks].name:find("运行", 1, true) and tasks[#tasks].exit_code == 47)
	assert(tasks[#tasks].status == "FAILURE")
	assert(vim.inspect(require("config.cmake_output").render(tasks[#tasks])):find("exit 47", 1, true))
end, debug.traceback)

if overseer then
	overseer.new_task = new_task
end
vim.cmd.cd(vim.fn.fnameescape(original_cwd))
vim.fn.delete(root, "rf")
if not ok then
	vim.api.nvim_err_writeln(err)
	vim.cmd("cquit 1")
end
print("CMake terminal/Neovim preset integration passed: project launchers, database ON/OFF, no root links")
