--- DX Semantic Color System (DX-COLOR-003)
--- C4.0 candidate visual projection. This profile is not selected at runtime.

local M = {}

---@param p table Unified palette returned by palette.resolve()
---@return table<string, vim.api.keyset.highlight>
function M.roles(p)
  local code = assert(p.code_profiles and p.code_profiles.c4, "C4 code palette is unavailable")

  return {
    DxKeyword = { fg = code.keyword, bold = false, italic = false },
    DxFunctionKeyword = { fg = code.keyword_function, bold = false, italic = false },
    DxCallable = { fg = code.callable, bold = false, italic = false },
    DxType = { fg = code.type, bold = false, italic = false },
    DxBuiltin = { fg = code.builtin, bold = false, italic = false },
    DxLifetime = { fg = code.lifetime, bold = false, italic = false },
    DxMember = { fg = code.member, bold = false, italic = false },
    DxParameter = { fg = code.parameter, bold = false, italic = false },
    DxVariable = { fg = code.variable, bold = false, italic = false },
    DxMeta = { fg = code.meta, bold = false, italic = false },
    DxNamespace = { fg = code.namespace, bold = false, italic = false },
    DxString = { fg = code.string, bold = false, italic = false },
    DxNumber = { fg = code.number, bold = false, italic = false },
    DxConstant = { fg = code.constant, bold = false, italic = false },
    DxLabel = { fg = code.label, bold = false, italic = false },
    DxOperator = { fg = code.operator, bold = false, italic = false },
    DxPunctuation = { fg = code.punctuation, bold = false, italic = false },
    DxComment = { fg = code.comment, italic = true },
    DxDocComment = { fg = code.doc, italic = true },
    DxError = { fg = p.state.error, bold = false, italic = false },
    DxWarn = { fg = p.state.warn, bold = false, italic = false },
    DxInfo = { fg = p.state.info, bold = false, italic = false },
    DxHint = { fg = p.state.hint, bold = false, italic = false },
  }
end

return M
