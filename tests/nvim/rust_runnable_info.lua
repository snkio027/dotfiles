-- Actual rust-analyzer responses and native runnables menu/consumer; no Cargo execution.
local info = require("config.rust_runnable_info")
-- Headless contracts run before VeryLazy normally loads the public commands.
require("lazyvim.config").load("autocmds")
local root = assert(vim.uv.fs_realpath(assert(vim.uv.fs_mkdtemp(vim.uv.os_tmpdir() .. "/rust-info-XXXXXX"))))
local cwd, select, notify = vim.fn.getcwd(), vim.ui.select, vim.notify
local buffers, projects, observations = {}, {}, {}
local env = { vim.env.CARGO_NET_OFFLINE, vim.env.RUSTUP_AUTO_INSTALL }
vim.env.CARGO_NET_OFFLINE, vim.env.RUSTUP_AUTO_INSTALL = "true", "0"
require("lazy").load({ plugins = { "rustaceanvim" } })
local native = require("rustaceanvim.runnables")
local config = require("rustaceanvim.config.internal")
local status = require("rustaceanvim.server_status")
local statuses, old_status = {}, status.handler
status.handler = function(err, result, ctx, cfg)
	statuses[ctx.client_id] = result
	return old_status(err, result, ctx, cfg)
end
local function wait(label, fn)
	assert(vim.wait(30000, fn, 20), label)
end
local function write(path, lines)
	vim.fn.mkdir(vim.fs.dirname(path), "p")
	vim.fn.writefile(lines, path)
end
local ok, err = xpcall(function()
	for index, name in ipairs({ "a", "b" }) do
		local project = root .. "/" .. name
		projects[index] = project
		write(project .. "/Cargo.toml", {
			"[package]",
			'name = "runnable_' .. name .. '"',
			'version = "0.1.0"',
			'edition = "2021"',
			"[features]",
			'default = ["standard"]',
			"standard = []",
			"fast = []",
		})
		write(
			project .. "/src/main.rs",
			{ 'fn main() { println!("runnable fixture"); }', "#[test] fn works() { assert!(true); }" }
		)
		if index == 2 then
			write(project .. "/.nvim/rust.json", { '{"features":["fast"],"noDefaultFeatures":true}' })
		end
		vim.cmd.cd(project)
		vim.cmd.edit(vim.fn.fnameescape(project .. "/src/main.rs"))
		local buf = vim.api.nvim_get_current_buf()
		buffers[index] = buf
		local client
		wait("Rust client did not become ready", function()
			client = vim.lsp.get_clients({ name = "rust-analyzer", bufnr = buf })[1]
			return client and client.initialized and statuses[client.id] and statuses[client.id].quiescent
		end)
		local reports, choose
		vim.ui.select = function(items, opts, callback)
			assert(opts.kind == "rust-runnable-info", "Unexpected inspection picker")
			reports, choose = items, callback
		end
		assert(vim.fn.exists(":RustRunnableInfo") == 2, "Public inspection command missing")
		vim.cmd.RustRunnableInfo()
		wait("Actual runnable inspection response missing", function()
			return reports ~= nil
		end)
		local source, generic
		for _, report in ipairs(reports) do
			assert(report.request_uri == vim.uri_from_bufnr(buf) and report.client_id == client.id)
			assert(report.client_root == project and report.workspace == project)
			if report.label == "runnable_" .. name then
				source = report
			end
			if report.label:match("^cargo run %-p") then
				generic = report
			end
		end
		if not source then
			for _, report in ipairs(reports) do
				if report.kind == "source Cargo runnable" and report.argv[1] == "run" then
					source = report
				end
			end
		end
		assert(source and generic, "Missing source and generic native runnables: " .. vim.inspect(reports))
		assert(source.kind == "source Cargo runnable" and generic.kind == "generic Cargo runnable (no source location)")
		if index == 2 then
			assert(vim.tbl_contains(source.flags.features, "fast") and source.flags.no_default_features)
			assert(
				#generic.flags.features == 0 and not generic.flags.no_default_features,
				"Generic Cargo defaults were relabeled as selected source features"
			)
		end
		choose(source)
		local float = vim.api.nvim_get_current_win()
		local preview = vim.api.nvim_get_current_buf()
		assert(vim.bo[preview].buftype == "nofile" and not vim.bo[preview].modifiable)
		assert(table.concat(vim.api.nvim_buf_get_lines(preview, 0, -1, false), "\n"):find(project, 1, true))
		local close = vim.fn.maparg("q", "n", false, true)
		assert(type(close.callback) == "function")
		close.callback()
		assert(not vim.api.nvim_win_is_valid(float), "Preview close did not own its window")

		-- Same actual LSP request through native RustLsp runnables and its original consumer.
		local saved, captured = {}, nil
		for _, key in ipairs({ "executor", "test_executor", "crate_test_executor" }) do
			saved[key] = config.tools[key]
			config.tools[key] = {
				execute_command = function(command, argv, dir)
					captured = { command = command, argv = vim.deepcopy(argv), cwd = dir }
				end,
			}
		end
		for _, expected in ipairs({ source, generic }) do
			captured = nil
			vim.ui.select = function(items, opts, callback)
				assert(opts.kind == "rust-tools/runnables", "Native execution picker changed")
				for choice, label in ipairs(items) do
					if label == expected.label then
						callback(label, choice)
						return
					end
				end
				error("Native choice not found: " .. expected.label)
			end
			native.runnables()
			wait("Native executor boundary not reached", function()
				return captured ~= nil
			end)
			assert(captured.command == expected.command and captured.cwd == expected.cwd)
			assert(vim.deep_equal(captured.argv, expected.argv), "RUST_NATIVE_COMMAND_PREVIEW_MISMATCH")
		end
		for key, value in pairs(saved) do
			config.tools[key] = value
		end
		observations[#observations + 1] = { project = project, source = source, generic = generic }
	end

	-- More than one offered client needs an explicit source choice, never first-client guessing.
	vim.api.nvim_set_current_buf(buffers[1])
	local ra = require("rustaceanvim.rust_analyzer")
	local active = ra.get_active_rustaceanvim_clients
	local client_a = assert(vim.lsp.get_clients({ name = "rust-analyzer", bufnr = buffers[1] })[1])
	local client_b = assert(vim.lsp.get_clients({ name = "rust-analyzer", bufnr = buffers[2] })[1])
	local picked, inspected
	ra.get_active_rustaceanvim_clients = function()
		return { client_a, client_b }
	end
	vim.ui.select = function(items, opts, callback)
		if opts.kind == "rust-runnable-info" then
			inspected = items
			return
		end
		assert(#items == 2 and opts.prompt:find("Inspect Rust client", 1, true))
		picked = true
		callback(items[1])
	end
	info.inspect(buffers[1])
	wait("Explicit Rust client choice did not return source facts", function()
		return inspected ~= nil
	end)
	assert(picked and inspected[1].client_id == client_a.id and inspected[1].workspace == projects[1])
	local request, calls = client_a.request, 0
	client_a.request = function(...)
		calls = calls + 1
		return request(...)
	end
	vim.ui.select = function(_, _, callback)
		callback(nil)
	end
	info.inspect(buffers[1])
	assert(calls == 0, "Cancelled client selection sent a request")
	client_a.request, ra.get_active_rustaceanvim_clients = request, active

	-- A response queued for A may not open an A preview over a now-selected B.
	vim.api.nvim_set_current_buf(buffers[1])
	local client = assert(vim.lsp.get_clients({ name = "rust-analyzer", bufnr = buffers[1] })[1])
	local request, delayed, warning = client.request, nil, nil
	client.request = function(_, _, _, callback)
		delayed = callback
		return true, 1
	end
	vim.ui.select = function()
		error("Stale source request opened a picker")
	end
	vim.notify = function(message)
		warning = message
	end
	info.inspect(buffers[1])
	vim.api.nvim_set_current_buf(buffers[2])
	assert(delayed)
	delayed(nil, {})
	assert(warning and warning:find("expired", 1, true), "Project switch did not expire response")
	vim.api.nvim_set_current_buf(buffers[1])
	local source_window = vim.api.nvim_get_current_win()
	warning = nil
	info.inspect(buffers[1])
	vim.cmd.vsplit()
	local other_window = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(other_window, buffers[2])
	delayed(nil, {})
	assert(warning and warning:find("expired", 1, true), "Window switch did not expire response")
	vim.api.nvim_win_close(other_window, true)
	vim.api.nvim_set_current_win(source_window)
	vim.api.nvim_set_current_buf(buffers[1])
	warning = nil
	info.inspect(buffers[1])
	vim.api.nvim_buf_set_lines(buffers[1], -1, -1, false, { "// changed after request" })
	delayed(nil, {})
	assert(warning and warning:find("expired", 1, true), "Source edit did not expire response")
	client.request = request
	vim.notify = notify
	-- The installed Snacks picker closes before its scheduled choice callback.
	-- This must keep the source-window identity guard usable with the real UI.
	vim.ui.select = require("snacks.picker.select").select
	vim.cmd.RustRunnableInfo()
	local picker
	wait("Native Snacks inspection picker missing", function()
		local active_pickers = Snacks.picker.get({ source = "select" })
		picker = active_pickers[1]
		return picker and #picker:items() > 0
	end)
	vim.fn.feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "xt")
	wait("Native Snacks choice did not open the owned report", function()
		return vim.bo.filetype == "rust-runnable-info"
	end)
	local report_window = vim.api.nvim_get_current_win()
	assert(report_window ~= source_window and vim.api.nvim_win_get_buf(source_window) == buffers[1])
	vim.fn.feedkeys("q", "xt")
	assert(not vim.api.nvim_win_is_valid(report_window) and vim.api.nvim_get_current_win() == source_window)
	print("RUST_RUNNABLE_INFO_EVIDENCE " .. vim.json.encode(observations))
end, debug.traceback)
vim.ui.select, vim.notify, status.handler = select, notify, old_status
for _, buf in ipairs(buffers) do
	for _, client in ipairs(vim.lsp.get_clients({ name = "rust-analyzer", bufnr = buf })) do
		client:stop(true)
	end
	if vim.api.nvim_buf_is_valid(buf) then
		vim.api.nvim_buf_delete(buf, { force = true })
	end
end
vim.cmd.cd(vim.fn.fnameescape(cwd))
vim.env.CARGO_NET_OFFLINE, vim.env.RUSTUP_AUTO_INSTALL = env[1], env[2]
vim.fn.delete(root, "rf")
assert(ok, err)
print("RUST_RUNNABLE_INFO_COMPLETE")
