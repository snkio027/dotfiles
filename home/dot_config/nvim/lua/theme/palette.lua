--- DX Semantic Color System (DX-COLOR-002)
--- Palette Candidate C2
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
      -- Execution: warm, unmistakable, but not glaring.
      callable = "#D8A972", -- 7.68:1

      -- User-defined types: move from green-teal toward clean cyan.
      -- Keeps the cold structural anchor without the "green" feeling.
      type = "#78B8BC", -- 7.33:1

      -- ----------------------------------------------------------------------
      -- L2 — Semantic Body
      -- ----------------------------------------------------------------------
      -- Rust lifetime: cyan-blue extension of the type family.
      lifetime = "#7DB1C3", -- 6.99:1

      -- Compile-time / macro / attributes.
      meta = "#C395B9", -- 6.50:1

      -- Language grammar and control flow.
      keyword = "#B298CE", -- 6.46:1

      -- Strings: muted parchment-gold.
      -- No green, but considerably more colored than neutral gray.
      string = "#B09E79", -- 6.26:1

      -- Members: stronger violet-periwinkle identity.
      member = "#9D95D3", -- 5.99:1

      -- Ordinary variables: blue-lilac instead of gray.
      variable = "#8F9BC2", -- 5.96:1

      -- Parameters: soft mauve, visibly distinct from local variables.
      parameter = "#A58FB8", -- 5.64:1

      -- Primitive/system types.
      -- Strongly reduced from the former bright blue.
      builtin = "#7396B8", -- 5.30:1

      -- ----------------------------------------------------------------------
      -- L3 — Context & Anchors
      -- ----------------------------------------------------------------------
      -- API/documentation prose.
      doc = "#9298AD", -- 5.71:1

      -- Modules / namespaces.
      namespace = "#7399CB", -- 5.58:1

      -- Numeric literals.
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
