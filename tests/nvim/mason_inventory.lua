-- Use the resolved LazyVim extras and real plugin setup, without installs.
require("lazy").load({ plugins = { "nvim-lspconfig" } })
local plugin = require("lazy.core.config").plugins["mason-tool-installer.nvim"]
local configure, captured = plugin.config, nil
plugin.config = function(p, opts)
	configure(p, opts)
	captured = opts.ensure_installed
end
require("lazy").load({ plugins = { "mason-tool-installer.nvim" } })
plugin.config = configure
assert(captured, "Mason tool installer setup failed")
local names = {}
for _, tool in ipairs(captured) do
	local name = require("config.mason").tool_name(tool)
	assert(not names[name], "Duplicate Mason package: " .. name)
	names[name] = true
end
for _, tool in ipairs(LazyVim.opts("mason.nvim").ensure_installed) do
	assert(names[require("config.mason").tool_name(tool)], "Tool omitted from installer")
end
local map = require("mason-lspconfig.mappings").get_mason_map().lspconfig_to_package
local servers = require("mason-lspconfig.settings").current.ensure_installed
assert(#servers > 0, "LSP install list was read before setup")
for _, server in ipairs(servers) do
	local name = require("mason-core.package").Parse(server)
	assert(names[map[name]], "Enabled LSP omitted from installer: " .. name)
end
assert(not names.clangd and not names["rust-analyzer"], "External server ownership was changed")
print(("Mason inventory contract passed: %d tools/servers, external owners preserved"):format(vim.tbl_count(names)))
