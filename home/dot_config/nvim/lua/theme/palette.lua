--- DX Semantic Color System (DX-COLOR-003)
--- Palette Definition: Decouples Source Semantic Colors from State and UI Colors.
--- Single Source of Truth for all Source Semantic Hex Literals.

local M = {}

--- Resolves the unified palette containing source semantic colors, transient state colors, and UI surfaces.
--- @param c table Catppuccin Mocha palette table
--- @return table
function M.resolve(c)
  local code = {
    -- High-frequency semantic axes
    variable = "#C4CAE0",
    keyword = "#BB9AF7",
    keyword_function = "#7DCFFF",
    callable = "#E6B35C",
    type = "#2AC3DE",
    builtin = "#9ECE6A",
    member = "#F29BC1",

    -- Secondary semantic structure
    lifetime = "#67D4C7",
    parameter = "#C8B2E3",
    meta = "#D16DDB",
    namespace = "#5EA1FF",
    string = "#B8D07A",
    number = "#F09A6C",
    constant = "#DCC66A",

    -- Micro-syntax and prose
    label = "#8E98B8",
    operator = "#89DDFF",
    punctuation = "#8991A8",
    comment = "#7580A3",
    doc = "#929BC2",
  }

  local ui = {
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
    normal_bg = "#1A1B2A",
  }

  return {
    -- 1. Production Source Semantic Palette (C4.4 High-Chroma Night)
    code = code,

    -- 2. State & Transient Palette (CVD-Aware Accents without Red/Green Dependency)
    state = {
      error = c.red, -- Critical errors / Failures / Destructive operations (pink-red)
      warn = c.yellow, -- Attention NOW / Warnings / Search targets / Debugger pause
      success = c.sky, -- Passes / Clean status; CVD-aware Cyan-Sky avoids green dependency
      info = c.blue, -- Informational messages
      hint = c.lavender, -- Type hints & suggestions
    },

    -- 3. Surfaces & UI Chrome (Inherited from Catppuccin Mocha)
    ui = ui,
  }
end

return M
