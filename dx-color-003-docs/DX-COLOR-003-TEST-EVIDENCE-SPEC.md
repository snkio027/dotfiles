# DX-COLOR-003 — Test and Evidence Specification

- **Document ID:** DX-COLOR-003-TEST
- **Status:** Normative Verification Contract

---

## 1. Test philosophy

The system must prove three different things:

```text
1. Domain / graph correctness
2. Runtime semantic authority correctness
3. Human visual quality
```

These are separate gates.

A unit test cannot approve visual comfort.

A screenshot cannot prove LSP protocol behavior.

---

## 2. Existing verification model to preserve

The current baseline already uses:

```text
Tier-1
  isolated unit contract

Tier-2A
  locked production-like Neovim runtime

Tier-2B
  strict LSP/devcontainer runtime
```

The shared `color_manifest.lua` remains the single source of truth for fixture sentinels.

Do not regress to ad-hoc language-specific test scripts.

---

## 3. Tier-1 responsibilities

Tier-1 verifies:

- role closure;
- module composition;
- highlight links;
- palette invariants;
- source/state separation;
- authority group shape;
- no forbidden raw HEX outside designated palette source;
- sentinel locator integrity;
- negative controls.

Tier-1 does not prove a real server emitted a token.

---

## 4. Tier-2 responsibilities

Tier-2 verifies the production runtime.

It must observe:

```text
Tree-sitter captures
LSP semantic tokens
client identity
token modifiers
highlight priority
effective final foreground/style
```

For protocol sentinels, the test must fail closed.

---

## 5. Evidence schema

Existing manifest fields should be preserved and may be normalized.

Recommended semantic shape:

```lua
{
  tag = "zig.fn.keyword",
  token = "fn",
  role = "DxFunctionKeyword",
  desc = "Zig function declaration keyword",

  required_ts_capture = "keyword.function.zig",

  protocol = {
    authority = "treesitter",
    expected_type = "keyword",
    required_modifiers = {},
    forbidden_modifiers = {},
  },
}
```

Optional future fields:

```lua
evidence = {
  semantic_concept = "function-declaration-keyword",
  provider = "zls",
}
```

Do not add fields unless tests consume them.

---

## 6. Evidence levels

Use explicit levels.

### E0 — Visual fixture only

A source token exists and should resolve to a role.

### E1 — Tree-sitter evidence

Requires an exact capture.

### E2 — LSP evidence

Requires:

```text
specific client
specific token type
modifier constraints where needed
```

### E3 — Authority evidence

Requires both evidence sources where applicable plus proof of which one owns the effective foreground.

Provider-specific adapter rules should normally require E2 or E3.

---

## 7. Authority assertions

### Tree-sitter authority case

Test must prove:

```text
raw LSP token exists if expected
LSP foreground is suppressed
required TS capture exists
effective foreground == intended Dx role
```

Examples:

```text
zig.fn.keyword
zig.pub.keyword
zig.u8.builtin
c/cpp builtin types where generic LSP type loses distinction
```

### LSP authority case

Test must prove:

```text
raw LSP token type matches
required modifiers match
client_id matches attached expected server
effective foreground == intended Dx role
```

---

## 8. Client isolation

Never accept a token from an arbitrary attached client.

Protocol evidence must bind to the expected LSP client identity/name.

If multiple compatible names exist, keep the current manifest mechanism for aliases.

---

## 9. Provider adapter test rule

Every new provider-specific adapter mapping must add or reference a sentinel that demonstrates it.

Bad:

```lua
["@lsp.typemod.variable.static.zig"] = ...
```

with no fixture.

Good:

```text
fixture token
+ raw ZLS token/modifier evidence
+ effective role assertion
```

---

## 10. Role-admission test rule

Adding a new `Dx*` role requires:

1. domain description independent of provider vocabulary;
2. role registry update;
3. visual definition in the production visual projection;
4. at least one real fixture binding;
5. closure test update;
6. no collision with unrelated roles;
7. explicit review note explaining why an existing role is insufficient.

---

## 11. M1 architecture-equivalence test

M1 should add a normalized graph comparison.

Snapshot the baseline governed groups or encode an expected map.

Normalize:

```text
link
fg
bg
sp
bold
italic
underline
undercurl
strikethrough
nocombine
```

Ignore irrelevant table ordering.

M1 PASS condition:

> Refactored architecture produces the same governed highlight graph as the baseline C3.1 configuration.

This should catch “refactor accidentally changed color” failures.

---

## 12. Production visual contract

M5 has one executable production visual: C4.4 High-Chroma Night. The runtime
contract must not reconstruct a profile selector or retain a C3.1 rollback
module.

Current structure:

```text
tests/nvim/visual_contracts/
  c4.lua
```

The core unit test freezes the current production graph independently and
reconstructs historical C4.3, C4.0, M2B, and M1 graph digests from explicit
authorized deltas. Historical reconstruction is evidence provenance, not an
executable runtime profile.

---

## 13. Shared visual contracts

Apply to the production visual:

- source/state separation;
- error/warn semantic uniqueness where intentionally reserved;
- green dominance is allowed only for the governed builtin and string axes;
- body readability and critical distinctions must not depend only on hue;
- no critical source/state distinction may rely only on red versus green;
- state success uses sky/cyan rather than green;
- diagnostic Error/Warn have non-color undercurl cues;
- function keyword and ordinary keyword are distinct roles;
- `DxBuiltin` and `DxType` remain semantically distinct.

---

## 14. C4.4 production contracts

The frozen C4.4 evidence record and executable
`tests/nvim/visual_contracts/c4.lua` govern the production visual. The original
M3-A contract remains a historical design baseline; its initial C4.0 contrast
and no-green hypotheses were explicitly superseded by M4 human evidence.

Required invariants:

```text
resolved Normal.bg == #1A1B2A
DxVariable >= 10.0 contrast against resolved Normal.bg

DxComment      within 4.1–4.6
DxDocComment   within 6.0–6.5
DxComment < DxDocComment < DxVariable

DxType         within 7.8–8.4
DxBuiltin      within 9.0–9.6
Type/Builtin   OKLab distance >= 0.17

Builtin and String are green-dominant
No other normal source role is green-dominant

DxOperator >= 10.8
DxOperator must not use state error/warn

DxComment < DxPunctuation < DxVariable
```

The pairing contract is relational rather than mere HEX inequality:

```text
MUST-SEPARATE
  Keyword / FunctionKeyword       >= 0.14 OKLab
  FunctionKeyword / Namespace     >= 0.12 OKLab
  Namespace / Type                >= 0.11 OKLab
  Type / Builtin                  >= 0.17 OKLab
  Variable / Member               >= 0.12 OKLab
  Variable / String               >= 0.14 OKLab
  Callable / Constant             >= 0.04 OKLab
  Callable / Number               >= 0.065 OKLab
  normal source / Error state     >= 0.035 OKLab

SHOULD-SEPARATE
  Builtin / String                >= 0.035 OKLab
  Number / Constant               >= 0.11 OKLab
  Meta / Keyword                  >= 0.10 OKLab
  Type / Lifetime                 >= 0.07 OKLab

INTENTIONAL-NEAR
  Variable / Parameter            0.02–0.10 OKLab
  Comment / Punctuation           0.02–0.06 OKLab
```

Do not call these universal accessibility requirements.

They are C4.4 production-visual design contracts.

---

## 15. Negative controls

Tests should prove gates fail closed.

Keep existing negative-control philosophy.

Keep C4.4 controls for:

```text
bad_primary_body:
  variable made too dim
  -> fail

bad_comment:
  comment made too bright
  -> fail

bad_comment_floor:
  comment made too dim
  -> fail

bad_background:
  production canvas replaced
  -> fail

bad_must_pair / bad_should_pair / bad_intentional_near:
  pairing relationship violated
  -> fail

bad_source_state:
  source role reuses error state
  -> fail

bad_operator_state:
  operator equals warning yellow
  -> fail
```

---

## 16. Injection verification

At least one injected-language smoke test SHOULD eventually verify that generic Tree-sitter fallback works without provider adapters.

This is not required to block M1 if no reliable existing injection fixture exists.

Do not add a fragile injection fixture solely to satisfy symmetry.

---

## 17. Binding-topology evidence matrix

M2 extended the manifest with scope/binding cases.

The goal is evidence, not a predetermined new role.

Record for each case:

```text
language
source token
semantic description
Tree-sitter capture
LSP provider
LSP type
LSP modifiers
current effective role
proposed domain meaning, if any
```

The evidence established that binding topology is real but did not support a
stable cross-language role or independent visual value. The final decision is:

```text
DxModuleBinding = DEFERRED / FROZEN
```

M3 must not reopen this decision. New evidence requires a separately governed
M2 regression/decision process.

---

## 18. Manual visual test protocol

Automated test names should never imply human comfort.

Manual validation requires:

```text
same terminal
same font
same font weight
same viewport
same file
same editor UI settings
only candidate visual values change
```

Capture at least:

```text
Zig
Rust
C++23
Python
C
```

Judge:

```text
airiness
semantic scanability
fatigue
comment suppression
local-vs-member distinction
type-vs-builtin distinction
function declaration rhythm
operator salience
string comfort
overall color density
```

The default acceptance protocol uses both observation windows from the M3-A
contract:

```text
First impression      10 minutes
Sustained editing     30-60 minutes
```

A human owner may replace part of that protocol only through an explicit,
reviewable waiver. The waiver must name every unperformed requirement, record
the actual controlled evidence, identify the decision authority, give exactly
one `PASS` / `PASS WITH CHANGES` / `REJECT` verdict, and state the limits of the
result. CI or screenshots alone cannot imply such a waiver.

---

## 19. CI gate

A PR may claim complete verification only if the current HEAD has passed all required remote jobs.

Local pass and remote CI pass must be reported separately.

Do not reuse a CI result from an earlier HEAD.

---

## 20. Test Definition of Done

The verification system is complete when it can distinguish:

```text
wrong semantic role
wrong authority
wrong provider token assumption
wrong production visual mapping
unexpected retired compatibility surface
wrong UI state
```

without conflating them into one generic “color mismatch”.
