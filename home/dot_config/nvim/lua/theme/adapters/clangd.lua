--- DX Semantic Color System (DX-COLOR-003)
--- clangd extensions and C/C++ taxonomy-loss handling.

local authority = require("theme.authority")

local M = {}

---@return table<string, vim.api.keyset.highlight>
function M.groups()
  return {
    ["@lsp.type.concept"] = { link = "DxType" },

    -- clangd's generic type token loses the builtin/user-defined distinction.
    ["@lsp.type.type.c"] = authority.suppress_foreground(),
    ["@lsp.type.type.cpp"] = authority.suppress_foreground(),
  }
end

return M
