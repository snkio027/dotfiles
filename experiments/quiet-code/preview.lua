-- Loaded only by the isolated launcher, before the ordinary Neovim init.
local directory = assert(vim.env.DOTFILES_QUIET_PREVIEW_DIR)
local candidate = dofile(directory .. "/palette.lua")
local palette = require("theme.palette")
local ui = require("theme.bindings.ui")
local plugins = require("theme.bindings.plugins")
local original_palette, original_ui, original_plugins = palette.resolve, ui.groups, plugins.groups

palette.resolve = function(colors)
	return candidate.apply(original_palette(colors))
end
ui.groups = function(p)
	local groups = original_ui(p)
	groups.Normal = { fg = p.ui.normal_fg, bg = p.ui.normal_bg }
	groups.CursorLineNr.fg = p.ui.focus
	groups.Visual = { fg = p.ui.selection_fg, bg = p.ui.selection_bg }
	return groups
end
plugins.groups = function(p)
	local groups = original_plugins(p)
	groups.SnacksIndentScope.fg = p.ui.focus
	groups.NeotestFocused.fg = p.ui.focus
	groups.DapStoppedLine = { bg = p.ui.stopped_bg }
	return groups
end

vim.g.dotfiles_quiet_code_preview = true
vim.opt.title = true
vim.opt.titlestring = "Quiet Code preview · %t"
