local group = vim.api.nvim_create_augroup("dotfiles_dx", { clear = true })

vim.api.nvim_create_autocmd("TextYankPost", {
  group = group,
  callback = function()
    vim.highlight.on_yank({ higroup = "IncSearch", timeout = 150 })
  end,
})

vim.api.nvim_create_autocmd("FileType", {
  group = group,
  pattern = { "markdown", "markdown.mdx" },
  callback = function()
    vim.opt_local.wrap = true
    vim.opt_local.linebreak = true
    vim.opt_local.breakindent = true
    vim.opt_local.breakindentopt = "shift:2,min:20"
    vim.opt_local.spell = true
    vim.opt_local.spelllang = { "en_us", "cjk" }
  end,
})
