--- DX Semantic Color System (DX-COLOR-001)
--- Theme Assembly Entry Point: combines semantic role definitions and external
--- mappings into a unified highlight specification for Catppuccin custom_highlights.

local M = {}

local semantic = require("theme.semantic")
local mappings = require("theme.mappings")

---@param colors table Catppuccin Mocha named palette table
---@return table<string, vim.api.keyset.highlight>
function M.highlights(colors)
  local result = {}

  -- 1. Apply Dx* semantic role definitions
  for group, spec in pairs(semantic.roles(colors)) do
    result[group] = spec
  end

  -- 2. Apply external namespace mappings (Tree-sitter, LSP, Editor, Plugins)
  for group, spec in pairs(mappings.mappings(colors)) do
    result[group] = spec
  end

  return result
end

return M
