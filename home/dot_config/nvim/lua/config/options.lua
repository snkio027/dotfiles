-- LazyVim loads this file before lazy.nvim starts.
vim.g.autoformat = true
vim.g.lazyvim_cmp = "blink.cmp"
vim.g.lazyvim_picker = "snacks"
vim.g.lazyvim_python_lsp = "ty"
vim.g.lazyvim_python_ruff = "ruff"

require("config.clipboard").setup()

-- Register before the first BufRead/FileType event so Compose's dedicated
-- language server starts on both command-line and picker opens.
vim.filetype.add({
  filename = {
    ["compose.yaml"] = "yaml.docker-compose",
    ["compose.yml"] = "yaml.docker-compose",
    ["docker-compose.yaml"] = "yaml.docker-compose",
    ["docker-compose.yml"] = "yaml.docker-compose",
  },
  pattern = {
    ["compose%.[%w_-]+%.ya?ml"] = "yaml.docker-compose",
    ["docker%-compose%.[%w_-]+%.ya?ml"] = "yaml.docker-compose",
  },
})

vim.opt.confirm = true
vim.opt.cursorline = true
vim.opt.cursorlineopt = "number"
vim.opt.scrolloff = 6
vim.opt.sidescrolloff = 8
vim.opt.smoothscroll = true
vim.opt.wrap = false
