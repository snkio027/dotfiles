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
    keyword = "#79AAFF",
    keyword_function = "#79AAFF",
    callable = "#FFB266",
    type = "#3DD1BB",
    builtin = "#9ECE6A",
    member = "#F29BC1",

    -- Secondary semantic structure
    lifetime = "#67D4C7",
    parameter = "#C8B2E3",
    meta = "#FF8F7D",
    namespace = "#DB8FEE",
    string = "#B8D07A",
    number = "#F2D675",
    constant = "#F2D675",

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
    -- Decorative consumers retain their C4.4 appearance independently of E source colors.
    accent_violet = "#BB9AF7",
    accent_cyan = "#2AC3DE",
    accent_orange = "#F09A6C",
  }

  return {
    -- 1. Production Source Semantic Palette (E: 19 source roles, 17 colors)
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
