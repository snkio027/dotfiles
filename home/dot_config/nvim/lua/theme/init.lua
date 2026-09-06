--- DX Semantic Color System (DX-COLOR-003)
--- Assembly entry point for the TokyoNight Storm semantic overlay.

local palette_mod = require("theme.palette")
local compose = require("theme.compose")
local visual = require("theme.visual.c4")

local M = {}

local preserved_host_lsp_groups = {
  -- TokyoNight supplies a non-color error cue for unresolved references. It is
  -- presentation state rather than source-semantic foreground authority.
  ["@lsp.type.unresolvedReference"] = true,
}

---@param colors table TokyoNight Storm named palette table
---@return table<string, vim.api.keyset.highlight>
function M.highlights(colors)
  local p = palette_mod.resolve(colors)
  return compose.highlights(p, visual)
end

--- Removes TokyoNight semantic-token foregrounds outside the governed DX graph,
--- then installs the DX overlay into the host highlight table. This keeps
--- provider evidence and foreground authority inside DX without copying the
--- host's Tree-sitter/LSP taxonomy.
---@param host_highlights table<string, vim.api.keyset.highlight|string>
---@param colors table TokyoNight Storm named palette table
function M.apply_host_overlay(host_highlights, colors)
  local overlay = M.highlights(colors)
  local unowned_lsp_groups = {}

  for group in pairs(host_highlights) do
    if group:match("^@lsp%.") and overlay[group] == nil and not preserved_host_lsp_groups[group] then
      table.insert(unowned_lsp_groups, group)
    end
  end

  for _, group in ipairs(unowned_lsp_groups) do
    host_highlights[group] = nil
  end
  for group, spec in pairs(overlay) do
    host_highlights[group] = spec
  end
end

return M
