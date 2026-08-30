local installer_opts = LazyVim.opts("mason-tool-installer.nvim")
assert(installer_opts.auto_update == false, "Mason tools must not update automatically")
assert(installer_opts.run_on_start == false, "mason-tool-installer must not run on startup")

local installer_plugin = require("lazy.core.config").plugins["mason-tool-installer.nvim"]
assert(installer_plugin, "mason-tool-installer plugin spec is unavailable")
assert(not installer_plugin._.loaded, "mason-tool-installer loaded during startup")
assert(not package.loaded["mason-tool-installer"], "mason-tool-installer module loaded during startup")

local debounce_file = vim.fn.stdpath("data") .. "/mason-tool-installer-debounce"
assert(vim.fn.filereadable(debounce_file) == 0, "Mason startup debounce file should not be created")

vim.wait(1000)
assert(not installer_plugin._.loaded, "mason-tool-installer loaded in the background")
assert(not package.loaded["mason-tool-installer"], "Mason background installer started")

print("Neovim Mason startup policy tests passed")
