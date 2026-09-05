# DX-COLOR-003 M3-B — C4.0 Candidate Visual Profile

<!-- markdownlint-disable MD013 -->

- **Milestone:** M3-B / visual-only candidate implementation
- **Base:** `6348cc2fd99457f2ecf0cb574c46a07db45d6e75`
- **Host theme:** Catppuccin Mocha
- **Runtime selector:** not included
- **Default profile:** C3.1, unchanged
- **Semantic / authority / provider delta:** none

## Candidate decision

M3-B implements the first executable C4 candidate under the normative M3-A
principle:

```text
Bright Neutral Canvas + Sparse Semantic Light + Deep Secondary Silence
```

The candidate is named `C4.0`. It is independently composable and testable, but
is not reachable through the production theme entry point. M3-C owns the later
opt-in selector; M4 owns human acceptance; M5 owns any default switch.

## Palette ownership

Raw C4 source colors live only in `theme/palette.lua` under:

```text
palette.code_profiles.c4
```

`visual/c4.lua` contains no raw colors. It maps all 23 existing `Dx*` roles to
the C4 palette or the unchanged state palette. The legacy `palette.code`
namespace remains the frozen C3.1 source palette used by the current runtime
default and existing UI/plugin bindings.

## C4.0 source palette

Contrast values use the resolved Catppuccin Mocha Base `#1E1E2E` supplied to
the palette during the contract test.

| Token | C4.0 | Contrast | Visual purpose |
| --- | --- | ---: | --- |
| `variable` | `#CDD6F4` | 11.34 | bright neutral reading body |
| `member` | `#B5BDFC` | 9.10 | subordinate lavender member structure |
| `parameter` | `#A6ADC8` | 7.37 | secondary neutral signature boundary |
| `type` | `#74C7EC` | 8.69 | strong sapphire type landmark |
| `keyword_function` | `#86B7F7` | 7.91 | blue declaration boundary |
| `callable` | `#D8A972` | 7.68 | retained amber execution landmark |
| `keyword` | `#B298CE` | 6.46 | retained violet grammar |
| `builtin` | `#7393B7` | 5.14 | retained quiet primitive type |
| `string` | `#C7B8A6` | 8.46 | warm stone data region |
| `number` | `#E09A7B` | 7.09 | terracotta literal accent |
| `constant` | `#D6A0BA` | 7.50 | orchid constant accent |
| `namespace` | `#79A7DC` | 6.54 | navigation blue |
| `operator` | `#8BDCEB` | 10.57 | high-energy cyan micro-syntax |
| `punctuation` | `#9399B2` | 5.81 | visible structural scaffolding |
| `comment` | `#6C7086` | 3.36 | deep secondary silence |
| `doc` | `#9399B2` | 5.81 | readable secondary prose |
| `lifetime` | `#7DA6C8` | 6.37 | retained C3.1 treatment |
| `meta` | `#C395B9` | 6.50 | retained C3.1 treatment |
| `label` | `#8D91A4` | 5.25 | retained C3.1 treatment |

## Candidate-research adjustments

The older non-normative C4 research table reused three Catppuccin state colors:

```text
Member             Lavender = DxHint
FunctionKeyword    Blue     = DxInfo
Operator           Sky      = state.success
```

M3-A retains source/state separation as a shared profile contract. C4.0 keeps
the intended lavender, blue, and cyan visual families but selects neighboring
independent values:

```text
Member             #B5BDFC
FunctionKeyword    #86B7F7
Operator           #8BDCEB
```

This is a visual-palette decision only. State meanings and their Catppuccin
colors are unchanged.

## Authorized visual delta

C4.0 changes exactly the 13 roles authorized by the C4-A experimental scope:

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

The first candidate intentionally retains these six C3.1 source treatments:

```text
DxCallable
DxKeyword
DxBuiltin
DxLifetime
DxMeta
DxLabel
```

All four state roles remain owned by the unchanged state palette. No Domain
role is added or removed.

## Profile-aware contract

The C4 contract proves:

```text
DxVariable contrast >= 9.0
DxVariable is chromatically quiet

DxMember < DxVariable
DxParameter < DxVariable

DxComment <= 3.8
DxComment < DxDocComment < DxVariable
DxComment < DxPunctuation < DxVariable

DxType >= 7.5
DxType - DxBuiltin >= 1.5

DxKeyword / DxFunctionKeyword / DxCallable
  retain violet / blue / warm family separation

DxOperator retains high local energy
normal source colors do not reuse state colors
normal source colors are not green-dominant
diagnostic Error/Warn retain undercurl cues
```

Four in-memory negative controls prove fail-closed behavior for a dim primary
body, an over-bright comment, collapsed function-keyword rhythm, and an
operator using warning identity.

## Graph governance

The default C3.1 resolved graph remains frozen:

```text
C3.1 count       225
C3.1 SHA-256     a2db03bf6a138c0784d74277adf6f7ee706a5398336305385ced7d3725c0dedf
```

C4.0 receives its own resolved graph oracle:

```text
C4.0 count       225
C4.0 SHA-256     311ac3566f816d0fc03ad4ec92c74477d4ac82bf8cc2ab5cd82f95a12688c043
```

The profile-topology contract requires:

- identical highlight-group names and count;
- identical non-Domain groups, including authority and style-only groups;
- unchanged links on Domain role groups;
- no added or removed group.

Negative controls add a group, change an LSP link, and remove deprecated-style
authority. All must be rejected. The historical M1 `221 / 05ff81df...` oracle
and M2B-B authorized-delta reconstruction remain unchanged.

## Preserved boundaries

```text
DX roles                         23 / unchanged
semantic rendering sentinels     42 / unchanged
M2A evidence                     28/28 + 15/15 / preserved
M2B-A evidence                   7/7 / preserved
M2B-B behavior evidence          13/13 / preserved

semantic bindings                unchanged
provider adapters                unchanged
authority arbitration            unchanged
Python provider ownership        unchanged
plugin / tool versions           unchanged
DxModuleBinding                  DEFERRED / FROZEN
```

## Human acceptance boundary

Automated gates may reject C4.0, but they do not approve reading comfort,
visual rhythm, landmark density, or long-session fatigue. C4.0 remains a
candidate until an explicit selector exists in M3-C and the controlled M4 A/B
matrix records a human decision.
