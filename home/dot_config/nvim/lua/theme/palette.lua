--- DX Semantic Color System (DX-COLOR-002)
--- Palette Candidate C1
---
--- Design model:
--- Primary landmarks -> Callable / Type
--- Semantic body -> Identifiers / structure / grammar
--- Context -> Constants / numbers / namespace / labels
--- Scaffolding -> Operators / punctuation / comments
---
--- High-contrast Catppuccin colors remain reserved for transient state.

local M = {}

--- Resolves the unified palette containing source semantic colors, transient state colors, and UI surfaces.
--- @param c table Catppuccin Mocha palette table
--- @return table
function M.resolve(c)
  return {
    -- ========================================================================
    -- Source Semantic Palette
    -- ========================================================================
    --
    -- Mocha Base: #1E1E2E
    --
    -- The palette intentionally uses both luminance hierarchy and hue/chroma
    -- separation. Not every semantic distinction needs equal visual weight.
    code = {
      -- ----------------------------------------------------------------------
      -- L1 — Primary Landmarks
      -- ----------------------------------------------------------------------
      -- Execution landmark.
      -- Warm amber provides immediate call-path recognition without bright
      -- Catppuccin Yellow glare.
      callable = "#D8A972", -- 7.68:1

      -- Data-model landmark.
      -- Clean muted teal; deliberately separated from Sage strings.
      type = "#77BEAC", -- 7.61:1

      -- ----------------------------------------------------------------------
      -- L2 — Semantic Body
      -- ----------------------------------------------------------------------
      -- Rust type-level lifetime bindings.
      -- Rare enough to remain relatively visible; belongs to cool type family.
      lifetime = "#7DB1C3", -- 6.99:1

      -- Ordinary program state.
      -- Reduced substantially from v2 #B4BCD6 so local variables no longer
      -- dominate the screen.
      variable = "#9FA7BE", -- 6.83:1

      -- Literal textual data.
      -- Calm Sage green; visibly distinct from Teal types.
      string = "#8EAE88", -- 6.69:1

      -- Language grammar and control flow.
      keyword = "#B298CE", -- 6.46:1

      -- Compile-time/meta layer: macros, attributes, decorators.
      meta = "#C395B9", -- 6.50:1

      -- Object structure.
      -- True violet/periwinkle shift rather than another neutral blue-gray.
      member = "#A19AD5", -- 6.33:1

      -- Primitive/system types.
      builtin = "#79A6C5", -- 6.31:1

      -- Signature boundary.
      -- Neutral mauve-gray: recognizable but intentionally quieter than
      -- callable/type/member.
      parameter = "#A49AAC", -- 6.09:1

      -- ----------------------------------------------------------------------
      -- L3 — Context & Anchors
      -- ----------------------------------------------------------------------
      -- API/documentation prose.
      doc = "#9298AD", -- 5.71:1

      -- Module/package/navigation hierarchy.
      -- Slightly more saturated blue than builtin, but lower luminance.
      namespace = "#7399CB", -- 5.58:1

      -- Numeric data.
      -- Terracotta family separates numbers from Amber callables while keeping
      -- them visually subordinate.
      number = "#C18975", -- 5.55:1

      -- Symbolic constants / enum variants.
      constant = "#B88892", -- 5.45:1

      -- Control-flow labels.
      label = "#8D91A4", -- 5.25:1

      -- ----------------------------------------------------------------------
      -- L4 — Syntactic Scaffolding
      -- ----------------------------------------------------------------------
      -- Expression mechanics should remain available but should never become
      -- a navigation landmark.
      operator = "#898FA6", -- 5.11:1

      -- Brackets, delimiters, separators.
      punctuation = "#858A9F", -- 4.79:1

      -- Secondary explanatory prose.
      comment = "#81869E", -- 4.56:1
    },

    -- ========================================================================
    -- Transient / State Palette
    -- ========================================================================
    --
    -- Bright Catppuccin accents are deliberately NOT used for normal source
    -- semantics. Their scarcity gives runtime state much stronger salience.
    state = {
      error = c.red,
      warn = c.yellow,
      info = c.sapphire,
      hint = c.teal,
      success = c.green,
    },

    -- ========================================================================
    -- UI Surface Palette
    -- ========================================================================
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
