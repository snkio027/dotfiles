--- DX Semantic Color System (DX-COLOR-001)
--- Semantic Role Definitions: maps abstract program semantics to palette roles.
--- Zero external plugin knowledge; pure semantic role contract.

local M = {}

---@param colors table Catppuccin Mocha named palette table
---@return table<string, vim.api.keyset.highlight>
function M.roles(colors)
  return {
    -- Language Grammar & Core Constructs
    DxKeyword = { fg = colors.mauve, bold = false, italic = false },

    -- Execution Landmarks: Functions & Methods
    DxCallable = { fg = colors.yellow, bold = false, italic = false },

    -- Data Models: User-defined Structs, Classes, Enums, Interfaces, Type Parameters
    DxType = { fg = colors.teal, bold = false, italic = false },

    -- Primitives & Builtin Types: u64, int, bool, str, float
    DxBuiltin = { fg = colors.sapphire, bold = false, italic = false },

    -- Object Structure: Fields, Properties, Members
    DxMember = { fg = colors.lavender, bold = false, italic = false },

    -- Signature Boundary: Function Parameters
    DxParameter = { fg = colors.rosewater, bold = false, italic = false },

    -- Neutral Foreground: Local Variables (preserves low visual noise)
    DxVariable = { fg = colors.text, bold = false, italic = false },

    -- Meta-programming: Attributes, Derive Macros, Decorators, Builtin Macros
    DxMeta = { fg = colors.pink, bold = false, italic = false },

    -- Organizational Hierarchy: Modules, Namespaces, Packages
    DxNamespace = { fg = colors.blue, bold = false, italic = false },

    -- Literals & Constants
    DxString = { fg = colors.green, bold = false, italic = false },
    DxNumber = { fg = colors.peach, bold = false, italic = false },
    DxConstant = { fg = colors.flamingo, bold = false, italic = false },

    -- Structural Syntax & Operators
    DxOperator = { fg = colors.subtext1, bold = false, italic = false },
    DxPunctuation = { fg = colors.subtext0, bold = false, italic = false },

    -- Comments & Documentation
    DxComment = { fg = colors.overlay1, italic = true },
    DxDocComment = { fg = colors.subtext0, italic = true },

    -- Diagnostics & Transient States (Red Scarcity: Red strictly reserved for DxError)
    DxError = { fg = colors.red, bold = false, italic = false },
    DxWarn = { fg = colors.yellow, bold = false, italic = false },
    DxInfo = { fg = colors.sapphire, bold = false, italic = false },
    DxHint = { fg = colors.teal, bold = false, italic = false },
  }
end

return M
