-- Native command calculation/consumer parity without running Cargo or changing configuration.
local info = require("config.rust_runnable_info")
local native = require("rustaceanvim.runnables")
local config = require("rustaceanvim.config.internal")
local ra = require("rustaceanvim.rust_analyzer")
local source = {
	label = "test source_test",
	kind = "cargo",
	location = {
		targetUri = "file:///project-a/src/lib.rs",
		targetRange = { start = { line = 1 }, ["end"] = { line = 3 } },
	},
	args = {
		workspaceRoot = "/project-a",
		cwd = "/project-a/member",
		cargoArgs = { "test", "--features", "fast,simd", "--no-default-features", "--target=fixture-target" },
		cargoExtraArgs = { "--locked" },
		executableArgs = { "source_test", "--exact", "--target", "not-a-cargo-target" },
		environment = { SECRET_FIXTURE_VALUE = "DO_NOT_DISPLAY_THIS_VALUE" },
	},
}
local generic = {
	label = "cargo test -p project-b",
	args = { workspaceRoot = "/project-b", cargoArgs = { "test", "-p", "project-b" }, executableArgs = {} },
}
local old = {
	nextest = config.tools.enable_nextest,
	override = config.tools.cargo_override,
	select = vim.ui.select,
	request = ra.buf_request,
	active = ra.get_active_rustaceanvim_clients,
}
local executors = {}
for _, key in ipairs({ "executor", "test_executor", "crate_test_executor" }) do
	executors[key] = config.tools[key]
end
local ok, err = xpcall(function()
	config.tools.enable_nextest = false
	config.tools.cargo_override = nil
	local snapshot = vim.deepcopy({ source, generic })
	local first = info.describe(source, { uri = "file:///project-a/src/lib.rs", id = 12, root = "/project-a" })
	assert(first.kind == "source Cargo runnable" and first.cwd == "/project-a" and first.workspace == "/project-a")
	assert(vim.deep_equal(first.flags.features, { "fast,simd" }) and first.flags.no_default_features)
	assert(vim.deep_equal(first.flags.targets, { "fixture-target" }), "Executable flags leaked into Cargo flags")
	assert(not table.concat(info.lines(first), "\n"):find("DO_NOT_DISPLAY_THIS_VALUE", 1, true), "Environment leaked")
	local second = info.describe(generic, { uri = "file:///project-b/src/lib.rs", id = 13, root = "/project-b" })
	assert(second.kind == "generic Cargo runnable (no source location)", "RUST_GENERIC_SOURCE_CONFUSION")
	assert(#second.flags.features == 0 and #second.flags.targets == 0 and not second.flags.no_default_features)
	assert(
		table.concat(info.lines(second), "\n"):find("not declared", 1, true),
		"Absent flags were presented as resolved defaults"
	)
	assert(vim.deep_equal(snapshot, { source, generic }), "Inspection mutated native runnable")
	assert(
		info.describe({ args = { program = "sh", args = { "-c", "echo fixture" }, cwd = "/shell" } }).cwd == "/shell"
	)
	assert(info.describe({}).unavailable and info.describe({}).workspace == "unavailable")
	local missing = info.describe({ label = "test no root", args = { cargoArgs = { "test" }, executableArgs = {} } })
	assert(missing.cwd == "unavailable", "Missing root was guessed from ambient cwd")
	-- Legal project paths may contain newlines; summary lines feed ProjectTools' buffer API.
	ra.get_active_rustaceanvim_clients = function()
		return { { id = 71, config = { root_dir = "/project\nwith-newline" } } }
	end
	local summary = info.summary_lines(0)
	for _, line in ipairs(summary) do
		assert(not line:find("\n", 1, true), "RUST_SUMMARY_RAW_NEWLINE")
	end
	assert(summary[2]:find(vim.json.encode("/project\nwith-newline"), 1, true))
	local preview = vim.api.nvim_create_buf(false, true)
	local rendered, render_error = pcall(vim.api.nvim_buf_set_lines, preview, 0, -1, false, summary)
	vim.api.nvim_buf_delete(preview, { force = true })
	assert(rendered, render_error)
	-- Exercise ProjectTools' actual public report buffer and owned close action.
	require("lazyvim.config").load("autocmds")
	local original_buffer, original_window = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
	local source_buffer = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_set_current_buf(source_buffer)
	vim.cmd("noautocmd setfiletype rust")
	vim.cmd.ProjectTools()
	local report_window = vim.api.nvim_get_current_win()
	assert(report_window ~= original_window and vim.bo.buftype == "nofile" and not vim.bo.modifiable)
	local rendered_summary = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
	assert(rendered_summary:find(vim.json.encode("/project\nwith-newline"), 1, true))
	vim.fn.feedkeys("q", "xt")
	assert(not vim.api.nvim_win_is_valid(report_window) and vim.api.nvim_get_current_win() == original_window)
	vim.api.nvim_set_current_buf(original_buffer)
	vim.api.nvim_buf_delete(source_buffer, { force = true })
	ra.get_active_rustaceanvim_clients = old.active

	-- Use the real native picker and execution consumer; capture the executor boundary only.
	local captured, requested
	ra.buf_request = function(_, method, _, callback)
		requested = method
		callback(nil, { source, generic })
		return true
	end
	local function execute(command, args, cwd, opts)
		captured = { command = command, argv = vim.deepcopy(args), cwd = cwd, env = opts.env }
	end
	for key in pairs(executors) do
		config.tools[key] = { execute_command = execute }
	end
	for choice, expected in ipairs({ first, second }) do
		vim.ui.select = function(items, opts, select)
			assert(opts.kind == "rust-tools/runnables" and #items == 2, "Native menu replaced")
			assert(items[1] == source.label and items[2] == generic.label, "Inspection changed native labels")
			select(items[choice], choice)
		end
		native.runnables()
		assert(requested == "experimental/runnables" and captured)
		assert(captured.command == expected.command and captured.cwd == expected.cwd)
		assert(vim.deep_equal(captured.argv, expected.argv), "RUST_NATIVE_COMMAND_PREVIEW_MISMATCH")
	end
	assert(captured.cwd == "/project-b", "Generic command reused previous project's root")
	config.tools.cargo_override = "custom-cargo"
	assert(info.describe(source).command == "custom-cargo", "Native executable override ignored")
	config.tools.cargo_override = nil

	-- Native nextest conversion creates a cache file; inspecting it must not do so.
	local executable = vim.fn.executable
	local cache = require("rustaceanvim.cache")
	local nextest_path = cache.nextest_config_path
	config.tools.enable_nextest = true
	vim.fn.executable = function(name)
		return name == "cargo-nextest" and 1 or executable(name)
	end
	cache.nextest_config_path = function()
		error("Read-only inspection attempted to create nextest cache")
	end
	local success, result = pcall(info.describe, source)
	vim.fn.executable, cache.nextest_config_path = executable, nextest_path
	assert(success and not result.command and result.unavailable:find("may write", 1, true))
end, debug.traceback)
config.tools.enable_nextest, config.tools.cargo_override = old.nextest, old.override
vim.ui.select, ra.buf_request = old.select, old.request
ra.get_active_rustaceanvim_clients = old.active
for key, value in pairs(executors) do
	config.tools[key] = value
end
assert(ok, err)
print("RUST_RUNNABLE_INFO_CONTRACT_COMPLETE")
