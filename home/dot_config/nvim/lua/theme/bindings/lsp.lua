--- DX Semantic Color System (DX-COLOR-003)
--- Generic semantic-token vocabulary translated into provider-independent DX roles.

local M = {}

---@return table<string, vim.api.keyset.highlight>
function M.groups()
  local hl = {
    ["@lsp.type.keyword"] = { link = "DxKeyword" },
    ["@lsp.type.modifier"] = { link = "DxKeyword" },
    ["@lsp.type.function"] = { link = "DxCallable" },
    ["@lsp.type.method"] = { link = "DxCallable" },
    ["@lsp.type.class"] = { link = "DxType" },
    ["@lsp.type.struct"] = { link = "DxType" },
    ["@lsp.type.enum"] = { link = "DxType" },
    ["@lsp.type.interface"] = { link = "DxType" },
    ["@lsp.type.type"] = { link = "DxType" },
    ["@lsp.type.typeParameter"] = { link = "DxType" },
    ["@lsp.type.property"] = { link = "DxMember" },
    ["@lsp.type.parameter"] = { link = "DxParameter" },
    ["@lsp.type.variable"] = { link = "DxVariable" },
    ["@lsp.type.namespace"] = { link = "DxNamespace" },
    ["@lsp.type.macro"] = { link = "DxMeta" },
    ["@lsp.type.decorator"] = { link = "DxMeta" },
    ["@lsp.type.enumMember"] = { link = "DxConstant" },
    ["@lsp.type.string"] = { link = "DxString" },
    ["@lsp.type.regexp"] = { link = "DxString" },
    ["@lsp.type.number"] = { link = "DxNumber" },
    ["@lsp.type.operator"] = { link = "DxOperator" },
    ["@lsp.type.comment"] = { link = "DxComment" },
    ["@lsp.type.event"] = { link = "DxMember" },

    -- Safe semantic extensions observed across the current provider set.
    ["@lsp.type.label"] = { link = "DxLabel" },
    ["@lsp.type.lifetime"] = { link = "DxLifetime" },
    ["@lsp.type.builtinType"] = { link = "DxBuiltin" },

    -- Modifier foreground normalization preserves the base semantic identity.
    ["@lsp.typemod.variable.readonly"] = { link = "DxVariable" },
    ["@lsp.typemod.variable.defaultLibrary"] = { link = "DxVariable" },
    ["@lsp.typemod.variable.static"] = { link = "DxVariable" },
    ["@lsp.typemod.property.readonly"] = { link = "DxMember" },
    ["@lsp.typemod.function.defaultLibrary"] = { link = "DxCallable" },
    ["@lsp.typemod.function.async"] = { link = "DxCallable" },
    ["@lsp.typemod.method.defaultLibrary"] = { link = "DxCallable" },
    ["@lsp.typemod.method.async"] = { link = "DxCallable" },

    -- Style authority composes without replacing semantic foreground authority.
    ["@lsp.mod.deprecated"] = { strikethrough = true },
  }

  local governed_lsp_types = {
    "function",
    "method",
    "class",
    "struct",
    "enum",
    "interface",
    "type",
    "typeParameter",
    "property",
    "parameter",
    "variable",
    "namespace",
    "macro",
    "decorator",
    "enumMember",
    "string",
    "number",
  }
  for _, token_type in ipairs(governed_lsp_types) do
    hl["@lsp.typemod." .. token_type .. ".deprecated"] = { strikethrough = true }
  end

  return hl
end

return M
