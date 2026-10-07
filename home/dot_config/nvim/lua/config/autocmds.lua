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

vim.api.nvim_create_autocmd("FileType", {
  group = group,
  pattern = { "c", "cpp", "objc", "objcpp", "cuda" },
  callback = function(event)
    require("config.cpp").setup_buffer(event.buf)
  end,
})

vim.api.nvim_create_user_command("CppDependencyEdit", function()
  require("config.cpp_dependency").edit(vim.api.nvim_get_current_buf())
end, { desc = "Allow editing this dependency buffer (autoformat stays off)" })

-- LazyVim can load these autocmds after the initial buffer's FileType event.
for _, buf in ipairs(vim.api.nvim_list_bufs()) do
  if
    vim.api.nvim_buf_is_loaded(buf) and vim.tbl_contains({ "c", "cpp", "objc", "objcpp", "cuda" }, vim.bo[buf].filetype)
  then
    require("config.cpp_dependency").protect(buf)
  end
end
