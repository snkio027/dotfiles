-- Test-only diagnostics. No installer retries, timeout changes or production hooks.
local M = {}

function M.open(name)
	local root = vim.env.DOTFILES_TEST_EVIDENCE_DIR or (vim.fn.stdpath("state") .. "/dotfiles-ci-evidence")
	vim.fn.mkdir(root, "p")
	local path = root .. "/" .. name .. "-" .. vim.fn.getpid()
	local started = vim.uv.hrtime()
	local function record(event, value)
		vim.fn.writefile({
			vim.json.encode({
				elapsed_ms = math.floor((vim.uv.hrtime() - started) / 1e6),
				event = event,
				value = value,
			}),
		}, path .. ".jsonl", "a")
	end
	record("start", { nvim = tostring(vim.version()), log = vim.lsp.log.get_filename() })
	return record, path
end

function M.rust_snapshot(bufnr)
	local snapshot = { stage = "attach", clients = {}, diagnostics = {} }
	for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr, name = "rust-analyzer" })) do
		table.insert(snapshot.clients, {
			id = client.id,
			initialized = client.initialized or false,
			stopped = client:is_stopped(),
			cmd = client.config.cmd,
		})
	end
	if #snapshot.clients == 1 then
		snapshot.stage = snapshot.clients[1].initialized and "clippy-diagnostic" or "initialize"
	end
	for _, d in ipairs(vim.diagnostic.get(bufnr)) do
		table.insert(snapshot.diagnostics, { source = d.source, code = d.code, message = d.message })
		if d.source == "clippy" and d.code == "clone_on_copy" then
			snapshot.lint_received = true
		end
	end
	return snapshot
end

function M.watch_mason(registry, record)
	local observed = {}
	local function watch(handle)
		if observed[handle] then
			return
		end
		observed[handle] = true
		local name = handle.package.name
		record("install-handle", { name = name, state = handle.state })
		-- Bounded, continuously flushed output; failure events remain uncapped.
		local remaining = 1024 * 1024
		for _, stream in ipairs({ "stdout", "stderr" }) do
			handle:on(stream, function(chunk)
				if remaining > 0 then
					local text = chunk:sub(1, remaining)
					remaining = remaining - #text
					record(stream, { name = name, text = text })
					if remaining == 0 then
						record("output-limit", { name = name })
					end
				end
			end)
		end
		handle:on("state:change", function(state)
			record("install-state", { name = name, state = state })
		end)
	end
	registry:on("package:install:handle", watch)
	registry:on("package:install:failed", function(pkg, err)
		record("install-failed", { name = pkg.name, error = tostring(err) })
	end)
	registry:on("package:install:success", function(pkg)
		record("install-success", { name = pkg.name })
	end)
	-- Include handles created by Mason setup before the observer was registered.
	for _, pkg in ipairs(registry.get_all_packages()) do
		pkg:get_install_handle():if_present(watch)
	end
end

function M.mason_snapshot(registry, names)
	local states = {}
	for _, name in ipairs(names) do
		local state = { name = name, registered = registry.has_package(name) }
		if state.registered then
			local pkg = registry.get_package(name)
			state.installed = pkg:is_installed()
			state.installing = pkg:is_installing()
			state.receipt = pkg:get_receipt():is_present()
			pkg:get_install_handle():if_present(function(handle)
				state.handle = handle.state
			end)
		end
		table.insert(states, state)
	end
	return states
end

return M
