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

    -- clangd projects its StaticField taxonomy as variable + classScope plus
    -- orthogonal storage, mutability, and provenance modifiers. For C++, type
    -- ownership defines the foreground identity; the other modifiers must not
    -- compete with classScope at semantic-token modifier priority.
    ["@lsp.typemod.variable.classScope.cpp"] = { link = "DxMember" },
    ["@lsp.typemod.variable.static.cpp"] = authority.suppress_foreground(),
    ["@lsp.typemod.variable.readonly.cpp"] = authority.suppress_foreground(),
    ["@lsp.typemod.variable.defaultLibrary.cpp"] = authority.suppress_foreground(),
  }
end

return M
