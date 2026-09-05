--- DX Semantic Color System (DX-COLOR-003)
--- Editor chrome, diagnostic state, and Git/diff state bindings.

local M = {}

---@param p table Unified palette returned by palette.resolve()
---@return table<string, vim.api.keyset.highlight>
function M.groups(p)
  local groups = {
    ["CursorLine"] = { bg = "NONE" },
    ["CursorLineNr"] = { fg = p.code.member, bold = true },
    ["Visual"] = { bg = p.ui.surface2 },

    ["CurSearch"] = { fg = p.ui.base, bg = p.state.warn },
    ["IncSearch"] = { fg = p.ui.base, bg = p.state.warn },
    ["Search"] = { fg = p.ui.text, bg = p.ui.surface2 },

    ["NormalFloat"] = { bg = p.ui.mantle },
    ["FloatBorder"] = { fg = p.ui.surface1, bg = p.ui.mantle },
    ["WinSeparator"] = { fg = p.ui.surface0 },
    ["Pmenu"] = { bg = p.ui.mantle, fg = p.ui.text },
    ["PmenuSel"] = { bg = p.ui.surface1, fg = p.ui.text },

    ["DiagnosticError"] = { fg = p.state.error },
    ["DiagnosticWarn"] = { fg = p.state.warn },
    ["DiagnosticInfo"] = { fg = p.state.info },
    ["DiagnosticHint"] = { fg = p.state.hint },

    ["DiagnosticUnderlineError"] = { undercurl = true, sp = p.state.error },
    ["DiagnosticUnderlineWarn"] = { undercurl = true, sp = p.state.warn },
    ["DiagnosticUnderlineInfo"] = { undercurl = true, sp = p.state.info },
    ["DiagnosticUnderlineHint"] = { undercurl = true, sp = p.state.hint },

    ["DiagnosticVirtualTextError"] = { fg = p.state.error },
    ["DiagnosticVirtualTextWarn"] = { fg = p.state.warn },
    ["DiagnosticVirtualTextInfo"] = { fg = p.state.info },
    ["DiagnosticVirtualTextHint"] = { fg = p.state.hint },

    ["GitSignsAdd"] = { fg = p.state.success },
    ["GitSignsChange"] = { fg = p.state.warn },
    ["GitSignsDelete"] = { fg = p.state.error },

    ["diffAdded"] = { fg = p.state.success },
    ["diffChanged"] = { fg = p.state.warn },
    ["diffRemoved"] = { fg = p.state.error },
  }

  if p.ui.normal_bg then
    groups["Normal"] = { bg = p.ui.normal_bg }
  end

  return groups
end

return M
