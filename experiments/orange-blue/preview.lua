-- Pre-init overlay used only by this directory's isolated launcher.
local candidate = dofile(assert(vim.env.DOTFILES_COLOR_PREVIEW_DIR) .. "/palette.lua")
local palette = require("theme.palette")
local original = palette.resolve
palette.resolve = function(colors)
  return candidate.apply(original(colors))
end

vim.g.dotfiles_orange_blue_preview = true
vim.opt.title = true
vim.opt.titlestring = "Orange / Violet / Blue preview · %t"
