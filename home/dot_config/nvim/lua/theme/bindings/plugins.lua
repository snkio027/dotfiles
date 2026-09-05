--- DX Semantic Color System (DX-COLOR-003)
--- Plugin-specific highlight integration, isolated from source semantics.

local M = {}

---@param p table Unified palette returned by palette.resolve()
---@return table<string, vim.api.keyset.highlight>
function M.groups(p)
  return {
    ["SnacksIndent"] = { fg = p.ui.surface1 },
    ["SnacksIndentScope"] = { fg = p.code.member },

    ["BlinkCmpKindFunction"] = { link = "DxCallable" },
    ["BlinkCmpKindMethod"] = { link = "DxCallable" },
    ["BlinkCmpKindConstructor"] = { link = "DxCallable" },
    ["BlinkCmpKindClass"] = { link = "DxType" },
    ["BlinkCmpKindStruct"] = { link = "DxType" },
    ["BlinkCmpKindInterface"] = { link = "DxType" },
    ["BlinkCmpKindEnum"] = { link = "DxType" },
    ["BlinkCmpKindTypeParameter"] = { link = "DxType" },
    ["BlinkCmpKindField"] = { link = "DxMember" },
    ["BlinkCmpKindProperty"] = { link = "DxMember" },
    ["BlinkCmpKindModule"] = { link = "DxNamespace" },
    ["BlinkCmpKindSnippet"] = { link = "DxMeta" },
    ["BlinkCmpKindMacro"] = { link = "DxMeta" },
    ["BlinkCmpKindVariable"] = { link = "DxVariable" },
    ["BlinkCmpKindValue"] = { link = "DxVariable" },
    ["BlinkCmpKindText"] = { link = "DxVariable" },
    ["BlinkCmpKindKeyword"] = { fg = p.ui.subtext0 },
    ["BlinkCmpKindFile"] = { fg = p.ui.subtext0 },
    ["BlinkCmpKindFolder"] = { fg = p.ui.subtext0 },

    ["NeotestPassed"] = { fg = p.state.success },
    ["NeotestFailed"] = { fg = p.state.error },
    ["NeotestRunning"] = { fg = p.state.warn },
    ["NeotestSkipped"] = { fg = p.ui.overlay1 },
    ["NeotestMarked"] = { fg = p.code.number },
    ["NeotestFocused"] = { fg = p.code.member },

    ["DapBreakpoint"] = { fg = p.state.error },
    ["DapBreakpointCondition"] = { fg = p.code.number },
    ["DapBreakpointRejected"] = { fg = p.ui.overlay1 },
    ["DapLogPoint"] = { fg = p.state.info },
    ["DapStopped"] = { fg = p.state.warn },
    ["DapStoppedLine"] = { bg = p.ui.surface1 },

    ["RenderMarkdownCodeInline"] = { fg = p.code.number, bg = "NONE" },
    ["RenderMarkdownDash"] = { fg = p.ui.surface1 },
    ["RenderMarkdownQuote"] = { fg = p.code.keyword },
    ["RenderMarkdownH1"] = { fg = p.code.keyword, bold = true },
    ["RenderMarkdownH2"] = { fg = p.code.member, bold = true },
    ["RenderMarkdownH3"] = { fg = p.code.type, bold = true },
    ["RenderMarkdownInfo"] = { fg = p.state.info },
    ["RenderMarkdownSuccess"] = { fg = p.state.hint },
    ["RenderMarkdownHint"] = { fg = p.code.keyword },
    ["RenderMarkdownWarn"] = { fg = p.state.warn },
    ["RenderMarkdownError"] = { fg = p.state.error },
  }
end

return M
