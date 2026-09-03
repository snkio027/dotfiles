--- DX Semantic Color System (DX-COLOR-002)
--- Semantic Role Definitions: maps abstract program semantics to palette roles.
--- Zero external plugin knowledge; pure semantic role contract.

local M = {}

---@param p table Unified palette returned by palette.resolve()
---@return table<string, vim.api.keyset.highlight>
function M.roles(p)
  return {
    -- Language Grammar & Core Constructs
    DxKeyword = { fg = p.code.keyword, bold = false, italic = false },

    -- Execution Landmarks: Functions & Methods
    DxCallable = { fg = p.code.callable, bold = false, italic = false },

    -- Data Models: User-defined Structs, Classes, Enums, Interfaces, Type Parameters
    DxType = { fg = p.code.type, bold = false, italic = false },

    -- Primitives & Builtin Types: u64, int, bool, str, float
    DxBuiltin = { fg = p.code.builtin, bold = false, italic = false },

    -- Type-level Lifetime Bindings: Rust 'a / 'static
    DxLifetime = { fg = p.code.lifetime, bold = false, italic = false },

    -- Object Structure: Fields, Properties, Members
    DxMember = { fg = p.code.member, bold = false, italic = false },

    -- Signature Boundary: Function Parameters
    DxParameter = { fg = p.code.parameter, bold = false, italic = false },

    -- Neutral Foreground: Local Variables (preserves low visual noise)
    DxVariable = { fg = p.code.variable, bold = false, italic = false },

    -- Meta-programming: Attributes, Derive Macros, Decorators, Builtin Macros
    DxMeta = { fg = p.code.meta, bold = false, italic = false },

    -- Organizational Hierarchy: Modules, Namespaces, Packages
    DxNamespace = { fg = p.code.namespace, bold = false, italic = false },

    -- Literals & Constants
    DxString = { fg = p.code.string, bold = false, italic = false },
    DxNumber = { fg = p.code.number, bold = false, italic = false },
    DxConstant = { fg = p.code.constant, bold = false, italic = false },

    -- Control-flow Anchors: Loop & Goto Labels
    DxLabel = { fg = p.code.label, bold = false, italic = false },

    -- Structural Syntax & Operators
    DxOperator = { fg = p.code.operator, bold = false, italic = false },
    DxPunctuation = { fg = p.code.punctuation, bold = false, italic = false },

    -- Comments & Documentation
    DxComment = { fg = p.code.comment, italic = true },
    DxDocComment = { fg = p.code.doc, italic = true },

    -- Diagnostics & Transient States (Red Scarcity & Yellow Scarcity Enforced)
    DxError = { fg = p.state.error, bold = false, italic = false },
    DxWarn = { fg = p.state.warn, bold = false, italic = false },
    DxInfo = { fg = p.state.info, bold = false, italic = false },
    DxHint = { fg = p.state.hint, bold = false, italic = false },
  }
end

return M
