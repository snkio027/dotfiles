--- DX Semantic Color System (DX-COLOR-003)
--- Rust grammar and rust-analyzer extensions backed by current fixture evidence.

local M = {}

---@return table<string, vim.api.keyset.highlight>
function M.groups()
  return {
    ["@type.lifetime.rust"] = { link = "DxLifetime" },
    ["@lsp.type.lifetime"] = { link = "DxLifetime" },
    ["@lsp.type.builtinType"] = { link = "DxBuiltin" },
    ["@lsp.type.typeAlias"] = { link = "DxType" },
    ["@lsp.type.union"] = { link = "DxType" },
    ["@lsp.type.selfTypeKeyword"] = { link = "DxType" },

    -- rust-analyzer represents attribute identifiers as attribute namespaces.
    ["@lsp.typemod.namespace.attribute.rust"] = { link = "DxMeta" },
  }
end

return M
