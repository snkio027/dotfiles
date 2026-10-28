local evidence = dofile("tests/nvim/ci_evidence.lua")
local clients, diagnostics = {}, {}
local original_clients, original_diagnostics = vim.lsp.get_clients, vim.diagnostic.get
vim.lsp.get_clients = function()
	return clients
end
vim.diagnostic.get = function()
	return diagnostics
end
local ok, err = xpcall(function()
	assert(evidence.rust_snapshot(0).stage == "attach")
	clients = {
		{
			id = 1,
			initialized = false,
			config = { cmd = { "rust-analyzer" } },
			is_stopped = function()
				return false
			end,
		},
	}
	assert(evidence.rust_snapshot(0).stage == "initialize")
	clients[1].initialized = true
	assert(evidence.rust_snapshot(0).stage == "clippy-diagnostic")
	diagnostics = { { source = "rustc", code = "clone_on_copy", message = "wrong source" } }
	assert(not evidence.rust_snapshot(0).lint_received)
	diagnostics[1].source = "clippy"
	assert(evidence.rust_snapshot(0).lint_received)
end, debug.traceback)
vim.lsp.get_clients, vim.diagnostic.get = original_clients, original_diagnostics
assert(ok, err)

local function emitter()
	return {
		handlers = {},
		on = function(self, event, fn)
			self.handlers[event] = self.handlers[event] or {}
			table.insert(self.handlers[event], fn)
		end,
		emit = function(self, event, ...)
			for _, fn in ipairs(self.handlers[event] or {}) do
				fn(...)
			end
		end,
	}
end
local registry, handle = emitter(), emitter()
local installed, receipt = false, false
local pkg = {
	name = "gopls",
	is_installed = function()
		return installed
	end,
	is_installing = function()
		return handle.state ~= "CLOSED"
	end,
	get_receipt = function()
		return {
			is_present = function()
				return receipt
			end,
		}
	end,
	get_install_handle = function()
		return {
			if_present = function(_, fn)
				fn(handle)
			end,
		}
	end,
}
handle.package, handle.state = pkg, "QUEUED"
registry.get_all_packages = function()
	return { pkg }
end
registry.has_package = function(name)
	return name == "gopls"
end
registry.get_package = function()
	return pkg
end
local record, path = evidence.open("mason-contract")
evidence.watch_mason(registry, record)
registry:emit("package:install:handle", handle) -- Existing handles must not be observed twice.
handle:emit("stderr", "fetch failed: injected connection reset")
handle.state = "CLOSED"
handle:emit("state:change", handle.state)
registry:emit("package:install:failed", pkg, "installer exited 23")
local states = evidence.mason_snapshot(registry, { "gopls", "unknown" })
assert(not states[1].installed and not states[1].receipt and not states[1].installing)
assert(states[1].handle == "CLOSED" and not states[2].registered)
installed = true
assert(not evidence.mason_snapshot(registry, { "gopls" })[1].receipt, "Missing receipt was hidden")
receipt = true
registry:emit("package:install:success", pkg)
local events = vim.tbl_map(vim.json.decode, vim.fn.readfile(path .. ".jsonl"))
local stderr, failure = 0, false
for _, event in ipairs(events) do
	if event.event == "stderr" then
		stderr = stderr + 1
		assert(event.value.name == "gopls" and event.value.text:find("connection reset", 1, true))
	elseif event.event == "install-failed" then
		failure = event.value.error == "installer exited 23"
	end
end
assert(stderr == 1 and failure, "Installer failure evidence was lost or duplicated")
print("CI evidence contract passed: Rust stages, installer output and receipt state.")
