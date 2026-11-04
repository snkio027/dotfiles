-- Real RA discovery -> existing Neotest adapter -> Cargo -> codelldb. Fixtures
-- use only std and the installed toolchain: no downloads or tool installs.
local root = vim.fn.stdpath("state") .. "/rust-workflow-" .. vim.fn.getpid()
vim.fn.mkdir(root, "p")
root = assert(vim.uv.fs_realpath(root))
local cwd = vim.fn.getcwd()
local env = {
	RUSTUP_AUTO_INSTALL = vim.env.RUSTUP_AUTO_INSTALL,
	CARGO_NET_OFFLINE = vim.env.CARGO_NET_OFFLINE,
	CARGO_TARGET_DIR = vim.env.CARGO_TARGET_DIR,
}
vim.env.RUSTUP_AUTO_INSTALL, vim.env.CARGO_NET_OFFLINE, vim.env.CARGO_TARGET_DIR = "0", "true", nil
local buffers, observations = {}, {}
local dap, listener = nil, "rust_workflow_contract"
local completed, discovered = {}, {}
local public_client
local plugin = require("lazy.core.config").plugins.neotest
local configure = plugin.config
plugin.config = function(spec, opts)
	opts.log_level = vim.log.levels.DEBUG
	opts.consumers = opts.consumers or {}
	opts.consumers.rust_workflow = function(client)
		public_client = client
		client.listeners.discover_positions = function(_, tree)
			for _, node in tree:iter_nodes() do
				discovered[node:data().id] = node:data()
			end
		end
		client.listeners.results = function(_, results, partial)
			if not partial then
				for id, result in pairs(results) do
					completed[id] = result
				end
			end
		end
		return {}
	end
	configure(spec, opts)
end
require("lazy").load({ plugins = { "rustaceanvim", "neotest", "nvim-dap" } })
plugin.config = configure
local debuggables = require("rustaceanvim.commands.debuggables")
local original_autoload = debuggables.add_dap_debuggables
local eager_builds = 0
debuggables.add_dap_debuggables = function(...)
	eager_builds = eager_builds + 1
	return original_autoload(...)
end
local statuses = {}
local status = require("rustaceanvim.server_status")
local original_status = status.handler
status.handler = function(err, result, ctx, config)
	statuses[ctx.client_id] = result
	observations[#observations + 1] = { status = result, client = ctx.client_id }
	return original_status(err, result, ctx, config)
end
local function wait(label, fn, timeout)
	assert(vim.wait(timeout or 30000, fn, 50), label)
end
local function command(argv, project)
	local result = vim.system(argv, { cwd = project or root, text = true }):wait(60000)
	observations[#observations + 1] =
		{ argv = argv, cwd = project, code = result.code, stdout = result.stdout, stderr = result.stderr }
	return result
end
local function write(path, lines)
	vim.fn.mkdir(vim.fs.dirname(path), "p")
	vim.fn.writefile(lines, path)
end
local function edit(path)
	vim.cmd.edit(vim.fn.fnameescape(path))
	local buf = vim.api.nvim_get_current_buf()
	buffers[#buffers + 1] = buf
	return buf
end
local function async(fn)
	local done, ok, value
	require("nio").run(function()
		ok, value = xpcall(fn, debug.traceback)
		done = true
	end)
	wait("Rust asynchronous operation did not finish", function()
		return done
	end, 60000)
	assert(ok, value)
	return value
end
local function ready(buf)
	local client, runnables
	wait("Rust runnable discovery did not initialize", function()
		client = vim.lsp.get_clients({ name = "rust-analyzer", bufnr = buf })[1]
		if not client or not client.initialized or not (statuses[client.id] and statuses[client.id].quiescent) then
			return false
		end
		local response = client:request_sync(
			"experimental/runnables",
			{ textDocument = { uri = vim.uri_from_bufnr(buf) } },
			2000,
			buf
		)
		runnables = response and response.result
		for _, item in ipairs(type(runnables) == "table" and runnables or {}) do
			if item.args and item.args.cargoArgs then
				if vim.api.nvim_buf_get_name(buf):match("/main%.rs$") and item.args.cargoArgs[1] == "run" then
					return true
				end
				if vim.tbl_contains(item.args.executableArgs or {}, "workflow_pass") then
					return true
				end
			end
		end
		return false
	end, 45000)
	return client, runnables
end
local function breakpoint(config, buf, line, project)
	require("dap.breakpoints").clear()
	require("dap.breakpoints").set({}, buf, line)
	local stopped, exited = false, nil
	dap.listeners.after.event_stopped[listener] = function(_, body)
		observations[#observations + 1] = { stop = body, config = config }
		stopped = true
	end
	dap.listeners.after.event_exited[listener] = function(_, body)
		observations[#observations + 1] = { exited = body }
		exited = body.exitCode
	end
	dap.run(config)
	wait("Rust source breakpoint was not reached", function()
		return stopped or exited ~= nil
	end)
	assert(stopped, "Rust process exited before its breakpoint: " .. tostring(exited))
	local session = assert(dap.session())
	assert(session.config.type == "codelldb", "Rust debugger ownership changed")
	wait("Rust frame missing", function()
		return session.current_frame ~= nil
	end)
	assert(session.current_frame.line == line, "Rust breakpoint line mismatch")
	assert(
		vim.uv.fs_realpath(session.current_frame.source.path) == vim.api.nvim_buf_get_name(buf),
		"Rust breakpoint source mismatch"
	)
	assert(vim.uv.fs_realpath(session.config.cwd) == project, "Rust debugger selected another project")
	-- An assertion can map to several machine-code locations on the same source
	-- line. After proving the stop, remove it before requiring normal exit.
	dap.clear_breakpoints()
	dap.continue()
	wait("Rust debug process did not exit", function()
		return exited ~= nil and dap.session() == nil
	end)
	assert(exited == 0, "Rust debug process failed")
end
local ok, err = xpcall(function()
	assert(
		require("rustaceanvim.config.internal").dap.autoload_configurations == false,
		"Rust still eagerly builds debugger configurations"
	)
	local version = command({ "rustc", "-vV" })
	assert(version.code == 0, version.stderr)
	local host = assert(version.stdout:match("host: ([^\n]+)"))
	vim.cmd.cd(root)
	for index, name in ipairs({ "defaults", "defaults_selected" }) do
		local project = root .. "/" .. name
		local expected = index == 1 and 11 or 7
		local source_root = index == 2 and project .. "/app" or project
		if index == 2 then
			write(project .. "/Cargo.toml", { "[workspace]", 'members = ["app", "utility"]', 'resolver = "3"' })
			write(
				project .. "/utility/Cargo.toml",
				{ "[package]", 'name="utility"', 'version="0.0.0"', 'edition="2024"' }
			)
			write(project .. "/utility/src/lib.rs", { "pub fn value() -> i32 { 19 }" })
		end
		write(source_root .. "/Cargo.toml", {
			"[package]",
			'name = "workflow_' .. name .. '"',
			'version = "0.0.0"',
			'edition = "2024"',
			"[features]",
			'default = ["slow"]',
			"fast = []",
			"slow = []",
		})
		write(source_root .. "/src/lib.rs", {
			'#[cfg(all(feature = "fast", feature = "slow"))]',
			'compile_error!("mutually exclusive features");',
			"pub fn value() -> i32 {",
			'    if cfg!(feature = "fast") { 7 } else if cfg!(feature = "slow") { 11 } else { 0 }',
			"}",
			"#[test]",
			"fn workflow_pass() {",
			"    let actual = value();",
			"    assert_eq!(actual, " .. expected .. ");",
			"}",
			"#[test]",
			"#[ignore]",
			'fn workflow_failure() { assert!(false, "intentional regression fixture"); }',
		})
		write(source_root .. "/src/main.rs", {
			"fn main() {",
			"    let actual = workflow_" .. name .. "::value();",
			"    assert_eq!(actual, " .. expected .. ");",
			'    assert_eq!(std::fs::read_to_string("resource.txt").unwrap().trim(), "' .. name .. '");',
			"}",
		})
		write(project .. "/resource.txt", { name })
		if index == 2 then
			write(
				project .. "/.nvim/rust.json",
				{ vim.json.encode({ features = { "fast" }, noDefaultFeatures = true, target = host }) }
			)
		end
		local buf = edit(source_root .. "/src/lib.rs")
		local client, runnables = ready(buf)
		assert(eager_builds == 0, "Opening Rust started an eager debugger build")
		assert(
			vim.fn.executable(
				project .. "/target/" .. (index == 2 and (host .. "/") or "") .. "debug/workflow_" .. name
			) == 0,
			"Rust binary built before explicit test/debug action"
		)
		local ra = client.config.settings["rust-analyzer"]
		assert(ra.cargo.allFeatures == false, "Rust still enables every feature globally")
		assert(ra.check.command == "clippy", "Rust diagnostics no longer use Clippy")
		assert(client.config.cmd[1] == LazyVim.opts("rustaceanvim").server.cmd[1], "Rust analyzer ownership changed")
		if index == 2 then
			assert(
				vim.deep_equal(ra.cargo.features, { "fast" }) and ra.cargo.noDefaultFeatures and ra.cargo.target == host,
				"Project Rust settings were lost"
			)
		end
		require("lazy").load({ plugins = { "neotest", "nvim-dap" } })
		dap = require("dap")
		dap.set_log_level("TRACE")
		local adapter = require("rustaceanvim.neotest")
		observations[#observations + 1] = {
			before_discovery = {
				root = client.config.root_dir,
				path = source_root .. "/src/lib.rs",
				supports = client:supports_method("experimental/runnables"),
				runnables = runnables,
				state = client:is_stopped(),
				matches = #vim.lsp.get_clients({ name = "rust-analyzer", method = "experimental/runnables" }),
			},
		}

		local original_request = client.request
		client.request = function(self, method, params, callback, request_buf)
			if method == "experimental/runnables" then
				return original_request(self, method, params, function(response_error, result, ...)
					observations[#observations + 1] = {
						adapter_response = {
							error = response_error,
							result = result,
							params = params,
							buffer = request_buf,
						},
					}
					return callback(response_error, result, ...)
				end, request_buf)
			end
			return original_request(self, method, params, callback, request_buf)
		end
		local tree = async(function()
			return adapter.discover_positions(source_root .. "/src/lib.rs")
		end)
		local pass, failure
		for _, node in tree:iter_nodes() do
			if node:data().name == "workflow_pass" then
				pass = node
			end
			if node:data().name == "workflow_failure" then
				failure = node
			end
		end
		observations[#observations + 1] = { discovery = tree:to_list(), runnables = runnables, settings = ra }
		assert(pass and failure, "Rust real tests were not discovered: " .. vim.inspect(tree:to_list()))
		local function run_test(node, status)
			local spec = async(function()
				return adapter.build_spec({ tree = node })
			end)
			assert(spec.cwd == project, "Rust Neotest used another project")
			if index == 2 then
				local args = table.concat(spec.command, " ")
				assert(
					args:find("--features", 1, true)
						and args:find("fast", 1, true)
						and args:find("--no-default-features", 1, true),
					"Rust runnable lost project features: " .. args
				)
				assert(args:find(host, 1, true), "Rust runnable lost project target: " .. args)
			end
			local result = command(spec.command, spec.cwd)
			local output = project .. "/test-output.txt"
			write(output, vim.split(result.stdout .. result.stderr, "\n", { plain = true }))
			local results = async(function()
				return adapter.results(spec, { code = result.code, output = output })
			end)
			assert(results[node:data().id].status == status, "Rust Neotest status mismatch")
			assert(
				(status == "passed" and result.code == 0) or (status == "failed" and result.code ~= 0),
				"Cargo exit status mismatch"
			)
		end
		local test_file = source_root .. "/src/lib.rs"
		require("neotest").summary.open()
		observations[#observations + 1] = {
			public_adapters = async(function()
				local items = {}
				for _, id in ipairs(public_client:get_adapters()) do
					local positions = public_client:get_position(nil, { adapter = id })
					items[#items + 1] = { id = id, tree = positions and positions:to_list() }
				end
				return items
			end),
		}
		wait("Public Rust Neotest discovery did not show the real test", function()
			return discovered[pass:data().id] ~= nil
		end, 30000)
		require("neotest").run.run(test_file)
		wait("Public Rust Neotest file run did not complete", function()
			return completed[test_file] ~= nil
		end, 60000)
		assert(completed[test_file].status == "passed", "Public Rust Neotest file run failed")
		observations[#observations + 1] = { public_neotest_file = test_file, result = completed[test_file] }
		run_test(pass, "passed")
		run_test(failure, "failed") -- Ignored tests run explicitly through RA's --ignored runnable.
		local test_spec = async(function()
			return adapter.build_spec({ tree = pass, strategy = "dap" })
		end)
		if index == 2 then
			assert(
				test_spec.strategy.program:find("/target/" .. host .. "/debug/", 1, true),
				"Rust test debugger lost selected target"
			)
		end
		breakpoint(assert(test_spec.strategy), buf, 9, project)
		local main = edit(source_root .. "/src/main.rs")
		local _, binaries = ready(main)
		local selected
		for _, runnable in ipairs(binaries) do
			if
				runnable.args
				and runnable.args.cargoArgs
				and runnable.args.cargoArgs[1] == "run"
				and vim.tbl_contains(runnable.args.cargoArgs, "--bin")
				and runnable.location
				and runnable.location.targetUri == vim.uri_from_bufnr(main)
			then
				selected = runnable
			end
		end
		assert(selected, "Rust binary runnable missing")
		local args = vim.deepcopy(selected.args)
		require("rustaceanvim.overrides").sanitize_command_for_debugging(args.cargoArgs)
		local config, build_error
		require("rustaceanvim.dap").start(args, true, function(value)
			config = value
		end, function(value)
			build_error = value
		end)
		wait("Rust binary debug build did not finish", function()
			return config or build_error
		end)
		assert(config, build_error)
		if index == 2 then
			assert(
				config.program:find("/target/" .. host .. "/debug/", 1, true),
				"Rust binary debugger lost selected target"
			)
		end
		breakpoint(config, main, 3, project)
		assert(vim.fn.getcwd() == root, "Rust workflow changed editor cwd")
		observations[#observations + 1] = { project = project, settings = ra, runnables = runnables, breakpoints = 2 }
		print("RUST_WORKFLOW_PROJECT_COMPLETE: " .. name)
	end
	local defaults = LazyVim.opts("rustaceanvim").server.default_settings
	local settings = require("config.rust_context").settings(root .. "/defaults", defaults)
	assert(settings["rust-analyzer"].cargo.features == nil, "Selected features leaked into another project")
	write(root .. "/defaults/.nvim/rust.json", { '{"features":42}' })
	assert(
		not pcall(require("config.rust_context").settings, root .. "/defaults", defaults),
		"Malformed project settings were silently ignored"
	)
end, debug.traceback)
debuggables.add_dap_debuggables = original_autoload
observations[#observations + 1] = { eager_debug_builds = eager_builds }
status.handler = original_status
write(root .. "/evidence.json", { vim.json.encode(observations) })
io.stdout:write("RUST_WORKFLOW_EVIDENCE: " .. root .. "/evidence.json\n")
if dap then
	dap.listeners.after.event_stopped[listener], dap.listeners.after.event_exited[listener] = nil, nil
	if dap.session() then
		dap.terminate()
		vim.wait(5000, function()
			return dap.session() == nil
		end)
	end
	require("dap.breakpoints").clear()
end
for _, client in ipairs(vim.lsp.get_clients({ name = "rust-analyzer" })) do
	client:stop()
end
wait("Rust clients did not stop", function()
	return #vim.lsp.get_clients({ name = "rust-analyzer" }) == 0
end, 10000)
for _, buf in ipairs(buffers) do
	if vim.api.nvim_buf_is_valid(buf) then
		vim.api.nvim_buf_delete(buf, { force = true })
	end
end
vim.cmd.cd(cwd)
for _, name in ipairs({ "RUSTUP_AUTO_INSTALL", "CARGO_NET_OFFLINE", "CARGO_TARGET_DIR" }) do
	vim.env[name] = env[name]
end
assert(ok, err)
assert(eager_builds == 0, "Rust startup eagerly rebuilt debug artifacts")
print("RUST_WORKFLOW_COMPLETE: actual default/selected feature tests, failures, four breakpoints and project isolation")
io.stdout:write("RUST_WORKFLOW_COMPLETE\n")
