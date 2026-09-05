# DX-COLOR-003 — Implementation Plan

- **Document ID:** DX-COLOR-003-PLAN
- **Status:** Normative Execution Plan

---

## 1. Delivery strategy

Do not combine architecture refactoring and visual redesign.

Required sequence:

```text
M0 Baseline Freeze
      ↓
M1 Architecture Extraction
      ↓
M2 Evidence / Authority / Provider Governance
      ↓
M3-A C4 Visual Contract
      ↓
M3-B C4 Visual Profile
      ↓
M3-C C4 Opt-In Runtime
      ↓
M4 Human Visual Gate
      ↓
M5 C4 Default + C3.1 Retirement
```

Each milestone should produce an independently reviewable commit or PR.

---

## 2. M0 — Freeze baseline

### M0 objective

Record the exact repository and runtime baseline before refactoring.

Initial design baseline:

```text
19f0570ee33025832ff1d1d49269d303677d9c0f
```

At implementation time Codex MUST re-read `origin/main` and record the actual starting SHA. If `main` has moved, it must compare the changes and stop if they materially affect the theme system.

### Required evidence

Capture:

```text
git rev-parse HEAD
git status --short
nvim --version
chezmoi --version
```

Run existing validation:

```bash
nvim -u NONE -i NONE --headless \
  "+set rtp^=$PWD/home/dot_config/nvim" \
  "+luafile tests/nvim/color_unit_contract.lua" \
  +qa

bash tests/nvim/color/validate_fixtures.sh

nvim -n --headless \
  "+luafile tests/nvim/color_contract.lua" \
  +qa
```

Use strict LSP lane where the current project requires it.

### Output

No source changes.

A short baseline note in the PR description is sufficient.

---

## 3. M1 — Behavior-preserving architecture extraction

### M1 objective

Split responsibilities without changing the effective C3.1 visual result.

### Prohibited in M1

- no C4 colors;
- no role additions;
- no role removals;
- no new LSP authority decisions;
- no new Tree-sitter query behavior;
- no UI redesign;
- no TokyoNight dependency;
- no default colorscheme change.

### File operations

Create:

```text
theme/domain.lua
theme/compose.lua
theme/authority.lua
theme/visual/c3_1.lua
theme/bindings/treesitter.lua
theme/bindings/lsp.lua
theme/bindings/ui.lua
theme/bindings/plugins.lua
theme/adapters/zls.lua
theme/adapters/clangd.lua
theme/adapters/rust_analyzer.lua
theme/adapters/pyright.lua
```

Refactor:

```text
theme/init.lua
theme/palette.lua
theme/semantic.lua
theme/mappings.lua
```

`mappings.lua` may be removed only after all responsibilities have migrated.

### M1 substeps

#### M1.1 Extract domain registry

Move the role closure/descriptions into `domain.lua`.

Do not change role names.

#### M1.2 Preserve C3.1 as named visual profile

Create `visual/c3_1.lua`.

The resolved role attributes MUST equal the baseline.

#### M1.3 Extract generic Tree-sitter bindings

Move universal capture mappings.

#### M1.4 Extract generic LSP bindings

Move standard safe LSP token mappings.

#### M1.5 Extract provider adapters

Move only already-proven provider-specific behavior.

#### M1.6 Extract authority primitives

Move `LspForegroundPassthrough` and reusable helper semantics.

#### M1.7 Extract UI/plugin mappings

Move non-source highlight groups out of source bindings.

#### M1.8 Compose final graph

Implement deterministic composition.

---

## 4. M1 equivalence gate

A new behavior-preserving test SHOULD compare baseline expected groups against the refactored composition.

Do not compare Lua table iteration order.

Compare normalized effective definitions:

```text
group name
resolved link or attributes
foreground
background
style flags
special color
```

At minimum verify all currently governed groups.

M1 must finish with:

```text
42/42 current sentinels unchanged
23/23 current roles unchanged
all current authority decisions unchanged
full CI green
```

---

## 5. M2 — Evidence / authority / provider governance

### M2 objective

M2 collected semantic evidence for binding topology, corrected proven authority
anomalies, and made interactive provider ownership explicit.

M2 is now closed and frozen.

### High-priority question

The role-admission investigation asked whether a universal concept such as:

```text
DxModuleBinding
```

could be defined and supported.

Candidate definition:

> A value binding whose scope/storage is non-local to the current function or block and belongs to a module, namespace, type, or persistent/static storage domain.

Do not define it in terms of an LSP `static` modifier.

### Required evidence matrix

For each language where practical, add representative fixture cases:

#### Zig

```text
top-level const
top-level var
local const
local var
parameter
member
```

Record:

```text
TS capture
LSP type
LSP modifiers
effective group
```

#### C

```text
file-scope static variable
file-scope global variable
function local variable
parameter
struct member
```

#### C++23

```text
namespace-scope variable
static data member
function local variable
parameter
instance member
```

#### Rust

```text
static item
const item
local let binding
parameter
field
```

#### Python

```text
module-level binding
local binding
parameter
instance attribute
```

If the language server does not expose a useful distinction, record that fact instead of inventing a mapping.

### M2 final output

The investigated decision space was:

```text
A. approve DxModuleBinding
B. reject it as insufficiently universal
C. defer pending more evidence
```

The final evidence-backed decision was:

```text
C. DxModuleBinding = DEFERRED / FROZEN
```

M3 must not admit the role, reserve palette capacity for it, or reopen the
classification. Reopening requires new evidence and a separately governed M2
regression/decision process.

---

## 6. M3 — Construct the C4 visual system

### M3-A — Freeze the C4 visual contract

Define before implementation:

```text
visual philosophy
visual-weight bands
role-energy relationships
contrast relationships
CVD-aware constraints
C3.1 deprecation behavior
M4 human acceptance criteria
```

M3-A MUST NOT select final HEX values or change runtime code.

The normative result is:

```text
DX-COLOR-003-M3A-C4-VISUAL-CONTRACT.md
```

### M3-B — Implement the independent C4 profile

Implement an independent `visual/c4.lua` without changing the default profile.

M3-B may add C4 palette values and profile-aware visual tests. It must preserve
the 23-role Domain, semantic bindings, provider adapters, authority decisions,
and the governed 225-group topology.

The current fully resolved C3.1 graph digest includes visual role attributes.
M3-B must preserve it as a C3.1 reference and freeze a separate C4 resolved
graph digest. Do not mislabel either resolved digest as profile-independent.

### M3-C — Add explicit opt-in runtime selection

Suggested profile selector:

```lua
local profile_name = "c3_1"
```

or an equivalent small configuration entry.

Avoid environment-variable complexity unless already used by the theme configuration.

Default remains temporarily:

```text
c3_1
```

until human approval. C3.1 remains the compatibility baseline while it is the
runtime default, but it receives no further design investment. It is also
retained for controlled A/B and deterministic rollback.

### Tasks

- implement C4 palette tokens only after M3-A review;
- add C4 visual role definitions in `visual/c4.lua`;
- replace C3-only mathematical gates with profile-aware contracts;
- retain source-state separation;
- retain red/yellow scarcity semantics where still valid;
- retain no-green normal source-role guard;
- run full language matrix.

### Prohibited

Do not modify adapters to make C4 “look right”.

If a token has the wrong semantic role under C4, that is an evidence/adapter bug and must be treated separately.

---

## 7. M4 — Human visual gate

No code changes are required unless feedback demands them.

Use real source files plus stable fixtures.

Record:

```text
PASS
PASS WITH CHANGES
REJECT
```

For every requested change, state whether it is:

```text
semantic classification
authority decision
visual profile
UI chrome
```

Do not change the wrong layer.

---

## 8. M5 — C4 default and C3.1 retirement

Only after M4 PASS.

Only after M4 PASS:

```text
default profile c3_1 -> c4
C3.1 active runtime path -> retired
```

No additional palette changes in the default-switch commit. Preserve historical
C3.1 evidence even if its runtime profile is removed in a separately reviewable
cleanup.

Run complete CI again.

---

## 9. Recommended PR breakdown

### PR A

```text
refactor(theme): extract semantic bindings and provider adapters
```

Scope:

- architecture only;
- zero intended visual change.

### PR B

```text
test(theme): expand semantic evidence for binding topology
```

Scope:

- fixtures;
- manifest;
- runtime evidence;
- optional separate role-admission follow-up.

### PR C

```text
docs(theme): define C4 visual contract
```

Scope:

- M3-A relationships and acceptance criteria only;
- no runtime or final-palette change.

### PR D

```text
feat(theme): add C4 candidate visual profile
```

Scope:

- `visual/c4.lua`;
- C4 palette tokens;
- profile-aware test contracts;
- no runtime selector;
- no default change;
- no adapter changes.

### PR E

```text
feat(theme): add explicit C4 opt-in selector
```

Scope:

- selector only;
- C3.1 remains default;
- prove C3.1 and C4 selection;
- no palette redesign.

### M4 review

Human visual acceptance. No default change occurs here.

### PR F

```text
style(theme): make C4 the default profile
```

Only after M4 human signoff. No palette changes.

### PR G — M5 cleanup, if separately authorized

```text
refactor(theme): retire C3.1 runtime profile
```

Retain historical C3.1 evidence.

---

## 10. Rollback strategy

Every phase must be independently revertible.

M1:

- revert architecture extraction; behavior returns to baseline.

M3:

- switch profile back to `c3_1`.

M5:

- revert default-selector change.

Never delete C3.1 before M4 acceptance. M5 retirement requires explicit review
and must retain the historical evidence record.

---

## 11. Required Codex report after each milestone

Codex must report:

```text
Base SHA
Head SHA
Branch
Changed files
Insertions/deletions

Design decisions implemented
Design decisions intentionally not implemented

Tier-1 result
Fixture validation result
Tier-2 result
Strict LSP result
CI run/result

Observed raw evidence for every new adapter rule
Known limitations
Merge status
```

Do not report “all good” without concrete evidence.
