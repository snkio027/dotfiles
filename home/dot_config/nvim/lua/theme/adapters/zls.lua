--- DX Semantic Color System (DX-COLOR-003)
--- Zig/ZLS taxonomy translation and proven foreground-authority decisions.

local authority = require("theme.authority")

local M = {}

---@return table<string, vim.api.keyset.highlight>
function M.groups()
  return {
    -- Tree-sitter preserves the distinction between builtins and callables.
    ["@function.builtin.zig"] = { link = "DxMeta" },

    -- ZLS extensions with evidence in the current fixture contract.
    ["@lsp.type.builtin"] = { link = "DxMeta" },
    ["@lsp.type.keywordLiteral"] = { link = "DxConstant" },
    ["@lsp.type.errorTag"] = { link = "DxConstant" },
    ["@lsp.type.escapeSequence"] = { link = "DxString" },

    -- ZLS uses `type` for unions as well as primitives. Keep semantic type
    -- authority on qualified names; the Zig query protects builtin_type nodes.
    ["@lsp.type.type.zig"] = { link = "DxType" },
    -- Preserve Tree-sitter's distinction between fn and ordinary keywords.
    ["@lsp.type.keyword.zig"] = authority.suppress_foreground(),
  }
end

return M
