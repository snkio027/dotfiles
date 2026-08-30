require("lazy").load({ plugins = { "mason.nvim" } })

local policy = require("config.mason")
local tools = LazyVim.opts("mason.nvim").ensure_installed or {}
local unique = policy.unique(tools)
assert(#unique == #tools, "Final Mason ensure_installed list contains duplicates")

local installed = policy.wait_for_installed(unique, vim.env.DOTFILES_MASON_TIMEOUT_MS)
print(("Mason missing-tool provisioning %d/%d"):format(installed, #unique))
