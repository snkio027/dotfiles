local installer_opts = LazyVim.opts("mason-tool-installer.nvim")
assert(installer_opts.auto_update == false, "Mason tools must not update automatically")
assert(installer_opts.run_on_start == false, "mason-tool-installer must not run on startup")

local lazy_config = require("lazy.core.config")
assert(lazy_config.options.checker.enabled == false, "Lazy plugin checker must not run automatically")
assert(not package.loaded["lazy.manage.checker"], "Lazy plugin checker loaded during startup")

local installer_plugin = lazy_config.plugins["mason-tool-installer.nvim"]
assert(installer_plugin, "mason-tool-installer plugin spec is unavailable")
assert(not installer_plugin._.loaded, "mason-tool-installer loaded during startup")
assert(not package.loaded["mason-tool-installer"], "mason-tool-installer module loaded during startup")

local debounce_file = vim.fn.stdpath("data") .. "/mason-tool-installer-debounce"
assert(vim.fn.filereadable(debounce_file) == 0, "Mason startup debounce file should not be created")

vim.wait(1000)
assert(not installer_plugin._.loaded, "mason-tool-installer loaded in the background")
assert(not package.loaded["mason-tool-installer"], "Mason background installer started")
assert(not package.loaded["lazy.manage.checker"], "Lazy plugin checker started in the background")

print("Neovim background update policy tests passed")
