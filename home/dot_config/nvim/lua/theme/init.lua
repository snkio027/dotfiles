--- DX Semantic Color System (DX-COLOR-002)
--- Theme Assembly Entry Point: combines palette, semantic roles, and external
--- mappings into a unified highlight specification for Catppuccin custom_highlights.

local palette_mod = require("theme.palette")
local semantic = require("theme.semantic")
local mappings = require("theme.mappings")

local M = {}

---@param colors table Catppuccin Mocha named palette table
---@return table<string, vim.api.keyset.highlight>
function M.highlights(colors)
  local p = palette_mod.resolve(colors)
  local roles = semantic.roles(p)
  local groups = mappings.groups(p)

  return vim.tbl_extend("force", roles, groups)
end

return M
