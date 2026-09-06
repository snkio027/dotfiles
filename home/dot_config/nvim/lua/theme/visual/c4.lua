--- DX Semantic Color System (DX-COLOR-003)
--- DX-COLOR-004 M1 Storm-derived semantic projection prototype.
--- The module name remains stable until promotion/cleanup.

local M = {}

---@param p table Unified palette returned by palette.resolve()
---@return table<string, vim.api.keyset.highlight>
function M.roles(p)
  local code = assert(p.code, "Storm semantic palette is unavailable")

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
