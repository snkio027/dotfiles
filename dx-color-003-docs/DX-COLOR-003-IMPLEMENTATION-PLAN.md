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
M2 Evidence Expansion
      ↓
M3 C4 Opt-In Profile
      ↓
M4 Human Visual Gate
      ↓
M5 Default Switch
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
  "+luafile tests/nvim/run_contract.lua" \
  "tests/nvim/color_contract.lua"
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

## 5. M2 — Evidence expansion

### M2 objective

Collect semantic evidence needed for future role decisions, especially binding topology.

This milestone is primarily research/test work.

### High-priority question

Can a universal domain concept such as:

```text
DxModuleBinding
```

be defined and supported?

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

### M2 outputs

One of:

```text
A. approve DxModuleBinding
B. reject it as insufficiently universal
C. defer pending more evidence
```

If approved, add the role in a dedicated role-admission commit with tests.

Do not mix role admission with C4 color changes.

---

## 6. M3 — Add C4 as opt-in

### M3 objective

Implement `visual/c4_airy.lua` without changing the default profile.

Suggested profile selector:

```lua
local profile_name = "c3_1"
```

or an equivalent small configuration entry.

Avoid environment-variable complexity unless already used by the theme configuration.

Default remains:

```text
c3_1
```

until human approval.

### Tasks

- add C4 palette tokens;
- add C4 visual role definitions;
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

## 8. M5 — Default profile switch

Only after M4 PASS.

Tiny scope:

```text
default profile c3_1 -> c4_airy
```

No additional palette changes in the same commit.

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
feat(theme): add opt-in C4 airy visual profile
```

Scope:

- visual profile;
- profile-aware test contracts;
- no adapter changes.

### PR D

```text
style(theme): make C4 airy the default profile
```

Only after human signoff.

---

## 10. Rollback strategy

Every phase must be independently revertible.

M1:

- revert architecture extraction; behavior returns to baseline.

M3:

- switch profile back to `c3_1`.

M5:

- revert default-selector change.

Never delete C3.1 until C4 has been used successfully for an extended period and a separate cleanup is explicitly authorized.

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
