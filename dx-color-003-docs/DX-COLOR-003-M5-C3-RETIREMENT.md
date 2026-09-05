# DX-COLOR-003 M5 — C3.1 Runtime Retirement / C4.4 Promotion

<!-- markdownlint-disable MD013 -->

- **Milestone:** M5 / runtime retirement and production simplification
- **Base:** `65b61ee03bef0bc0bb8bee945d1bbc32a6a829b5`
- **Production visual:** C4.4 High-Chroma Night
- **Semantic / authority / provider delta:** none
- **Palette delta:** none
- **TokyoNight runtime dependency:** none

## Decision

Human A/B acceptance selected C4.4 High-Chroma Night for sustained use. M5
therefore retires C3.1 as an executable compatibility path and promotes C4.4
from an opt-in candidate to the only supported production visual.

This is not a palette iteration. Every accepted C4.4 HEX value remains
unchanged.

## Production topology

The former runtime topology was:

```text
theme selector
  ├─ C3.1 compatibility default
  └─ C4.4 explicit opt-in
```

M5 replaces it with:

```text
Evidence
  → Semantic Roles
  → Authority
  → C4 visual projection
  → C4.4 palette
  → Highlight graph
```

`theme.highlights()` now resolves `palette.code` and composes it directly with
`theme.visual.c4`. The following executable compatibility surfaces are absent:

```text
theme.visual.c3_1
theme.default_profile
theme.resolve_profile()
theme.active_profile()
vim.g.dx_color_profile selection contract
palette.code_profiles
default / opt-in / opt-out runtime fixtures
```

`palette.code` directly owns the accepted C4.4 source-semantic colors, while
`palette.ui.normal_bg` directly owns `#1A1B2A`.

## Preserved architecture

```text
Domain roles                 23 / unchanged
Semantic sentinels           42 / unchanged
M2A evidence                 28/28 + 15/15 / unchanged
M2B evidence and behavior    unchanged
M2C provider ownership       unchanged
Bindings / adapters          unchanged
Authority model              unchanged
Catppuccin Mocha             host theme retained
```

## Graph governance

The selector and palette indirection did not contribute highlight groups, so
the group count remains unchanged. Promoting C4.4 to the sole `palette.code`
owner does intentionally update eleven existing UI/plugin consumers that had
continued to read the C3.1 code palette while C4.4 was opt-in:

```text
CursorLineNr
DapBreakpointCondition
NeotestFocused
NeotestMarked
RenderMarkdownCodeInline
RenderMarkdownH1
RenderMarkdownH2
RenderMarkdownH3
RenderMarkdownHint
RenderMarkdownQuote
SnacksIndentScope
```

These groups receive only already accepted C4.4 palette values. No group is
added or removed, and no new HEX value is introduced. The resulting production
graph is frozen independently:

```text
M5 production C4.4
  226 / 51cfaae3c02ec25551f1a8afd27427d3919d6b53c3b05f5ae26ff6c125aa6666
```

Historical provenance remains executable. Starting from the M5 production
graph, the unit contract must reconstruct:

```text
Accepted C4.4 candidate after exact eleven-consumer rollback
  226 / 1ac13a349234d5926a250a82c6beb1135fe4483bfe1208f0e24245d4f0022fc8

C4.3 rejected candidate
  226 / 12d9299d27f50cc96bc056662ce13eed1bb1e46d7fc154f7bd5655216c7a8cc8

C4.0 historical candidate
  225 / 311ac3566f816d0fc03ad4ec92c74477d4ac82bf8cc2ab5cd82f95a12688c043

M2B C3.1 graph
  225 / a2db03bf6a138c0784d74277adf6f7ee706a5398336305385ced7d3725c0dedf

M1 historical graph
  221 / 05ff81df9019ace7bee14a494db1a9e39c7d18426f3b78bae1ef3012a068a276
```

This preserves immutable history without retaining a live rollback module or
selector.

## Runtime contract

Cold-start and Dev Container lifecycle verification now execute one production
visual runtime contract. It proves:

```text
Catppuccin host theme active
C4.4 owns all 23 Domain role foregrounds
representative Tree-sitter/LSP links resolve correctly
actual Normal.bg == #1A1B2A
C4.4 contrast and pairing gates pass against actual Normal.bg
```

Profile-selection and invalid-selector tests are removed because no selector
exists to validate.

## Completion definition

```text
C3.1 runtime module                ABSENT
C3.1 production palette           ABSENT
runtime profile selector          ABSENT
vim.g.dx_color_profile contract   ABSENT
C4.4                              SOLE VISUAL BASELINE
palette.code                       C4.4
Normal.bg                          #1A1B2A
historical graph provenance        PRESERVED
authorized palette consumers       EXACTLY 11
M5 production graph                226 / 51cfaae3c02ec25551f1a8afd27427d3919d6b53c3b05f5ae26ff6c125aa6666
C4.4 visual/pairing gates          PASS
semantic architecture              UNCHANGED
```
