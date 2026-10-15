-- Exercise the real command registration and policy without installing tools.
local policy = require("config.mason")
local original_registry = package.loaded["mason-registry"]
local original_installer = package.loaded["mason-tool-installer"]
local original_lazyvim = _G.LazyVim
local original_wait = vim.wait
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
		assert(name == "fixture-tool")
		assert(registered, "unknown package")
		return tool_package
	end,
}
local modules = package.loaded
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
		return { ensure_installed = { "fixture-tool", "fixture-tool" } }
	end,
}

local ok, err = xpcall(function()
	for _, spec in ipairs(dofile("home/dot_config/nvim/lua/plugins/toolchain.lua")) do
		if spec[1] == "WhoIsSethDaniel/mason-tool-installer.nvim" then
			spec.config(nil, vim.deepcopy(spec.opts))
		end
	end
	assert(setup_options and #setup_options.ensure_installed == 1)
	assert(not setup_options.run_on_start and not setup_options.auto_update)

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
end, debug.traceback)

vim.wait, _G.LazyVim = original_wait, original_lazyvim
modules["mason-registry"], modules["mason-tool-installer"] = original_registry, original_installer
if not ok then
	error(err)
end
print("Mason recovery contract passed: missing tools, active installs, registry refresh, failure propagation")
