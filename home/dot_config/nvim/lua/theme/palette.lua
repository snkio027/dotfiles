--- DX Semantic Color System (DX-COLOR-002)
--- Palette Definition: Decouples Source Semantic Colors from State and UI Colors.
--- Single Source of Truth for all Source Semantic Hex Literals.

local M = {}

--- Resolves the unified palette containing source semantic colors, transient state colors, and UI surfaces.
--- @param c table Catppuccin Mocha palette table
--- @return table
function M.resolve(c)
  return {
    -- 1. Normal Source Semantic Palette (Candidate C3 — CVD-aware, Hierarchy-First)
    -- Contrast against Mocha Base (#1E1E2E) strictly within 4.5:1 - 8.8:1
    code = {
      -- L1 — Primary landmarks
      callable = "#D8A972", -- 7.68:1 Amber execution landmark
      type = "#72AFC4", -- 6.75:1 Cyan structure anchor

      -- L2 — Semantic body
      string = "#ADA497", -- 6.67:1 Warm Stone (no green dependency)
      meta = "#C395B9", -- 6.50:1 Dusty Magenta
      keyword = "#B298CE", -- 6.46:1 Violet grammar
      lifetime = "#7DA6C8", -- 6.37:1 Cyan-blue
      variable = "#919CC4", -- 6.06:1 Blue-lilac semantic body
      member = "#A38BDA", -- 5.67:1 Periwinkle
      parameter = "#A58FB2", -- 5.60:1 Mauve
      builtin = "#7393B7", -- 5.14:1 Quiet Steel Blue

      -- L3 — Context
      doc = "#9298AD", -- 5.71:1 Secondary prose
      constant = "#B08BAA", -- 5.56:1 Dusty Orchid
      number = "#C18975", -- 5.55:1 Terracotta
      namespace = "#6D97CC", -- 5.43:1 Navigation Azure
      label = "#8D91A4", -- 5.25:1 Slate

      -- L4 — Scaffolding
      operator = "#898FA6", -- 5.11:1 Scaffolding
      punctuation = "#858A9F", -- 4.79:1 Scaffolding
      comment = "#81869E", -- 4.56:1 Deepest normal prose
    },

    -- 2. State & Transient Palette (CVD-Aware Accents without Red/Green Dependency)
    state = {
      error = c.red, -- Critical errors / Failures / Destructive operations (pink-red)
      warn = c.yellow, -- Attention NOW / Warnings / Search targets / Debugger pause
      success = c.sky, -- Passes / Clean status (CVD-safe Cyan-Sky replaces Green)
      info = c.blue, -- Informational messages
      hint = c.lavender, -- Type hints & suggestions
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
