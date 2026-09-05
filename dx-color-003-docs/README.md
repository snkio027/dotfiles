# DX-COLOR-003 Development Documentation Set

- **Status:** M4 / C4.4 High-Chroma Night Candidate
- **Repository:** `snkio027/dotfiles`
- **Initial M0 baseline:** `19f0570ee33025832ff1d1d49269d303677d9c0f`
- **Current M4 base:** `9a7cea1579b6df1e8195be538beb0b1cb6bad901`
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

2. **C4 visual system**
   - redesign visual weight distribution using lessons observed from TokyoNight Night;
   - preserve the user's preferred hue region while avoiding red/green dependency;
   - use a larger luminance dynamic range rather than placing almost all roles in one muted middle band.

Architecture extraction and visual redesign MUST be delivered separately.

---

## 2. Required reading order for Codex

1. [`DX-COLOR-003-ARCHITECTURE.md`](./DX-COLOR-003-ARCHITECTURE.md)
2. [`DX-COLOR-003-IMPLEMENTATION-PLAN.md`](./DX-COLOR-003-IMPLEMENTATION-PLAN.md)
3. [`DX-COLOR-003-TEST-EVIDENCE-SPEC.md`](./DX-COLOR-003-TEST-EVIDENCE-SPEC.md)
4. [M3-A visual contract](./DX-COLOR-003-M3A-C4-VISUAL-CONTRACT.md)
5. [`DX-COLOR-003-C4-VISUAL-SPEC.md`](./DX-COLOR-003-C4-VISUAL-SPEC.md)
6. [Codex execution contract](./DX-COLOR-003-CODEX-EXECUTION-CONTRACT.md)

The M3-A contract is normative for visual relationships. The older C4 visual
specification is research input and contains candidate values; it does not
select the final C4 palette.

Milestone evidence records:

- [`DX-COLOR-003-M2A-BINDING-EVIDENCE.md`](./DX-COLOR-003-M2A-BINDING-EVIDENCE.md)
  — reproducible binding-topology observations and the M2A domain decision.
- [`DX-COLOR-003-M2B-STATIC-MEMBER-CLASSIFICATION.md`](./DX-COLOR-003-M2B-STATIC-MEMBER-CLASSIFICATION.md)
  — C++ static data member evidence, modifier priority analysis, and the
  existing-role classification decision.
- [`DX-COLOR-003-M2B-B-STATIC-MEMBER-CORRECTION.md`](./DX-COLOR-003-M2B-B-STATIC-MEMBER-CORRECTION.md)
  — the narrow clangd/C++ behavior correction, positive and negative runtime
  controls, and governed highlight-graph delta.
- [`DX-COLOR-003-M2C-PYTHON-PROVIDER-OWNERSHIP.md`](./DX-COLOR-003-M2C-PYTHON-PROVIDER-OWNERSHIP.md)
  — the Python provider activation provenance, isolated Ty exclusion experiment,
  capability evidence, and interactive-provider ownership decision.
- [`DX-COLOR-003-M2C-B-PYTHON-PROVIDER-CORRECTION.md`](./DX-COLOR-003-M2C-B-PYTHON-PROVIDER-CORRECTION.md)
  — the explicit Ty/Ruff production ownership correction, Pyright rollback
  boundary, capability matrix, and semantic-token provenance contract.
- [`DX-COLOR-003-M3B-C4-CANDIDATE.md`](./DX-COLOR-003-M3B-C4-CANDIDATE.md)
  — the first independently composable C4.0 palette and visual profile,
  profile-aware contracts, and resolved-graph governance.
- [`DX-COLOR-003-M3C-C4-SELECTOR.md`](./DX-COLOR-003-M3C-C4-SELECTOR.md)
  — the deterministic C3.1/C4 selector, fail-closed selection policy, and
  production runtime proof against the actual resolved `Normal.bg`.
- [`DX-COLOR-003-M4-C4-3-HIGH-SEPARATION-GRAPHITE.md`](./DX-COLOR-003-M4-C4-3-HIGH-SEPARATION-GRAPHITE.md)
  — the neutral Graphite experiment, its pairing contract, graph provenance,
  and the final human A/B rejection that motivated the visual rebase.
- [`DX-COLOR-003-M4-C4-4-HIGH-CHROMA-NIGHT.md`](./DX-COLOR-003-M4-C4-4-HIGH-CHROMA-NIGHT.md)
  — the TokyoNight-informed perceptual rebase, softened body white, dark navy
  canvas, full-color-wheel semantic axes, and C4.3-to-C4.4 provenance.

The architecture and test specifications are normative. The C4 color values are candidate visual values and require runtime visual acceptance before becoming the default profile.

Current milestone status:

```text
M1   Architecture extraction                    FROZEN
M2   Evidence / authority / provider governance CLOSED / FROZEN
M3-A C4 visual contract                         CLOSED / FROZEN
M3-B C4.0 candidate visual profile              CLOSED / FROZEN
M3-C Explicit C4 opt-in selector                CLOSED / FROZEN
M4   Human visual acceptance                    CURRENT

C3.1                                            DEPRECATED / FROZEN
C4.0                                            PASS WITH CHANGES / SUPERSEDED
C4.1 / C4.2                                     EXPERIMENTAL / SUPERSEDED
C4.3                                            A/B REJECTED / SUPERSEDED
C4.4                                            IMPLEMENTED / OPT-IN / NOT DEFAULT
```

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
M3-A Define the C4 visual contract
M3-B Implement an independent C4 visual profile
M3-C Expose C4 as an explicit opt-in
M4  Human visual acceptance
M5  Switch C4 to default and retire the C3.1 runtime path
```

M1 MUST NOT change rendered semantic output.

M3-A MUST NOT change runtime code or select final HEX values.

M3-B and M3-C MUST NOT silently change the default profile.

---

## 5. Repository paths in scope

Current core:

```text
home/dot_config/nvim/lua/theme/
  init.lua
  compose.lua
  domain.lua
  palette.lua
  authority.lua
  visual/
    c3_1.lua
    c4.lua
  bindings/
    treesitter.lua
    lsp.lua
    ui.lua
    plugins.lua
  adapters/
    zls.lua
    clangd.lua
    rust_analyzer.lua
    pyright.lua

home/dot_config/nvim/after/queries/
  rust/highlights.scm

tests/nvim/
  color_manifest.lua
  color_unit_contract.lua
  color_contract.lua
  binding_evidence.lua
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
