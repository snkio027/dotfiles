--- DX Semantic Color System (DX-COLOR-003)
--- Assembly entry point for Catppuccin custom_highlights.

local palette_mod = require("theme.palette")
local compose = require("theme.compose")
local c3_1 = require("theme.visual.c3_1")

local M = {}

---@param colors table Catppuccin Mocha named palette table
---@return table<string, vim.api.keyset.highlight>
function M.highlights(colors)
  local p = palette_mod.resolve(colors)
  return compose.highlights(p, c3_1)
end

return M
