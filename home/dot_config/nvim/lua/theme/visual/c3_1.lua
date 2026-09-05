--- DX Semantic Color System (DX-COLOR-003)
--- C3.1 visual projection. This profile preserves the DX-COLOR-002 baseline.

local M = {}

---@param p table Unified palette returned by palette.resolve()
---@return table<string, vim.api.keyset.highlight>
function M.roles(p)
  return {
    DxKeyword = { fg = p.code.keyword, bold = false, italic = false },
    DxFunctionKeyword = { fg = p.code.keyword_function, bold = false, italic = false },
    DxCallable = { fg = p.code.callable, bold = false, italic = false },
    DxType = { fg = p.code.type, bold = false, italic = false },
    DxBuiltin = { fg = p.code.builtin, bold = false, italic = false },
    DxLifetime = { fg = p.code.lifetime, bold = false, italic = false },
    DxMember = { fg = p.code.member, bold = false, italic = false },
    DxParameter = { fg = p.code.parameter, bold = false, italic = false },
    DxVariable = { fg = p.code.variable, bold = false, italic = false },
    DxMeta = { fg = p.code.meta, bold = false, italic = false },
    DxNamespace = { fg = p.code.namespace, bold = false, italic = false },
    DxString = { fg = p.code.string, bold = false, italic = false },
    DxNumber = { fg = p.code.number, bold = false, italic = false },
    DxConstant = { fg = p.code.constant, bold = false, italic = false },
    DxLabel = { fg = p.code.label, bold = false, italic = false },
    DxOperator = { fg = p.code.operator, bold = false, italic = false },
    DxPunctuation = { fg = p.code.punctuation, bold = false, italic = false },
    DxComment = { fg = p.code.comment, italic = true },
    DxDocComment = { fg = p.code.doc, italic = true },
    DxError = { fg = p.state.error, bold = false, italic = false },
    DxWarn = { fg = p.state.warn, bold = false, italic = false },
    DxInfo = { fg = p.state.info, bold = false, italic = false },
    DxHint = { fg = p.state.hint, bold = false, italic = false },
  }
end

return M
