--- DX Semantic Color System (DX-COLOR-002)
--- Palette Definition: Decouples Source Semantic Colors from State and UI Colors.
--- Single Source of Truth for all Source Semantic Hex Literals.

local M = {}

--- Resolves the unified palette containing source semantic colors, transient state colors, and UI surfaces.
--- @param c table Catppuccin Mocha palette table
--- @return table
function M.resolve(c)
  return {
    -- 1. Normal Source Semantic Palette (Muted, Low-Glare, High-Ergonomics)
    -- Contrast against Mocha Base (#1E1E2E) strictly within 4.5:1 - 8.8:1
    code = {
      variable = "#B4BCD6", -- Neutral body identifiers (8.67:1)
      callable = "#D8AA7E", -- Execution landmarks / Functions & Methods (7.79:1 Muted Amber)
      type = "#82BCAD", -- Data model / User-defined types & structs (7.61:1 Muted Teal)
      lifetime = "#7DB1C3", -- Type-level lifetime bindings (6.99:1 Cyan)
      string = "#90B18F", -- Strings & regular expressions (6.89:1 Muted Sage)
      member = "#9DA4C7", -- Object structure / Fields & properties (6.69:1 Periwinkle)
      operator = "#9DA2B8", -- Operators & expressions (6.55:1)
      keyword = "#B298CE", -- Grammar & control flow constructs (6.51:1 Muted Violet)
      meta = "#C395B9", -- Compile-time macros, decorators & attributes (6.46:1 Dusty Pink)
      builtin = "#79A6C5", -- Primitives & system types (6.30:1 Muted Blue)
      parameter = "#A19CAF", -- Function signature boundaries (6.16:1 Muted Violet-Gray)
      constant = "#BB929B", -- Symbolic constants & enum variants (6.02:1 Dusty Rose)
      doc = "#9298AD", -- Documentation comments / API contracts (5.67:1)
      namespace = "#789BBF", -- Organization / Modules & packages (5.65:1)
      number = "#B99072", -- Numeric literals (5.65:1 Muted Brown)
      label = "#8D91A4", -- Control-flow anchors / Loop & goto labels (5.25:1)
      punctuation = "#858A9F", -- Delimiters & brackets (4.79:1)
      comment = "#81869E", -- Secondary explanatory prose (4.56:1)
    },

    -- 2. State & Transient Palette (High-Contrast Catppuccin Accents for Attention / Diagnostics)
    state = {
      error = c.red, -- Critical errors / Failures / Destructive operations
      warn = c.yellow, -- Attention NOW / Warnings / Search targets / Debugger pause
      info = c.sapphire, -- Informational messages
      hint = c.teal, -- Type hints & suggestions
      success = c.green, -- Passes / Clean status
    },

    -- 3. Surfaces & UI Chrome (Inherited from Catppuccin Mocha)
    ui = {
      base = c.base,
      mantle = c.mantle,
      crust = c.crust,
      surface0 = c.surface0,
      surface1 = c.surface1,
      surface2 = c.surface2,
      overlay0 = c.overlay0,
      overlay1 = c.overlay1,
      overlay2 = c.overlay2,
      subtext0 = c.subtext0,
      subtext1 = c.subtext1,
      text = c.text,
    },
  }
end

return M
