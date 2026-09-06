--- DX Semantic Color System (DX-COLOR-003)
--- Assembly entry point for Catppuccin custom_highlights.

local palette_mod = require("theme.palette")
local compose = require("theme.compose")
local visual = require("theme.visual.c4")

local M = {}

---@param colors table Catppuccin Mocha named palette table
---@return table<string, vim.api.keyset.highlight>
function M.highlights(colors)
  local p = palette_mod.resolve(colors)
  return compose.highlights(p, visual)
end

return M
