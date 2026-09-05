# DX-COLOR-003 — C4 Airy Visual Profile

- **Document ID:** DX-COLOR-003-C4
- **Status:** Candidate Visual Specification
- **Host theme:** Catppuccin Mocha
- **Reference study:** TokyoNight Night visual-energy distribution
- **Important:** TokyoNight is a research reference, not a dependency.

---

## 1. Why C4 exists

Runtime A/B observation showed that stock TokyoNight Night felt substantially less oppressive than the current C3.1 design even though TokyoNight Night uses a very dark background.

The key conclusion is:

> The primary problem is not simply background darkness.

The likely issue is **visual-energy distribution**.

C3/C3.1 places many roles in a relatively narrow, muted middle contrast band.

TokyoNight demonstrates a different strategy:

```text
very dim secondary prose
bright neutral body
high-energy small syntax
strongly separated semantic accents
```

C4 adopts that strategy while retaining Catppuccin and DX semantics.

---

## 2. Visual principles

### VP-001 — Bright Neutral Body

High-frequency ordinary local identifiers should not all carry a bespoke muted hue.

Default local body:

```text
DxVariable -> bright neutral foreground
```

Rationale:

- local variables occupy large visual area;
- neutral foreground reduces semantic rainbow density;
- high brightness creates air and readability.

---

### VP-002 — High-Separation Landmarks

Prefer clearly separated hue families over multiple near-neighbor dusty hues.

Preferred principal axes:

```text
neutral blue-white
violet
sky / cyan
amber / orange
pink
warm stone
```

Avoid relying on:

```text
purple vs pink-purple
red vs green
multiple nearly identical blue-purple shades
```

---

### VP-003 — Wide Dynamic Range

Do not force all normal source roles into one contrast interval.

C4 intentionally permits:

```text
very dim comment
very bright local body
very bright micro-syntax
```

Visual hierarchy cannot be represented by contrast ratio alone.

---

### VP-004 — Visual weight depends on area

Use the heuristic:

```text
perceived salience
≈ contrast × chroma × visual area × frequency
```

This is a design heuristic, not a mathematical accessibility metric.

Consequences:

```text
Comment:
  large area
  -> should be dim

Variable:
  large area
  -> may be bright but preferably neutral

Operator:
  very small area
  -> may be highly luminous/chromatic without dominating the screen

Callable:
  medium area + high semantic value
  -> distinct warm landmark
```

---

### VP-005 — No green-dependent source semantics

Normal source roles must not require red/green discrimination.

Do not copy TokyoNight's green String/Member choices.

State success remains cyan/sky rather than green.

---

### VP-006 — Color encodes meaning; visual weight encodes importance

Two independent questions:

```text
What semantic family is this?
-> hue / color family

How much should I notice it?
-> luminance / chroma / area / style
```

---

## 3. C4-A candidate profile

Background baseline for contrast calculations:

```text
Catppuccin Mocha Base = #1E1E2E
```

If the real runtime background changes, all numerical contrast gates MUST be recalculated against the actual resolved `Normal.bg`.

The following values are candidates for the first A/B profile.

| Role | Candidate | Approx. contrast | Intent |
| --- | --- | ---: | --- |
| `DxVariable` | `#CDD6F4` Catppuccin Text | 11.34 | bright neutral body |
| `DxMember` | `#B4BEFE` Lavender | 9.17 | structural object distinction |
| `DxParameter` | `#A6ADC8` Subtext0 | 7.37 | signature boundary, secondary neutral |
| `DxType` | `#74C7EC` Sapphire | 8.69 | strong structure anchor |
| `DxFunctionKeyword` | `#89B4FA` Blue | 7.79 | clearly separated from violet keyword |
| `DxCallable` | `#D8A972` | 7.68 | retain proven amber behavior anchor |
| `DxKeyword` | `#B298CE` | 6.46 | retain violet grammar |
| `DxBuiltin` | `#7393B7` | 5.14 | quiet primitive/builtin |
| `DxString` | `#C7B8A6` | 8.46 | brighter warm stone, no green |
| `DxNumber` | `#E09A7B` | 7.09 | small terracotta accent |
| `DxConstant` | `#D6A0BA` | 7.50 | pink/orchid accent |
| `DxNamespace` | `#79A7DC` | 6.54 | navigation blue |
| `DxOperator` | `#89DCEB` Catppuccin Sky | 10.54 | high-energy micro-syntax |
| `DxPunctuation` | `#9399B2` Overlay2 | 5.81 | visible scaffolding |
| `DxComment` | `#6C7086` Overlay0 | 3.36 | genuine visual silence |
| `DxDocComment` | `#9399B2` Overlay2 | 5.81 | readable secondary prose |
| `DxLifetime` | keep C3.1 initially | 6.37 | no change in C4-A |
| `DxMeta` | keep C3.1 initially | 6.50 | no change in C4-A |
| `DxLabel` | keep C3.1 initially | 5.25 | no change in C4-A |

C4-A intentionally changes only the high-information roles required to test the new visual-weight model.

---

## 4. C4-A exact experimental scope

For the first visual experiment, Codex SHOULD change only:

```text
DxVariable
DxMember
DxParameter
DxType
DxFunctionKeyword
DxString
DxNumber
DxConstant
DxNamespace
DxOperator
DxPunctuation
DxComment
DxDocComment
```

`DxCallable` and `DxKeyword` remain unchanged to preserve two known landmarks.

`DxBuiltin`, `DxLifetime`, `DxMeta`, and `DxLabel` remain unchanged initially.

Do not add module/static binding color in the same experiment.

---

## 5. Object/binding topology

Long-term desired model:

```text
local binding        -> bright neutral
parameter            -> secondary distinct neutral
member/property      -> lavender / structural color
module/non-local     -> reserved warm/orange candidate
```

The module/non-local distinction is not approved until the semantic-domain evidence gate passes.

Reserve an orange visual token for a future `DxModuleBinding` candidate, but do not map it speculatively.

---

## 6. Function declaration rhythm

The approved semantic distinction remains:

```text
pub / general modifier  -> DxKeyword
fn / def                -> DxFunctionKeyword
function name           -> DxCallable
```

C4 visual intent:

```text
Violet -> Blue -> Amber
```

This is intentionally more perceptually separated than purple -> pink-purple -> amber.

---

## 7. Source vs state palette

Source colors must not equal high-priority state accents where that would create ambiguity.

Retain:

```text
DxError  -> state error
DxWarn   -> state warn
DxInfo   -> state info
DxHint   -> state hint

state.success -> Catppuccin Sky
```

Yellow scarcity and red scarcity remain valid concepts, but C4 tests should verify semantic purpose rather than forbid every visually related warm tone.

---

## 8. UI interaction grammar

Keep the UI reductions already validated:

```text
current line location -> gutter / CursorLineNr
selection             -> background enclosure
diagnostic             -> undercurl
reference              -> local relation cue
semantic meaning       -> foreground
inlay hint             -> quiet auxiliary text
```

Do not reintroduce:

- full-width current-line bands;
- inlay-hint badge backgrounds.

`LspReference*` should be evaluated separately from C4 source colors.

Recommended future experiment:

```text
LspReferenceText/Read/Write
background rectangle
-> underline / underdotted or another local non-enclosure cue
```

This is not part of C4-A.

---

## 9. Test-contract migration

The current C3 tests encode assumptions that C4 intentionally rejects.

The following old assumptions MUST NOT survive unchanged:

```text
all code roles must be within [4.5, 8.8]
comment must be >= 4.5
operator must not exceed semantic body
strict scaffolding ceiling
```

These were useful for C3 but would make C4 impossible.

C4 replaces them with role-class budgets.

Suggested C4 contracts:

### C4-P1 — Primary Body Floor

```text
DxVariable contrast >= 9.0
```

### C4-P2 — Secondary Prose Ceiling

```text
DxComment contrast <= 3.8
DxDocComment contrast > DxComment
```

C4 deliberately treats comments as de-emphasized secondary prose. This is a visual preference contract, not an accessibility claim.

### C4-P3 — Structural Separation

```text
DxType contrast >= 7.5
DxBuiltin contrast < DxType
type/builtin contrast gap >= 1.5
```

### C4-P4 — Function Declaration Separation

The resolved colors of:

```text
DxKeyword
DxFunctionKeyword
DxCallable
```

must be pairwise different.

Do not claim universal perceptual/CVD safety from RGB distance alone.

Runtime fixture proof remains required.

### C4-P5 — Micro-Syntax Allowance

`DxOperator` may exceed primary body contrast.

It MUST NOT reuse error/warn state colors.

### C4-P6 — Comment Silence

```text
DxComment < DxPunctuation < DxVariable
```

### C4-P7 — No Green-Dominant Normal Source Role

Retain the existing heuristic guard unless a better documented metric replaces it.

### C4-P8 — State Non-Color Redundancy

Retain diagnostic undercurl requirements.

---

## 10. Human visual acceptance protocol

Automated tests cannot approve C4.

Use identical fixtures and viewport where possible.

Minimum manual matrix:

```text
Zig
Rust
C++23
Python
```

Observe:

- 10-minute first impression;
- 30-60 minute sustained editing;
- function declaration scanning;
- local-variable readability;
- type vs builtin recognition;
- member vs local recognition;
- comment suppression;
- operator brightness;
- string comfort;
- green aversion;
- red/green ambiguity;
- overall “oppressive vs airy” perception.

A/B:

```text
C3.1
vs
C4-A
```

Do not compare against a different font, terminal background, or font weight at the same time.

---

## 11. Rejection criteria

Reject or revise C4-A if any of the following occurs:

- bright neutral variables make the screen look mostly white and visually flat;
- operators become the dominant first-order landmark;
- comments become unreadable in actual use;
- Type and FunctionKeyword become indistinguishable;
- Member and Type collapse visually;
- the palette becomes candy/rainbow-like;
- a normal source role becomes green-dominant;
- visual comfort degrades after sustained use.

---

## 12. C4 Definition of Done

C4 may become default only after:

- architecture extraction is already merged;
- C4 exists as an independent visual profile;
- all semantic sentinels still pass;
- C4-specific contracts pass;
- no authority mapping was changed merely to achieve a desired color;
- human A/B acceptance is explicitly recorded;
- default profile switch is a separate, tiny commit/PR.

---

## 13. TokyoNight lessons to copy — and not copy

Copy the **design mechanics**:

```text
wide visual dynamic range
bright neutral high-frequency body
high-separation semantic hue families
very dim secondary prose
permission for small-area syntax to be bright
provider-specific semantic modifiers only when meaningful
```

Do not copy:

```text
TokyoNight background
TokyoNight plugin dependency
green String
green/teal Member as a required semantic axis
static -> Constant as an internal semantic identity
the full TokyoNight Tree-sitter/LSP mapping table
```

The target remains a Catppuccin-hosted DX visual language.
