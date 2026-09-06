# DX-COLOR-003 Development Documentation Set

- **Status:** M5 / C3.1 Runtime Retirement / C4.4 Promotion
- **Repository:** `snkio027/dotfiles`
- **Initial M0 baseline:** `19f0570ee33025832ff1d1d49269d303677d9c0f`
- **Current M5 base:** `65b61ee03bef0bc0bb8bee945d1bbc32a6a829b5`
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

The architecture and test specifications describe the current M5 normative
runtime and verification model. The M3-A contract is the frozen initial C4
design baseline; its C4.0 visual hypotheses were superseded by governed M4
human evidence. The older C4 visual specification remains research input.

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
  historical profile-aware contracts, and resolved-graph governance.
- [`DX-COLOR-003-M3C-C4-SELECTOR.md`](./DX-COLOR-003-M3C-C4-SELECTOR.md)
  — the deterministic C3.1/C4 selector, fail-closed selection policy, and
  production runtime proof against the actual resolved `Normal.bg`.
- [`DX-COLOR-003-M4-C4-3-HIGH-SEPARATION-GRAPHITE.md`](./DX-COLOR-003-M4-C4-3-HIGH-SEPARATION-GRAPHITE.md)
  — the neutral Graphite experiment, its pairing contract, graph provenance,
  and the final human A/B rejection that motivated the visual rebase.
- [`DX-COLOR-003-M4-C4-4-HIGH-CHROMA-NIGHT.md`](./DX-COLOR-003-M4-C4-4-HIGH-CHROMA-NIGHT.md)
  — the TokyoNight-informed perceptual rebase, softened body white, dark navy
  canvas, full-color-wheel semantic axes, and C4.3-to-C4.4 provenance.
- [`DX-COLOR-003-M4-HUMAN-ACCEPTANCE-CLOSURE.md`](./DX-COLOR-003-M4-HUMAN-ACCEPTANCE-CLOSURE.md)
  — the final `PASS`, actual A/B evidence, explicit five-language/timed-protocol
  waiver, decision authority, and limits of the human acceptance claim.
- [`DX-COLOR-003-M5-C3-RETIREMENT.md`](./DX-COLOR-003-M5-C3-RETIREMENT.md)
  — the removal of the executable C3.1 compatibility surface, promotion of
  C4.4 to the sole production visual, and historical graph reconstruction.

The architecture and test specifications are normative. C4.4 received a
governed human `PASS` under the recorded protocol waiver and is the sole
production visual baseline.

Current milestone status:

```text
M1   Architecture extraction                    FROZEN
M2   Evidence / authority / provider governance CLOSED / FROZEN
M3-A C4 visual contract                         CLOSED / FROZEN
M3-B C4.0 candidate visual profile              CLOSED / FROZEN
M3-C Explicit C4 opt-in selector                CLOSED / FROZEN
M4   Human visual acceptance                    CLOSED / PASS VIA GOVERNED WAIVER
M5   C3.1 retirement / C4.4 promotion           CURRENT

C3.1                                            RUNTIME RETIRED / HISTORY PRESERVED
C4.0                                            PASS WITH CHANGES / SUPERSEDED
C4.1 / C4.2                                     EXPERIMENTAL / SUPERSEDED
C4.3                                            A/B REJECTED / SUPERSEDED
C4.4                                            SOLE PRODUCTION VISUAL
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
