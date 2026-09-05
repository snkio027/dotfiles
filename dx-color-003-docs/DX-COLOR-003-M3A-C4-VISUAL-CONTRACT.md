# DX-COLOR-003 — M3-A C4 Visual Contract

- **Document ID:** DX-COLOR-003-M3A
- **Status:** Normative Visual-Design Contract
- **Milestone:** M3-A — C4 Visual System Construction
- **Base:** `c930a0330bfd4a19921985c6c24a33ce1c6f4aee`
- **Host theme:** Catppuccin Mocha
- **Runtime change:** None
- **Final color values:** Not selected in this milestone

---

## 1. Decision

M2 semantic evidence, authority arbitration, and provider ownership are closed
and frozen. M3 changes only the visual projection of the existing DX Domain.

C4 is governed by this design principle:

> **Bright Neutral Canvas + Sparse Semantic Light + Deep Secondary Silence**

The goal is not to maximize brightness or the number of distinct colors. The
goal is to create a larger, more legible difference between high-frequency
reading body, sparse semantic landmarks, secondary structure, and receding
prose.

C3.1 is now:

```text
DEPRECATED / FROZEN
```

It remains the runtime compatibility baseline through M4, receives no further
design investment, and is retained for controlled A/B and deterministic
rollback. It is not an active design target.

---

## 2. Scope

M3-A defines:

1. visual philosophy;
2. visual hierarchy;
3. role-energy relationships;
4. contrast relationships;
5. CVD-aware constraints;
6. C3.1 deprecation behavior;
7. M4 human acceptance criteria.

M3-A does not:

- choose final HEX values;
- add `visual/c4.lua`;
- add or change a runtime profile selector;
- change palette, highlight, binding, adapter, or authority code;
- change any of the 23 DX roles;
- reopen `DxModuleBinding`;
- change Python, Ty, Ruff, or Pyright ownership;
- modify the current 225-group graph;
- update plugins or tools.

The older C4 visual specification contains useful research and candidate color
values. It is input to M3-B and M4, but this document is authoritative for C4
visual relationships.

---

## 3. Frozen semantic foundation

M3 starts from these governed facts:

```text
M1 architecture                    FROZEN
M2 evidence / authority / provider FROZEN

DX Domain roles                    23
Semantic rendering sentinels       42
Current highlight groups           225
Current C3.1 resolved graph SHA    a2db03bf6a138c0784d74277adf6f7ee706a5398336305385ced7d3725c0dedf
Historical M1 graph                221 / 05ff81df9019ace7bee14a494db1a9e39c7d18426f3b78bae1ef3012a068a276

DxModuleBinding                    DEFERRED / FROZEN
Host theme                         Catppuccin Mocha
```

M3 may alter how existing `Dx*` roles look. It may not alter what source
evidence means, which role owns that meaning, or which producer has foreground
authority.

If C4 appears to require an authority or semantic correction, stop M3 and open
a separately governed regression investigation.

---

## 4. Graph terminology

The current `225 / a2db03bf...` oracle hashes the fully resolved highlight
definitions, including the visual attributes of `Dx*` roles. The group topology
is independent of the visual profile; the fully resolved digest is not.

M3-B must therefore distinguish:

```text
DX graph topology
  group names, ownership, links, composition order
  expected to remain stable across C3.1 and C4

C3.1 resolved graph
  topology plus C3.1 visual attributes
  frozen reference: 225 / a2db03bf...

C4 resolved graph
  same governed topology plus C4 visual attributes
  receives its own count and digest in M3-B
```

Do not rename the current resolved digest to a profile-independent
`DX_GRAPH_SHA256`; that would overstate what it proves. A future topology-only
oracle may use a profile-independent name only if it explicitly excludes visual
role attributes and is protected by negative controls.

---

## 5. Visual-energy model

C4 treats perceived salience as a relationship among several factors:

```text
perceived salience
~= luminance contrast x chroma x visual area x occurrence frequency x style
```

This is a design heuristic, not an accessibility formula. Contrast ratio
remains useful, but it cannot alone predict whether a token dominates a real
source viewport.

Consequences:

- high-frequency body may be bright when it is chromatically quiet;
- large-area prose should recede primarily through luminance;
- small-area operators may carry more energy without becoming the reading body;
- sparse type, callable, and control landmarks may be more chromatic;
- state colors are governed separately from normal source semantics.

---

## 6. Four visual-weight bands

Every non-state DX role belongs to one primary C4 band.

### Band A — Reading Body

```text
DxVariable
```

Intent:

- bright neutral canvas for ordinary code reading;
- high legibility without requiring hue recognition;
- high frequency without turning the viewport into a colored field.

### Band B — Semantic Landmarks

```text
DxType
DxCallable
DxFunctionKeyword
DxKeyword
DxOperator
```

Intent:

- reveal type boundaries, callable boundaries, control grammar, and meaningful
  micro-syntax during scanning;
- remain sparse enough that the reading body still dominates sustained reading;
- use clearly separated hue families rather than near-neighbor dusty hues.

`DxOperator` is a small-area exception: it may have high local energy, but it
must not become the first-order landmark across a representative viewport.

### Band C — Secondary Semantic Structure

```text
DxMember
DxParameter
DxBuiltin
DxNamespace
DxConstant
DxNumber
DxString
DxMeta
DxLifetime
```

Intent:

- preserve useful semantic distinctions without competing with the body and
  primary landmarks;
- keep high-frequency member access lightly chromatic rather than dominant;
- keep parameters and builtins visibly subordinate to ordinary body and
  user-defined type landmarks;
- constrain large string regions so they do not flood a viewport with chroma.

### Band D — Structural and Receding Information

Structural low-energy roles:

```text
DxPunctuation
DxLabel
```

Receding prose roles:

```text
DxComment
DxDocComment
```

Intent:

- punctuation remains available without becoming semantic body;
- ordinary comments leave the primary visual competition;
- documentation comments remain more readable than ordinary comments while
  staying below body text.

### State — Orthogonal Feedback

```text
DxError
DxWarn
DxInfo
DxHint
```

State roles do not participate in the source-energy band ordering. They retain
their operational meaning and, where relevant, non-color cues such as diagnostic
undercurls.

---

## 7. Required role relationships

The following are normative C4 relationships. They do not select exact colors.

### Body and binding density

```text
DxVariable is bright and neutral.
DxMember is visually distinct from DxVariable but must not dominate it.
DxParameter is subordinate to DxVariable.
```

In member-heavy code, the first impression must remain the code body, not a
field of member-color accents.

### Type system

```text
DxType is a strong structure landmark.
DxBuiltin remains distinct from DxType and carries less visual energy.
DxLifetime remains secondary to DxType.
```

### Function declaration rhythm

```text
DxKeyword -> general grammar
DxFunctionKeyword -> declaration boundary
DxCallable -> execution landmark
```

The three roles must be distinguishable by both color family and visual energy;
simple RGB inequality is insufficient evidence.

### Data and metadata

```text
DxString, DxNumber, DxConstant, DxMeta
```

remain recognizable secondary accents. None should routinely outrank types,
callables, or control structure across a full viewport.

### Prose and structure

```text
DxComment < DxDocComment < DxVariable
DxComment < DxPunctuation < DxVariable
```

The first chain governs readable prose hierarchy. The second governs ordinary
source scaffolding. It does not require `DxDocComment` and `DxPunctuation` to
have a universal ordering.

---

## 8. Contrast contract

All contrast measurements use the actual resolved `Normal.bg` at runtime.
Catppuccin Mocha Base is a planning reference, not a hard-coded substitute for
the resolved background.

The initial C4 contract is:

```text
contrast(DxVariable) >= 9.0

contrast(DxComment) <= 3.8
contrast(DxDocComment) > contrast(DxComment)

contrast(DxType) >= 7.5
contrast(DxType) > contrast(DxBuiltin)
contrast(DxType) - contrast(DxBuiltin) >= 1.5

contrast(DxComment) < contrast(DxPunctuation)
contrast(DxPunctuation) < contrast(DxVariable)
```

Additional rules:

- `DxOperator` may exceed `DxVariable` contrast because it is small-area
  micro-syntax;
- `DxOperator` must not reuse `DxError` or `DxWarn` visual identity;
- C4 must not inherit the C3.1 global `[4.5, 8.8]` source-role budget;
- comments below 4.5 are an intentional visual-preference decision, not a claim
  of universal WCAG compliance;
- thresholds may change only through an explicit M3-A contract revision backed
  by visual evidence, not because an implementation happens to miss them.

---

## 9. CVD-aware constraints

C4 must satisfy all of the following:

1. Reading body does not depend on hue recognition.
2. Comment recession is primarily a luminance relationship.
3. Type and builtin remain separable under grayscale-like inspection through a
   meaningful luminance gap.
4. No critical semantic or state distinction relies only on red versus green.
5. No normal source role is intentionally green-dominant.
6. Keyword, function keyword, and callable use separated color families and
   different visual energy.
7. Error and warning retain non-color diagnostic cues where applicable.
8. CVD simulation is supporting evidence; it cannot replace human review of
   the actual terminal rendering.

Passing an RGB-distance calculation alone does not establish CVD safety.

---

## 10. C3.1 deprecation contract

C3.1 remains the runtime default through M4 as the compatibility baseline. Its
deprecated/frozen status means it receives no further design investment; it
does not mean the runtime path is already inactive.

While deprecated and frozen, C3.1 permits:

- deterministic rendering for comparison;
- rollback if C4 produces a severe visual regression;
- historical resolved-graph verification.

C3.1 forbids:

- new color tuning;
- new contrast policy;
- new semantic accommodation;
- provider-specific visual fixes;
- feature work;
- using C3.1 preferences to weaken the C4 contract.

It is additionally retained for controlled A/B and deterministic rollback.

M3 and M4 must not delete `visual/c3_1.lua` or its rollback path. After explicit
M4 acceptance, M5 may switch the default to C4 and retire the C3.1 runtime path
in a separately reviewable cleanup. Historical documents and evidence remain.

---

## 11. M3-B and M3-C implementation boundary

M3-B may:

- add an independent `theme/visual/c4.lua`;
- add C4 palette data through a clearly owned visual/palette seam;
- add profile-aware visual contracts;
- freeze a C4 resolved graph count and digest;
- add negative controls for the C4 visual rules.

M3-C may:

- add one explicit, deterministic opt-in selector;
- prove opt-in and opt-out behavior;
- keep C3.1 as the default until M5.

Neither milestone may:

- modify Domain roles;
- modify Tree-sitter or LSP bindings;
- modify provider adapters or authority arbitration;
- alter Python provider ownership;
- add a runtime dependency;
- reinterpret a semantic token to achieve a preferred color.

M3 must not admit `DxModuleBinding`, reserve palette capacity for it, or design
a C4 token around it. Its deferred/frozen decision may be reopened only by new
evidence and a separately governed M2 regression/decision process.

An unknown visual-profile name must fail clearly or use an explicitly documented
safe policy. It must not silently select an unintended profile.

---

## 12. M4 human visual acceptance

Automated contracts may reject an invalid C4 candidate, but they cannot approve
the visual experience.

### Fixed language matrix

Use representative, real source pages for:

```text
C++23
Rust
Zig
Python
C
```

Each page should expose, where the language supports them:

```text
types
variables
members
parameters
functions
keywords
strings
numbers
comments
operators
generic / lifetime / metadata constructs
```

### Controlled A/B

Compare C3.1 and the C4 candidate with these held constant:

- terminal background and opacity;
- font family, size, weight, Grade, and OpenType features;
- viewport dimensions and source location;
- Neovim UI layout;
- LSP and Tree-sitter provider state.

### Required observation windows

```text
First impression      10 minutes
Sustained editing     30-60 minutes
```

### Acceptance questions

Record concrete answers to:

1. Does the first impression reveal code body rather than colors?
2. Can type, callable, and control boundaries be scanned without hunting for
   color?
3. Do ordinary variables form a comfortable reading canvas?
4. Do member-heavy expressions avoid turning the viewport into a chromatic
   field?
5. Are parameters visible without competing with the body?
6. Do ordinary comments clearly recede while documentation remains readable?
7. Are operators useful micro-landmarks without becoming dominant?
8. Do large string and comment regions remain comfortable?
9. Can every critical distinction be explained without saying only “one is red
   and one is green”?
10. Is the profile still comfortable after sustained use?

### Decision values

Each candidate receives exactly one result:

```text
PASS
PASS WITH CHANGES
REJECT
```

For every requested change, record:

```text
observed visual problem
affected role and visual-weight relationship
which contract relationship changes, if any
why the change belongs to the visual layer
```

Do not iterate by unexplained HEX replacement.

---

## 13. Rejection and stop conditions

Reject or revise a C4 candidate if:

- bright neutral variables make the viewport flat or overwhelmingly white;
- members dominate member-heavy code;
- operators become first-order landmarks;
- comments become impractical to read;
- type and builtin collapse in grayscale-like inspection;
- member and type collapse visually;
- the result becomes rainbow-like or candy-like;
- a critical distinction depends only on red/green;
- sustained comfort is worse than C3.1.

Stop M3 rather than editing semantics if:

- a token has the wrong DX role;
- C4 seems to require a provider-specific mapping;
- the 225-group topology changes;
- the 23-role Domain closure changes;
- M2 evidence, authority, or provider ownership regresses.

---

## 14. M3-A completion gate

M3-A is complete when:

- this contract is reviewed and accepted;
- C3.1 is documented as deprecated/frozen;
- all 23 roles are assigned to a visual band or orthogonal state category;
- contrast and CVD constraints are explicit;
- graph terminology distinguishes topology from resolved visual attributes;
- M4 acceptance questions are fixed;
- no runtime, color, semantic, authority, or provider behavior changed.

Only then may M3-B select candidate values and implement `visual/c4.lua`.
