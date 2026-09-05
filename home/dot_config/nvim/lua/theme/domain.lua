--- DX Semantic Color System (DX-COLOR-003)
--- Provider-independent registry of the semantic roles owned by the DX domain.

local M = {}

M.roles = {
  DxKeyword = {
    family = "grammar",
    description = "General grammar or control keyword",
  },
  DxFunctionKeyword = {
    family = "grammar",
    description = "Keyword that introduces a function declaration",
  },
  DxCallable = {
    family = "execution",
    description = "Callable function, method, or constructor",
  },
  DxType = {
    family = "type-system",
    description = "User-defined data type or type parameter",
  },
  DxBuiltin = {
    family = "type-system",
    description = "Primitive or built-in type",
  },
  DxLifetime = {
    family = "type-system",
    description = "Type-level lifetime binding",
  },
  DxMember = {
    family = "binding",
    description = "Object field, property, or member",
  },
  DxParameter = {
    family = "binding",
    description = "Function or callable parameter",
  },
  DxVariable = {
    family = "binding",
    description = "Ordinary value binding",
  },
  DxMeta = {
    family = "meta",
    description = "Metaprogramming construct such as an attribute, decorator, or macro",
  },
  DxNamespace = {
    family = "organization",
    description = "Module, namespace, or package",
  },
  DxString = {
    family = "data",
    description = "String or character data",
  },
  DxNumber = {
    family = "data",
    description = "Numeric literal",
  },
  DxConstant = {
    family = "data",
    description = "Constant value or constant-like literal",
  },
  DxLabel = {
    family = "control",
    description = "Named control-flow target",
  },
  DxOperator = {
    family = "syntax",
    description = "Operation symbol or operator",
  },
  DxPunctuation = {
    family = "syntax",
    description = "Structural delimiter or punctuation",
  },
  DxComment = {
    family = "prose",
    description = "Ordinary source comment",
  },
  DxDocComment = {
    family = "prose",
    description = "Documentation prose embedded in source",
  },
  DxError = {
    family = "state",
    description = "Error or destructive state",
  },
  DxWarn = {
    family = "state",
    description = "Warning or attention state",
  },
  DxInfo = {
    family = "state",
    description = "Informational state",
  },
  DxHint = {
    family = "state",
    description = "Hint or suggestion state",
  },
}

return M
