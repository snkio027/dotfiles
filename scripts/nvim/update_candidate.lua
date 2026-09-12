-- Invoked through run_contract.lua, inside devup's disposable XDG environment.
assert(vim.v.errmsg == "", "candidate startup error: " .. vim.v.errmsg)
print("Candidate Neovim: " .. tostring(vim.version()))
require("lazy").sync({ wait = true, show = false })

-- Lazy task failures do not necessarily throw; inspect every completed task.
local config = require("lazy.core.config")
local plugins = vim.tbl_values(config.plugins)
vim.list_extend(plugins, vim.tbl_values(config.to_clean))
for _, plugin in ipairs(plugins) do
	for _, task in ipairs(plugin._.tasks or {}) do
		assert(not task:running(), "unfinished plugin task: " .. plugin.name)
		assert(not task:has_errors(), "failed plugin task: " .. plugin.name .. "\n" .. task:output())
	end
end
assert(vim.v.errmsg == "", "candidate update error: " .. vim.v.errmsg)
print("Neovim plugin candidate downloaded.")
