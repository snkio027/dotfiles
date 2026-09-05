# DX-COLOR-003 M4 — C4.3 High-Separation Graphite

<!-- markdownlint-disable MD013 -->

- **Milestone:** M4 / human-directed visual candidate baseline
- **Base:** `9a7cea1579b6df1e8195be538beb0b1cb6bad901`
- **Candidate:** C4.3 High-Separation Graphite
- **Human verdict:** A/B rejected; superseded by C4.4
- **Default profile:** C3.1, unchanged
- **Semantic / authority / provider delta:** none
- **Host theme:** Catppuccin Mocha

## Human decision

C4.0 and the intermediate C4.1/C4.2 experiments established that luminance
alone did not solve the subdued viewport. Controlled comparisons used the same
real source, tiled windows, and no focus difference. TokyoNight Storm exposed
the useful mechanism: high-frequency semantic families occupied visibly
different color regions, while its near-white body was too bright for sustained
use.

The successful sequence was:

```text
C4.0
  semantic landmarks existed
  middle-energy roles and prose remained visually compressed

C4.1 / C4.2
  foreground lift improved readability
  repeated lift did not create sufficient semantic separation

C4.3 foreground experiments
  green builtin/string and coral/warm axes improved scanning
  cyan / blue / violet separation became stable

background A/B
  identical foregrounds on Mocha #1E1E2E
  versus Neutral Graphite #181A1F
  Graphite preferred by human review
```

The accepted design term is:

> **High-Separation Graphite**

It uses a neutral low-chroma canvas and explicit semantic color families. It
does not pursue maximum brightness or one unique hue per role.

## Authorized visual delta

Only the C4 profile changes. C3.1 remains the compatibility default and keeps
its historical graph and Mocha canvas.

The C4 canvas owns one explicit override:

```text
Normal.bg = #181A1F
```

Other Catppuccin surfaces remain unchanged in this candidate. The experimental
full Graphite surface remap was not admitted into the baseline.

| Role | C4.3 | Contrast against `#181A1F` | Visual responsibility |
| --- | --- | ---: | --- |
| `DxVariable` | `#C9D4F2` | 11.76 | soft cool-white reading body |
| `DxKeyword` | `#C08CFF` | 6.99 | violet grammar |
| `DxFunctionKeyword` | `#9BCBFF` | 10.26 | light-blue declaration boundary |
| `DxCallable` | `#E6B35C` | 9.09 | amber execution landmark |
| `DxType` | `#79D2F2` | 10.21 | cyan type anchor |
| `DxBuiltin` | `#82D887` | 10.05 | clean-green language/runtime primitive |
| `DxLifetime` | `#67D4C7` | 9.80 | teal lifetime structure |
| `DxMember` | `#F29BC1` | 8.48 | soft-pink member identity |
| `DxParameter` | `#D7B3E8` | 9.54 | muted-mauve binding |
| `DxMeta` | `#D98FD6` | 7.34 | magenta metadata |
| `DxNamespace` | `#5C96FF` | 6.02 | pure-blue navigation structure |
| `DxString` | `#B8D07A` | 10.23 | yellow-green data region |
| `DxNumber` | `#F09A6C` | 7.91 | coral-orange literal |
| `DxConstant` | `#DCC66A` | 10.22 | yellow-gold constant |
| `DxLabel` | `#9AA3BA` | 6.90 | quiet structural target |
| `DxOperator` | `#89DDFF` | 11.48 | bright-aqua micro-syntax |
| `DxPunctuation` | `#8991A8` | 5.54 | structural slate |
| `DxComment` | `#7D8496` | 4.65 | readable recessed prose |
| `DxDocComment` | `#969EB4` | 6.50 | brighter secondary prose |

State roles remain owned by the Catppuccin state palette. No C4 source role may
reuse a state color exactly.

## Semantic color axes

The high-frequency system must read as:

```text
neutral       Variable
violet        Keyword
light blue    FunctionKeyword
pure blue     Namespace
cyan          Type
green         Builtin
pink          Member
amber         Callable
yellow-green  String
coral         Number
gold          Constant
gray-blue     Comment
```

The cold progression is intentional:

```text
cyan Type
  -> light-blue FunctionKeyword
  -> pure-blue Namespace
  -> violet Keyword
```

The first dense C++ review admitted only three pairing refinements:

```text
Keyword / FunctionKeyword  stronger violet / light-blue separation
Type / Builtin             cyan / cleaner-green separation
Namespace / Type           deeper pure-blue / cyan separation
```

Callable, Number, and Constant remain frozen; the warm family was not changed
without a concrete collision.

## Pairing contract

Color expresses semantic families, not a requirement that all 23 roles occupy
maximally distant hues. Pairings are governed in three classes.

```text
MUST-SEPARATE
  Keyword / FunctionKeyword
  FunctionKeyword / Namespace
  Namespace / Type
  Type / Builtin
  Variable / Member
  Variable / String
  Callable / Constant
  Callable / Number
  normal source / Error state

SHOULD-SEPARATE
  Builtin / String
  Number / Constant
  Meta / Keyword
  Type / Lifetime

INTENTIONAL-NEAR
  Variable / Parameter
  Comment / Punctuation
```

The executable contract uses OKLab distance as an auxiliary fail-closed
guardrail with pair-specific bounds. It does not claim that a single numerical
threshold proves visual quality. Human A/B remains authoritative for comfort,
rhythm, density, and fatigue.

## Green and CVD-aware boundary

M4 human evidence supersedes the earlier research hypothesis that no normal
source role should be green-dominant. C4.3 admits green dominance only for:

```text
DxBuiltin
DxString
```

This does not change the stronger normative boundary: critical meaning must not
depend only on red-versus-green discrimination. State success remains
Catppuccin Sky; error remains Catppuccin Red; diagnostics preserve non-color
undercurl cues. C4.3 is CVD-aware, not certified color-blind-safe.

## Graph provenance

The C4.3 resolved graph is frozen separately from C4.0:

```text
C4.0 historical graph
  225 / 311ac3566f816d0fc03ad4ec92c74477d4ac82bf8cc2ab5cd82f95a12688c043

C4.3 candidate graph
  226 / 12d9299d27f50cc96bc056662ce13eed1bb1e46d7fc154f7bd5655216c7a8cc8
```

The only authorized group addition is:

```text
Normal = { bg = "#181A1F" }
```

Removing that group and replacing exactly the 19 C4.3 Domain foregrounds with
their frozen C4.0 values must reconstruct the historical C4.0 count and digest.
Any other group, link, style-authority, binding, adapter, or provider delta
fails closed.

## M4 adjustment discipline

The following axes are frozen unless a concrete cross-language collision is
observed:

```text
Background
Keyword
FunctionKeyword
Namespace
Type
Variable
Member
Builtin
Callable
Operator
```

Validation continues across C++ type/member-heavy, Rust generic/lifetime-heavy,
Zig builtin-heavy, Python call/decorator-heavy, and literal-heavy pages. Every
future visual change must identify the colliding roles, pairing class, changed
perceptual dimension, and regressions checked.

C4.3 was rejected in a same-source, tiled-window A/B against TokyoNight Night.
Its neutral Graphite canvas and pastel foreground distribution reduced scanning
speed for the user. The graph is retained as a deterministic historical oracle;
it is no longer the active M4 candidate and does not authorize a default switch.
