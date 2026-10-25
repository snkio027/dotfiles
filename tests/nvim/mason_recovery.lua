-- Exercise the real command registration and policy without installing tools.
local policy = require("config.mason")
local original_registry = package.loaded["mason-registry"]
local original_installer = package.loaded["mason-tool-installer"]
local original_lazyvim = _G.LazyVim
local original_wait = vim.wait
local original_notify = vim.notify
local original_settings = package.loaded["mason-lspconfig.settings"]
local original_mappings = package.loaded["mason-lspconfig.mappings"]
local original_package = package.loaded["mason-core.package"]
local tools = { "fixture-tool", "fixture-tool" }
local servers = { "fixture_lsp" }
local notices = {}
local installed, installing, receipt, registered
local calls, setup_options, fail_install, waits = {}, nil, false, 0
local tool_package = {
	is_installed = function()
		return installed
	end,
	is_installing = function()
		return installing
	end,
	get_receipt = function()
		return {
			is_present = function()
				return receipt
			end,
		}
	end,
}
local registry = {
	get_package = function(name)
		assert(name == "fixture-tool" or name == "fixture-lsp")
		assert(registered, "unknown package")
		return tool_package
	end,
	get_installed_package_names = function()
		return { "fixture-tool", "fixture-lsp", "manual-java" }
	end,
}
local modules = package.loaded
modules["mason-lspconfig.settings"] = { current = { ensure_installed = servers } }
modules["mason-lspconfig.mappings"] = {
	get_mason_map = function()
		return { lspconfig_to_package = { fixture_lsp = "fixture-lsp" } }
	end,
}
modules["mason-core.package"] = {
	Parse = function(value)
		local name, version = value:match("^(.-)@(.+)$")
		return name or value, version
	end,
}
modules["mason-registry"] = registry
modules["mason-tool-installer"] = {
	setup = function(opts)
		setup_options = opts
	end,
	check_install = function(force, sync)
		assert(not installing, "Competing installation was not awaited")
		calls[#calls + 1] = { force, sync }
		registered = true -- Simulate the installer's registry refresh.
		installed, receipt = not fail_install, not fail_install
	end,
}
_G.LazyVim = {
	opts = function()
		return { ensure_installed = tools }
	end,
}

local ok, err = xpcall(function()
	for _, spec in ipairs(dofile("home/dot_config/nvim/lua/plugins/toolchain.lua")) do
		if spec[1] == "WhoIsSethDaniel/mason-tool-installer.nvim" then
			spec.config(nil, vim.deepcopy(spec.opts))
		end
	end
	assert(setup_options and vim.deep_equal(setup_options.ensure_installed, { "fixture-tool", "fixture-lsp" }))
	assert(not setup_options.run_on_start and not setup_options.auto_update)
	vim.notify = function(message)
		notices[#notices + 1] = message
	end
	vim.cmd("MasonToolsClean")
	assert(#notices == 1 and notices[1]:find("manual-java", 1, true))
	assert(not notices[1]:find("fixture-lsp", 1, true), "Cleanup offered an active LSP for removal")
	assert(notices[1]:find("not removed", 1, true), "Cleanup must preview instead of uninstalling")

	-- Accelerate waits while enforcing the real predicate and bounded timeout.
	vim.wait = function(timeout, predicate)
		waits = waits + 1
		assert(timeout == 900000)
		return predicate()
	end
	for _, command in ipairs({
		"MasonToolsInstall",
		"MasonToolsInstallSync",
		"MasonToolsUpdate",
		"MasonToolsUpdateSync",
	}) do
		installed, installing, receipt, registered = false, false, false, true
		local before = #calls
		vim.cmd(command)
		assert(#calls == before + 1, command .. " never attempted missing-tool repair")
		assert(calls[#calls][1] == (command:find("Update", 1, true) ~= nil))
		assert(calls[#calls][2] == (command:find("Sync", 1, true) ~= nil))
		assert(installed and receipt)
	end

	registered, installed, receipt = false, false, false
	vim.cmd("MasonToolsInstallSync")
	assert(registered and installed and receipt, "Unknown package blocked registry refresh")

	-- Active startup installs finish (or fail) before explicit repair begins.
	installing, installed, receipt = true, false, false
	vim.wait = function(_, predicate)
		assert(not predicate(), "Active install was ignored")
		installing = false -- Startup install failed; this command must repair it.
		return predicate()
	end
	vim.cmd("MasonToolsInstallSync")
	assert(installed and receipt)

	-- Timeout and failed repair cannot look successful or start competing work.
	installing = true
	vim.wait = function(_, predicate)
		return predicate()
	end
	local before = #calls
	local success, failure = pcall(vim.cmd, "MasonToolsInstallSync")
	assert(not success and tostring(failure):find("Timed out waiting for active Mason installs", 1, true))
	assert(#calls == before)
	installing, fail_install = false, true
	success, failure = pcall(vim.cmd, "MasonToolsInstallSync")
	assert(not success and tostring(failure):find("Mason tools unavailable after install", 1, true))
	assert(not installed and not receipt and waits >= 5)
	assert(#policy.pending({ "fixture-tool" }) == 1)

	-- Keep explicit version constraints/options and never mutate input lists.
	tools = { "fixture-tool", { "fixture-lsp", version = "1.2.3", auto_update = false } }
	servers[1] = "fixture_lsp@1.2.3"
	local snapshot = vim.deepcopy(tools)
	assert(vim.deep_equal(policy.required_tools(), tools))
	assert(vim.deep_equal(tools, snapshot))
	tools = { "fixture-tool", "fixture-lsp" }
	local pinned = policy.required_tools()
	assert(pinned[2].version == "1.2.3" and tools[2] == "fixture-lsp")
	tools = { "fixture-tool" }
	pinned = policy.required_tools()
	assert(pinned[2][1] == "fixture-lsp" and pinned[2].version == "1.2.3")
	tools[2] = { "fixture-lsp", version = "9.9.9" }
	success, failure = pcall(policy.required_tools)
	assert(not success and tostring(failure):find("Conflicting Mason versions", 1, true))
	servers[1] = "unknown_server"
	success, failure = pcall(policy.required_tools)
	assert(not success and tostring(failure):find("Unmapped Mason LSP server", 1, true))
end, debug.traceback)

vim.wait, _G.LazyVim = original_wait, original_lazyvim
vim.notify = original_notify
modules["mason-registry"], modules["mason-tool-installer"] = original_registry, original_installer
modules["mason-lspconfig.settings"] = original_settings
modules["mason-lspconfig.mappings"] = original_mappings
modules["mason-core.package"] = original_package
if not ok then
	error(err)
end
print("Mason recovery contract passed: tool/LSP union, safe cleanup preview, pins, missing tools and failed repair")
