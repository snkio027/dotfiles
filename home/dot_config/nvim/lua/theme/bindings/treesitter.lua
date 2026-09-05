--- DX Semantic Color System (DX-COLOR-003)
--- Generic Tree-sitter vocabulary translated into provider-independent DX roles.

local M = {}

---@return table<string, vim.api.keyset.highlight>
function M.groups()
  return {
    ["@keyword"] = { link = "DxKeyword" },
    ["@keyword.function"] = { link = "DxFunctionKeyword" },
    ["@keyword.return"] = { link = "DxKeyword" },
    ["@keyword.type"] = { link = "DxKeyword" },
    ["@keyword.import"] = { link = "DxKeyword" },
    ["@keyword.conditional"] = { link = "DxKeyword" },
    ["@keyword.repeat"] = { link = "DxKeyword" },
    ["@keyword.coroutine"] = { link = "DxKeyword" },
    ["@keyword.operator"] = { link = "DxKeyword" },
    ["@keyword.modifier"] = { link = "DxKeyword" },
    ["@keyword.exception"] = { link = "DxKeyword" },
    ["@keyword.directive"] = { link = "DxKeyword" },
    ["@keyword.directive.define"] = { link = "DxKeyword" },
    ["@keyword.storage"] = { link = "DxKeyword" },

    ["@function"] = { link = "DxCallable" },
    ["@function.call"] = { link = "DxCallable" },
    ["@function.method"] = { link = "DxCallable" },
    ["@function.method.call"] = { link = "DxCallable" },
    ["@function.builtin"] = { link = "DxCallable" },
    ["@constructor"] = { link = "DxCallable" },

    ["@type"] = { link = "DxType" },
    ["@type.definition"] = { link = "DxType" },
    ["@type.builtin"] = { link = "DxBuiltin" },
    ["@type.lifetime"] = { link = "DxLifetime" },

    ["@variable"] = { link = "DxVariable" },
    ["@variable.builtin"] = { link = "DxVariable" },
    ["@variable.parameter"] = { link = "DxParameter" },
    ["@variable.member"] = { link = "DxMember" },
    ["@property"] = { link = "DxMember" },

    ["@module"] = { link = "DxNamespace" },
    ["@module.builtin"] = { link = "DxNamespace" },

    ["@attribute"] = { link = "DxMeta" },
    ["@attribute.builtin"] = { link = "DxMeta" },
    ["@function.macro"] = { link = "DxMeta" },
    ["@constant.macro"] = { link = "DxMeta" },

    ["@label"] = { link = "DxLabel" },

    ["@string"] = { link = "DxString" },
    ["@string.documentation"] = { link = "DxDocComment" },
    ["@string.regexp"] = { link = "DxString" },
    ["@string.escape"] = { link = "DxString" },
    ["@character"] = { link = "DxString" },
    ["@character.special"] = { link = "DxPunctuation" },
    ["@number"] = { link = "DxNumber" },
    ["@number.float"] = { link = "DxNumber" },
    ["@boolean"] = { link = "DxConstant" },
    ["@constant"] = { link = "DxConstant" },
    ["@constant.builtin"] = { link = "DxConstant" },

    ["@operator"] = { link = "DxOperator" },
    ["@punctuation.delimiter"] = { link = "DxPunctuation" },
    ["@punctuation.bracket"] = { link = "DxPunctuation" },
    ["@punctuation.special"] = { link = "DxPunctuation" },

    ["@comment"] = { link = "DxComment" },
    ["@comment.documentation"] = { link = "DxDocComment" },
    ["@comment.error"] = { link = "DxError" },
    ["@comment.warning"] = { link = "DxWarn" },
    ["@comment.todo"] = { link = "DxWarn" },
    ["@comment.note"] = { link = "DxInfo" },
  }
end

return M
