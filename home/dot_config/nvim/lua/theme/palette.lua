--- DX Semantic Color System (DX-COLOR-003)
--- Palette Definition: Decouples Source Semantic Colors from State and UI Colors.
--- Single Source of Truth for all Source Semantic Hex Literals.

local M = {}

--- Resolves the unified palette containing source semantic colors, transient state colors, and UI surfaces.
--- @param c table Catppuccin Mocha palette table
--- @param profile_name? string Selected visual profile; only C4 owns a canvas override
--- @return table
function M.resolve(c, profile_name)
  local c4 = {
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
  }
  if profile_name == "c4" then
    ui.normal_bg = "#1A1B2A"
  end

  return {
    -- 1. Normal Source Semantic Palette (Candidate C3 — CVD-aware, Hierarchy-First)
    -- Contrast against Mocha Base (#1E1E2E) strictly within 4.5:1 - 8.8:1
    code = {
      -- L1 — Primary landmarks
      callable = "#D8A972", -- 7.68:1 Amber execution landmark
      type = "#78B6CC", -- Clear Sky Blue structure anchor

      -- L2 — Semantic body
      string = "#ADA497", -- 6.67:1 Warm Stone (no green dependency)
      meta = "#C395B9", -- 6.50:1 Dusty Magenta
      keyword = "#B298CE", -- 6.46:1 Violet grammar
      keyword_function = "#82AEDB", -- Sky Blue function declaration marker (fn / def)
      lifetime = "#7DA6C8", -- 6.37:1 Cyan-blue
      variable = "#989FCC", -- Clear Blue-lilac semantic body
      member = "#AA91DF", -- Vibrant Periwinkle purple
      parameter = "#AA94BE", -- Mauve signature boundary
      builtin = "#7393B7", -- 5.14:1 Quiet Steel Blue

      -- L3 — Context
      doc = "#9298AD", -- 5.71:1 Secondary prose
      constant = "#B78EAF", -- Orchid pink breathing accent
      number = "#C18975", -- 5.55:1 Terracotta
      namespace = "#75A0D8", -- Clear Sky Blue navigation axis
      label = "#8D91A4", -- 5.25:1 Slate

      -- L4 — Scaffolding
      operator = "#898FA6", -- 5.11:1 Scaffolding
      punctuation = "#858A9F", -- 4.79:1 Scaffolding
      comment = "#81869E", -- 4.56:1 Deepest normal prose
    },

    -- Independent candidate profiles. `code` remains the frozen C3.1 palette
    -- until a later milestone adds an explicit runtime selector.
    code_profiles = {
      c4 = c4,
    },

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
