--- DX Semantic Color System (DX-COLOR-002)
--- External highlight namespace mappings: maps Tree-sitter, LSP semantic tokens,
--- editor UI, diagnostics, and plugins to abstract Dx* semantic roles.
--- Completely decoupled from Dx* role definitions ({ link = "DxRole" }).

local M = {}

---@param p table Unified palette returned by palette.resolve()
---@return table<string, vim.api.keyset.highlight>
function M.groups(p)
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
  hl["@function.builtin.zig"] = { link = "DxMeta" }
  hl["@constructor"] = { link = "DxCallable" }

  -- Data Models: User Types, Primitives, Lifetimes
  hl["@type"] = { link = "DxType" }
  hl["@type.definition"] = { link = "DxType" }
  hl["@type.builtin"] = { link = "DxBuiltin" }
  hl["@type.lifetime"] = { link = "DxLifetime" }
  hl["@type.lifetime.rust"] = { link = "DxLifetime" }

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
  hl["@attribute.builtin"] = { link = "DxMeta" }
  hl["@function.macro"] = { link = "DxMeta" }
  hl["@constant.macro"] = { link = "DxMeta" }

  -- Control-flow Anchors
  hl["@label"] = { link = "DxLabel" }

  -- Literals
  hl["@string"] = { link = "DxString" }
  hl["@string.documentation"] = { link = "DxDocComment" }
  hl["@string.regexp"] = { link = "DxString" }
  hl["@string.escape"] = { link = "DxString" }
  hl["@character"] = { link = "DxString" }
  hl["@character.special"] = { link = "DxPunctuation" }
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
  -- 2. LSP Semantic Tokens: Standard Closure & Observed Server Adapters
  -- ==========================================================================

  -- Standard LSP Types
  hl["@lsp.type.keyword"] = { link = "DxKeyword" }
  hl["@lsp.type.modifier"] = { link = "DxKeyword" }
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
  hl["@lsp.type.regexp"] = { link = "DxString" }
  hl["@lsp.type.number"] = { link = "DxNumber" }
  hl["@lsp.type.operator"] = { link = "DxOperator" }
  hl["@lsp.type.comment"] = { link = "DxComment" }
  hl["@lsp.type.event"] = { link = "DxMember" }

  -- Observed / Server-specific Adapters
  hl["@lsp.type.label"] = { link = "DxLabel" }
  hl["@lsp.type.lifetime"] = { link = "DxLifetime" }
  hl["@lsp.type.builtinType"] = { link = "DxBuiltin" }

  -- rust-analyzer extensions
  hl["@lsp.type.typeAlias"] = { link = "DxType" }
  hl["@lsp.type.union"] = { link = "DxType" }
  hl["@lsp.type.selfTypeKeyword"] = { link = "DxType" }

  -- clangd extensions
  hl["@lsp.type.concept"] = { link = "DxType" }

  -- zls extensions
  hl["@lsp.type.builtin"] = { link = "DxMeta" }
  hl["@lsp.type.keywordLiteral"] = { link = "DxConstant" }
  hl["@lsp.type.errorTag"] = { link = "DxConstant" }
  hl["@lsp.type.escapeSequence"] = { link = "DxString" }

  -- ==========================================================================
  -- 3. DX-COLOR Semantic Authority Model & Typemod Neutralization
  -- ==========================================================================

  -- Root highlight group for LSP foreground authority suppression.
  -- Has no foreground, no style attributes, and no dotted parent,
  -- ensuring Neovim's resolver will not fall back to parent @lsp.type.type.
  hl["LspForegroundPassthrough"] = {}

  -- Suppress generic type foreground for languages where LSP collapses
  -- primitive types and structured types into a generic "type" token.
  -- This allows Tree-sitter's precise @type.builtin capture to govern foreground color.
  hl["@lsp.type.type.c"] = { link = "LspForegroundPassthrough" }
  hl["@lsp.type.type.cpp"] = { link = "LspForegroundPassthrough" }
  hl["@lsp.type.type.zig"] = { link = "LspForegroundPassthrough" }

  -- Suppress generic variable and lifetime foreground for Rust where rust-analyzer collapses:
  -- 1) function parameters and local variables into a generic "variable" token.
  -- 2) loop control-flow labels and type lifetimes into a generic "lifetime" token.
  -- This allows Tree-sitter's precise queries to govern foreground color.
  hl["@lsp.type.variable.rust"] = { link = "LspForegroundPassthrough" }
  hl["@lsp.type.lifetime.rust"] = { link = "LspForegroundPassthrough" }

  hl["@lsp.typemod.variable.readonly"] = { link = "DxVariable" }
  hl["@lsp.typemod.variable.defaultLibrary"] = { link = "DxVariable" }
  hl["@lsp.typemod.variable.static"] = { link = "DxVariable" }
  hl["@lsp.typemod.property.readonly"] = { link = "DxMember" }
  hl["@lsp.typemod.function.defaultLibrary"] = { link = "DxCallable" }
  hl["@lsp.typemod.function.async"] = { link = "DxCallable" }
  hl["@lsp.typemod.method.defaultLibrary"] = { link = "DxCallable" }
  hl["@lsp.typemod.method.async"] = { link = "DxCallable" }

  -- Empirical modifier exception: Rust attribute identifiers (#[must_use])
  -- rust-analyzer emits namespace tagged with modifier attribute.
  hl["@lsp.typemod.namespace.attribute"] = { link = "DxMeta" }
  hl["@lsp.mod.attribute"] = { link = "DxMeta" }

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
  -- 4. Editor UI Chrome (Quiet, Receding Background)
  -- ==========================================================================

  hl["CursorLine"] = { bg = p.ui.surface0 }
  hl["CursorLineNr"] = { fg = p.code.member }
  hl["Visual"] = { bg = p.ui.surface2 }

  -- Search: high-contrast target, softer background matches (Yellow Scarcity applied)
  hl["CurSearch"] = { fg = p.ui.base, bg = p.state.warn }
  hl["IncSearch"] = { fg = p.ui.base, bg = p.state.warn }
  hl["Search"] = { fg = p.ui.text, bg = p.ui.surface2 }

  -- Floating UI & Separators
  hl["NormalFloat"] = { bg = p.ui.mantle }
  hl["FloatBorder"] = { fg = p.ui.surface1, bg = p.ui.mantle }
  hl["WinSeparator"] = { fg = p.ui.surface0 }
  hl["Pmenu"] = { bg = p.ui.mantle, fg = p.ui.text }
  hl["PmenuSel"] = { bg = p.ui.surface1, fg = p.ui.text }

  -- Indent Guides (Snacks indent)
  hl["SnacksIndent"] = { fg = p.ui.surface1 }
  hl["SnacksIndentScope"] = { fg = p.code.member }

  -- ==========================================================================
  -- 5. Diagnostics: State Signs & Undercurls (Preserve Token Foreground)
  -- ==========================================================================

  hl["DiagnosticError"] = { fg = p.state.error }
  hl["DiagnosticWarn"] = { fg = p.state.warn }
  hl["DiagnosticInfo"] = { fg = p.state.info }
  hl["DiagnosticHint"] = { fg = p.state.hint }

  hl["DiagnosticUnderlineError"] = { undercurl = true, sp = p.state.error }
  hl["DiagnosticUnderlineWarn"] = { undercurl = true, sp = p.state.warn }
  hl["DiagnosticUnderlineInfo"] = { undercurl = true, sp = p.state.info }
  hl["DiagnosticUnderlineHint"] = { undercurl = true, sp = p.state.hint }

  hl["DiagnosticVirtualTextError"] = { fg = p.state.error }
  hl["DiagnosticVirtualTextWarn"] = { fg = p.state.warn }
  hl["DiagnosticVirtualTextInfo"] = { fg = p.state.info }
  hl["DiagnosticVirtualTextHint"] = { fg = p.state.hint }

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
  hl["BlinkCmpKindKeyword"] = { fg = p.ui.subtext0 }
  hl["BlinkCmpKindFile"] = { fg = p.ui.subtext0 }
  hl["BlinkCmpKindFolder"] = { fg = p.ui.subtext0 }

  -- ==========================================================================
  -- 7. Git & Diff State Contract
  -- ==========================================================================

  hl["GitSignsAdd"] = { fg = p.state.success }
  hl["GitSignsChange"] = { fg = p.state.warn }
  hl["GitSignsDelete"] = { fg = p.state.error }

  hl["diffAdded"] = { fg = p.state.success }
  hl["diffChanged"] = { fg = p.state.warn }
  hl["diffRemoved"] = { fg = p.state.error }

  -- ==========================================================================
  -- 8. DAP & Neotest State Contract
  -- ==========================================================================

  -- Neotest State
  hl["NeotestPassed"] = { fg = p.state.success }
  hl["NeotestFailed"] = { fg = p.state.error }
  hl["NeotestRunning"] = { fg = p.state.warn }
  hl["NeotestSkipped"] = { fg = p.ui.overlay1 }
  hl["NeotestMarked"] = { fg = p.code.number }
  hl["NeotestFocused"] = { fg = p.code.member }

  -- DAP State
  hl["DapBreakpoint"] = { fg = p.state.error }
  hl["DapBreakpointCondition"] = { fg = p.code.number }
  hl["DapBreakpointRejected"] = { fg = p.ui.overlay1 }
  hl["DapLogPoint"] = { fg = p.state.info }
  hl["DapStopped"] = { fg = p.state.warn }
  hl["DapStoppedLine"] = { bg = p.ui.surface1 }

  -- ==========================================================================
  -- 9. Markdown Presentation (render-markdown)
  -- ==========================================================================

  hl["RenderMarkdownCodeInline"] = { fg = p.code.number, bg = "NONE" }
  hl["RenderMarkdownDash"] = { fg = p.ui.surface1 }
  hl["RenderMarkdownQuote"] = { fg = p.code.keyword }

  hl["RenderMarkdownH1"] = { fg = p.code.keyword, bold = true }
  hl["RenderMarkdownH2"] = { fg = p.code.member, bold = true }
  hl["RenderMarkdownH3"] = { fg = p.code.type, bold = true }

  -- Admonitions
  hl["RenderMarkdownInfo"] = { fg = p.state.info }
  hl["RenderMarkdownSuccess"] = { fg = p.state.hint }
  hl["RenderMarkdownHint"] = { fg = p.code.keyword }
  hl["RenderMarkdownWarn"] = { fg = p.state.warn }
  hl["RenderMarkdownError"] = { fg = p.state.error }

  return hl
end

return M
