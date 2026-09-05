# DX-COLOR-003 Development Documentation Set

- **Status:** Development Specification
- **Repository:** `snkio027/dotfiles`
- **Baseline:** `19f0570ee33025832ff1d1d49269d303677d9c0f`
- **Host theme:** Catppuccin Mocha
- **Target editor:** Neovim / LazyVim
- **Languages in current verification matrix:** Rust, C, C++23, Zig, Python
- **Purpose:** Provide a complete, normative implementation contract for Codex.

---

## 1. Decision

DX-COLOR-003 does **not** replace Catppuccin and does **not** adopt TokyoNight as a runtime dependency.

The project retains:

- Catppuccin Mocha as the host UI theme;
- the existing DX semantic role model;
- the Semantic Authority Model;
- the current multi-language runtime verification system.

DX-COLOR-003 introduces two changes:

1. **Architecture extraction**
   - external Tree-sitter/LSP vocabularies are isolated behind bindings and provider adapters;
   - semantic authority becomes an explicit architectural concern;
   - visual projection is separated from the semantic domain.

2. **C4 visual profile**
   - redesign visual weight distribution using lessons observed from TokyoNight Night;
   - preserve the user's preferred hue region while avoiding red/green dependency;
   - use a larger luminance dynamic range rather than placing almost all roles in one muted middle band.

Architecture extraction and visual redesign MUST be delivered separately.

---

## 2. Required reading order for Codex

1. [`DX-COLOR-003-ARCHITECTURE.md`](./DX-COLOR-003-ARCHITECTURE.md)
2. [`DX-COLOR-003-IMPLEMENTATION-PLAN.md`](./DX-COLOR-003-IMPLEMENTATION-PLAN.md)
3. [`DX-COLOR-003-TEST-EVIDENCE-SPEC.md`](./DX-COLOR-003-TEST-EVIDENCE-SPEC.md)
4. [`DX-COLOR-003-C4-VISUAL-SPEC.md`](./DX-COLOR-003-C4-VISUAL-SPEC.md)
5. [`DX-COLOR-003-CODEX-EXECUTION-CONTRACT.md`](./DX-COLOR-003-CODEX-EXECUTION-CONTRACT.md)

The architecture and test specifications are normative. The C4 color values are candidate visual values and require runtime visual acceptance before becoming the default profile.

---

## 3. Core invariants

```text
External vocabulary never defines internal meaning.

Same semantic meaning has the same visual meaning across languages.

Authority is granted only when the producer preserves the distinction we care about.

No evidence -> no provider-specific special case.

Color encodes meaning; visual weight encodes importance.
```

---

## 4. Delivery phases

```text
M0  Freeze and record baseline
M1  Behavior-preserving architecture extraction
M2  Expand evidence for language/provider distinctions
M3  Add C4 visual profile as opt-in
M4  Human visual acceptance
M5  Switch default profile only after acceptance
```

M1 MUST NOT change rendered semantic output.

M3 MUST NOT silently change the default profile.

---

## 5. Repository paths in scope

Current core:

```text
home/dot_config/nvim/lua/theme/
  init.lua
  palette.lua
  semantic.lua
  mappings.lua

home/dot_config/nvim/after/queries/
  rust/highlights.scm

tests/nvim/
  color_manifest.lua
  color_unit_contract.lua
  color_contract.lua
  color/
```

Target architecture is defined in the architecture specification.

---

## 6. Explicit non-goals

DX-COLOR-003 is not:

- a colorscheme replacement;
- a TokyoNight fork;
- a general-purpose Neovim highlighting framework;
- a dynamic semantic-token renderer;
- a new LSP client;
- an attempt to normalize every token emitted by every language server;
- a reason to introduce speculative semantic roles.

No new runtime dependency is authorized by this specification.

---

## 7. Merge policy

Every milestone must be reviewable independently.

A PR is mergeable only when:

- its scope matches the milestone;
- existing evidence contracts remain valid;
- new claims are backed by runtime evidence;
- all required CI lanes pass;
- no unrelated visual or architecture changes are bundled.

Visual acceptance is a separate human gate and cannot be inferred from unit tests.
