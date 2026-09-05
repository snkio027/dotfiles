--- DX Semantic Color System (DX-COLOR-003)
--- Reusable primitives for highlight-attribute authority decisions.

local M = {}

M.foreground_passthrough = "LspForegroundPassthrough"

---@return table<string, vim.api.keyset.highlight>
function M.base_groups()
  return {
    [M.foreground_passthrough] = {},
  }
end

---@return vim.api.keyset.highlight
function M.suppress_foreground()
  return { link = M.foreground_passthrough }
end

return M
