--- DX Semantic Color System (DX-COLOR-001)
--- External highlight namespace mappings: maps Tree-sitter, LSP semantic tokens,
--- editor UI, diagnostics, and plugins to the Dx* semantic layer.

local M = {}

---@param colors table Catppuccin Mocha named palette table
---@return table<string, vim.api.keyset.highlight>
function M.mappings(colors)
  local hl = {}

  -- ==========================================================================
  -- 1. Tree-sitter Standard Captures
  -- ==========================================================================

  -- Language Grammar & Keywords
  hl["@keyword"] = { link = "DxKeyword" }
  hl["@keyword.function"] = { link = "DxKeyword" }
  hl["@keyword.return"] = { link = "DxKeyword" }
  hl["@keyword.type"] = { link = "DxKeyword" }
  hl["@keyword.import"] = { link = "DxKeyword" }
  hl["@keyword.conditional"] = { link = "DxKeyword" }
  hl["@keyword.repeat"] = { link = "DxKeyword" }
  hl["@keyword.coroutine"] = { link = "DxKeyword" }
  hl["@keyword.operator"] = { link = "DxKeyword" }
  hl["@keyword.modifier"] = { link = "DxKeyword" }
  hl["@keyword.exception"] = { link = "DxKeyword" }
  hl["@keyword.directive"] = { link = "DxKeyword" }
  hl["@keyword.directive.define"] = { link = "DxKeyword" }
  hl["@keyword.storage"] = { link = "DxKeyword" }

  -- Callables: Functions & Methods
  hl["@function"] = { link = "DxCallable" }
  hl["@function.call"] = { link = "DxCallable" }
  hl["@function.method"] = { link = "DxCallable" }
  hl["@function.method.call"] = { link = "DxCallable" }
  hl["@function.builtin"] = { link = "DxCallable" }
  hl["@constructor"] = { link = "DxCallable" }

  -- Data Models: User Types & Primitives
  hl["@type"] = { link = "DxType" }
  hl["@type.definition"] = { link = "DxType" }
  hl["@type.builtin"] = { link = "DxBuiltin" }

  -- Variables, Parameters, Members
  hl["@variable"] = { link = "DxVariable" }
  hl["@variable.builtin"] = { link = "DxVariable" }
  hl["@variable.parameter"] = { link = "DxParameter" }
  hl["@variable.member"] = { link = "DxMember" }
  hl["@property"] = { link = "DxMember" }

  -- Namespaces & Modules
  hl["@module"] = { link = "DxNamespace" }
  hl["@module.builtin"] = { link = "DxNamespace" }

  -- Meta-programming: Attributes, Macros, Decorators
  hl["@attribute"] = { link = "DxMeta" }
  hl["@function.macro"] = { link = "DxMeta" }

  -- Literals
  hl["@string"] = { link = "DxString" }
  hl["@string.documentation"] = { link = "DxDocComment" }
  hl["@character"] = { link = "DxString" }
  hl["@number"] = { link = "DxNumber" }
  hl["@number.float"] = { link = "DxNumber" }
  hl["@boolean"] = { link = "DxConstant" }
  hl["@constant"] = { link = "DxConstant" }
  hl["@constant.builtin"] = { link = "DxConstant" }

  -- Operators & Punctuation
  hl["@operator"] = { link = "DxOperator" }
  hl["@punctuation.delimiter"] = { link = "DxPunctuation" }
  hl["@punctuation.bracket"] = { link = "DxPunctuation" }
  hl["@punctuation.special"] = { link = "DxPunctuation" }

  -- Comments
  hl["@comment"] = { link = "DxComment" }
  hl["@comment.documentation"] = { link = "DxDocComment" }
  hl["@comment.error"] = { link = "DxError" }
  hl["@comment.warning"] = { link = "DxWarn" }
  hl["@comment.todo"] = { link = "DxWarn" }
  hl["@comment.note"] = { link = "DxInfo" }

  -- ==========================================================================
  -- 2. LSP Semantic Tokens: Base Standard Closure
  -- ==========================================================================

  hl["@lsp.type.keyword"] = { link = "DxKeyword" }
  hl["@lsp.type.function"] = { link = "DxCallable" }
  hl["@lsp.type.method"] = { link = "DxCallable" }
  hl["@lsp.type.class"] = { link = "DxType" }
  hl["@lsp.type.struct"] = { link = "DxType" }
  hl["@lsp.type.enum"] = { link = "DxType" }
  hl["@lsp.type.interface"] = { link = "DxType" }
  hl["@lsp.type.type"] = { link = "DxType" }
  hl["@lsp.type.typeParameter"] = { link = "DxType" }
  hl["@lsp.type.property"] = { link = "DxMember" }
  hl["@lsp.type.parameter"] = { link = "DxParameter" }
  hl["@lsp.type.variable"] = { link = "DxVariable" }
  hl["@lsp.type.namespace"] = { link = "DxNamespace" }
  hl["@lsp.type.macro"] = { link = "DxMeta" }
  hl["@lsp.type.decorator"] = { link = "DxMeta" }
  hl["@lsp.type.enumMember"] = { link = "DxConstant" }
  hl["@lsp.type.string"] = { link = "DxString" }
  hl["@lsp.type.number"] = { link = "DxNumber" }
  hl["@lsp.type.operator"] = { link = "DxOperator" }
  hl["@lsp.type.comment"] = { link = "DxComment" }

  -- Optional server-specific adapter (non-standard token fallback)
  hl["@lsp.type.builtinType"] = { link = "DxBuiltin" }

  -- ==========================================================================
  -- 3. LSP Precedence Governance: Typemod Neutralization & Deprecated Style
  -- ==========================================================================

  -- Neutralize high-precedence modifiers (typemod priority 127) to maintain neutrality
  hl["@lsp.typemod.variable.readonly"] = { link = "DxVariable" }
  hl["@lsp.typemod.variable.defaultLibrary"] = { link = "DxVariable" }
  hl["@lsp.typemod.variable.static"] = { link = "DxVariable" }
  hl["@lsp.typemod.property.readonly"] = { link = "DxMember" }
  hl["@lsp.typemod.function.defaultLibrary"] = { link = "DxCallable" }
  hl["@lsp.typemod.function.async"] = { link = "DxCallable" }
  hl["@lsp.typemod.method.defaultLibrary"] = { link = "DxCallable" }
  hl["@lsp.typemod.method.async"] = { link = "DxCallable" }

  -- Style-only deprecated composition: strikethrough without destroying semantic identity
  hl["@lsp.mod.deprecated"] = { strikethrough = true }

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

  -- ==========================================================================
  -- 4. Editor UI Chrome (Quiet, receding background)
  -- ==========================================================================

  hl["CursorLine"] = { bg = colors.surface0 }
  hl["CursorLineNr"] = { fg = colors.lavender }
  hl["Visual"] = { bg = colors.surface2 }

  -- Search: high-contrast target, softer background matches
  hl["CurSearch"] = { fg = colors.base, bg = colors.yellow }
  hl["IncSearch"] = { fg = colors.base, bg = colors.yellow }
  hl["Search"] = { fg = colors.text, bg = colors.surface2 }

  -- Floating UI & Separators
  hl["NormalFloat"] = { bg = colors.mantle }
  hl["FloatBorder"] = { fg = colors.surface1, bg = colors.mantle }
  hl["WinSeparator"] = { fg = colors.surface0 }
  hl["Pmenu"] = { bg = colors.mantle, fg = colors.text }
  hl["PmenuSel"] = { bg = colors.surface1, fg = colors.text }

  -- Indent Guides (Snacks indent)
  hl["SnacksIndent"] = { fg = colors.surface1 }
  hl["SnacksIndentScope"] = { fg = colors.lavender }

  -- ==========================================================================
  -- 5. Diagnostics: State Signs & Undercurls (Preserve Token Foreground)
  -- ==========================================================================

  hl["DiagnosticError"] = { fg = colors.red }
  hl["DiagnosticWarn"] = { fg = colors.yellow }
  hl["DiagnosticInfo"] = { fg = colors.sapphire }
  hl["DiagnosticHint"] = { fg = colors.teal }

  hl["DiagnosticUnderlineError"] = { undercurl = true, sp = colors.red }
  hl["DiagnosticUnderlineWarn"] = { undercurl = true, sp = colors.yellow }
  hl["DiagnosticUnderlineInfo"] = { undercurl = true, sp = colors.sapphire }
  hl["DiagnosticUnderlineHint"] = { undercurl = true, sp = colors.teal }

  hl["DiagnosticVirtualTextError"] = { fg = colors.red }
  hl["DiagnosticVirtualTextWarn"] = { fg = colors.yellow }
  hl["DiagnosticVirtualTextInfo"] = { fg = colors.sapphire }
  hl["DiagnosticVirtualTextHint"] = { fg = colors.teal }

  -- ==========================================================================
  -- 6. Completion (blink.cmp)
  -- ==========================================================================

  hl["BlinkCmpKindFunction"] = { link = "DxCallable" }
  hl["BlinkCmpKindMethod"] = { link = "DxCallable" }
  hl["BlinkCmpKindConstructor"] = { link = "DxCallable" }

  hl["BlinkCmpKindClass"] = { link = "DxType" }
  hl["BlinkCmpKindStruct"] = { link = "DxType" }
  hl["BlinkCmpKindInterface"] = { link = "DxType" }
  hl["BlinkCmpKindEnum"] = { link = "DxType" }
  hl["BlinkCmpKindTypeParameter"] = { link = "DxType" }

  hl["BlinkCmpKindField"] = { link = "DxMember" }
  hl["BlinkCmpKindProperty"] = { link = "DxMember" }

  hl["BlinkCmpKindModule"] = { link = "DxNamespace" }

  hl["BlinkCmpKindSnippet"] = { link = "DxMeta" }
  hl["BlinkCmpKindMacro"] = { link = "DxMeta" }

  -- Neutral completion categories
  hl["BlinkCmpKindVariable"] = { link = "DxVariable" }
  hl["BlinkCmpKindValue"] = { link = "DxVariable" }
  hl["BlinkCmpKindText"] = { link = "DxVariable" }
  hl["BlinkCmpKindKeyword"] = { fg = colors.subtext0 }
  hl["BlinkCmpKindFile"] = { fg = colors.subtext0 }
  hl["BlinkCmpKindFolder"] = { fg = colors.subtext0 }

  -- ==========================================================================
  -- 7. Git & Diff State Contract
  -- ==========================================================================

  hl["GitSignsAdd"] = { fg = colors.green }
  hl["GitSignsChange"] = { fg = colors.yellow }
  hl["GitSignsDelete"] = { fg = colors.red }

  hl["diffAdded"] = { fg = colors.green }
  hl["diffChanged"] = { fg = colors.yellow }
  hl["diffRemoved"] = { fg = colors.red }

  -- ==========================================================================
  -- 8. DAP & Neotest State Contract
  -- ==========================================================================

  -- Neotest State
  hl["NeotestPassed"] = { fg = colors.green }
  hl["NeotestFailed"] = { fg = colors.red }
  hl["NeotestRunning"] = { fg = colors.yellow }
  hl["NeotestSkipped"] = { fg = colors.overlay1 }
  hl["NeotestMarked"] = { fg = colors.peach }
  hl["NeotestFocused"] = { fg = colors.lavender }

  -- DAP State
  hl["DapBreakpoint"] = { fg = colors.red }
  hl["DapBreakpointCondition"] = { fg = colors.peach }
  hl["DapBreakpointRejected"] = { fg = colors.overlay1 }
  hl["DapLogPoint"] = { fg = colors.sapphire }
  hl["DapStopped"] = { fg = colors.yellow }
  hl["DapStoppedLine"] = { bg = colors.surface1 }

  -- ==========================================================================
  -- 9. Markdown Presentation (render-markdown)
  -- ==========================================================================

  hl["RenderMarkdownCodeInline"] = { fg = colors.peach, bg = "NONE" }
  hl["RenderMarkdownDash"] = { fg = colors.surface1 }
  hl["RenderMarkdownQuote"] = { fg = colors.mauve }

  hl["RenderMarkdownH1"] = { fg = colors.mauve, bold = true }
  hl["RenderMarkdownH2"] = { fg = colors.lavender, bold = true }
  hl["RenderMarkdownH3"] = { fg = colors.teal, bold = true }

  -- Admonitions
  hl["RenderMarkdownInfo"] = { fg = colors.sapphire }
  hl["RenderMarkdownSuccess"] = { fg = colors.teal }
  hl["RenderMarkdownHint"] = { fg = colors.mauve }
  hl["RenderMarkdownWarn"] = { fg = colors.yellow }
  hl["RenderMarkdownError"] = { fg = colors.red }

  return hl
end

return M
