# DX-COLOR-003 M4 — C4.4 High-Chroma Night

<!-- markdownlint-disable MD013 -->

- **Milestone:** M4 / human-directed perceptual rebase
- **Base:** `86d10b4fa938d377840d2b46c49b6da195ff9080`
- **Candidate:** C4.4 High-Chroma Night
- **Default profile:** C3.1, unchanged
- **Semantic / authority / provider delta:** none
- **TokyoNight runtime dependency:** none

## Human decision

A same-source, tiled-window comparison established that TokyoNight Night fits
the user's visual model more closely than C4.3 High-Separation Graphite. Focus,
content, diagnostics, font, and terminal were controlled.

The preferred perceptual topology is:

```text
high chroma
+ explicit hue families
+ high local contrast
+ a dark, slightly cool canvas
+ a limited amount of bright neutral body text
```

C4.3 instead produced a neutral Graphite canvas with pastel foregrounds and a
more uniform luminance distribution. It was readable, but slower to scan. Human
evidence therefore rejects C4.3 as the active candidate.

C4.4 keeps the DX semantic architecture and rebases only the final visual
projection toward the perceptual distribution that won the A/B. It does not
copy TokyoNight highlight ownership and does not load TokyoNight at runtime.

The design objective is:

> **TokyoNight hue separation and chroma confidence without TokyoNight body-white glare.**

## Authorized C4.4 visual projection

The canvas is a dark navy with lower purple bias than Catppuccin Mocha:

```text
Normal.bg = #1A1B2A
```

Only C4 owns this canvas override. Other Catppuccin UI surfaces remain
unchanged; C3.1 remains the compatibility default.

| Role | C4.4 | Contrast against `#1A1B2A` | Visual responsibility |
| --- | --- | ---: | --- |
| `DxVariable` | `#C4CAE0` | 10.43 | softened cool-white body |
| `DxKeyword` | `#BB9AF7` | 7.36 | high-chroma violet grammar |
| `DxFunctionKeyword` | `#7DCFFF` | 9.92 | clear cyan declaration boundary |
| `DxCallable` | `#E6B35C` | 8.89 | amber execution landmark |
| `DxType` | `#2AC3DE` | 8.07 | bright saturated cyan type anchor |
| `DxBuiltin` | `#9ECE6A` | 9.31 | vivid green language/runtime primitive |
| `DxLifetime` | `#67D4C7` | 9.58 | teal lifetime structure |
| `DxMember` | `#F29BC1` | 8.29 | visible soft-pink member identity |
| `DxParameter` | `#C8B2E3` | 8.86 | mauve binding near the body family |
| `DxMeta` | `#D16DDB` | 5.61 | high-chroma magenta metadata |
| `DxNamespace` | `#5EA1FF` | 6.50 | pure-blue navigation structure |
| `DxString` | `#B8D07A` | 10.00 | yellow-green data region |
| `DxNumber` | `#F09A6C` | 7.73 | coral-orange literal |
| `DxConstant` | `#DCC66A` | 9.99 | yellow-gold constant |
| `DxLabel` | `#8E98B8` | 5.94 | quiet blue-slate target |
| `DxOperator` | `#89DDFF` | 11.22 | bright-aqua micro-syntax |
| `DxPunctuation` | `#8991A8` | 5.41 | structural blue-slate |
| `DxComment` | `#7580A3` | 4.35 | readable blue-gray prose |
| `DxDocComment` | `#929BC2` | 6.23 | brighter secondary prose |

State roles remain Catppuccin-owned. Diagnostic severity continues to combine
color with signs and undercurl cues.

## Perceptual axes

The viewport should expose the full semantic color wheel instead of pulling
normal source roles toward one pastel center:

```text
        violet grammar
              |
pure blue ----+---- cyan / aqua
namespace     |     type / function keyword
              |
pink member   |     vivid green builtin / string
              |
       amber / coral / gold
       execution and literals
```

The body is intentionally softer than TokyoNight's `#C0CAF5`; high-frequency
variables use `#C4CAE0`. Brightness is concentrated in semantic landmarks and
micro-syntax rather than spread across every ordinary identifier.

## Pairing contract

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

These distances are regression guardrails, not an automated aesthetic verdict.
Human A/B remains authoritative for scanability, glare, rhythm, and fatigue.

## Graph provenance

```text
C4.0 historical graph
  225 / 311ac3566f816d0fc03ad4ec92c74477d4ac82bf8cc2ab5cd82f95a12688c043

C4.3 rejected candidate graph
  226 / 12d9299d27f50cc96bc056662ce13eed1bb1e46d7fc154f7bd5655216c7a8cc8

C4.4 candidate graph
  226 / 1ac13a349234d5926a250a82c6beb1135fe4483bfe1208f0e24245d4f0022fc8
```

Rolling back exactly the eleven changed Domain foregrounds and `Normal.bg`
must reconstruct the C4.3 graph. Removing `Normal` and restoring the nineteen
C4.0 foreground values must independently reconstruct the C4.0 graph. The M1
and M2 historical oracles remain unchanged.

## Boundaries

```text
Semantic architecture     unchanged
Authority model           unchanged
23-role Domain            unchanged
Bindings / adapters       unchanged
Provider ownership        unchanged
TokyoNight dependency     absent
Plugin/tool versions      unchanged
C3.1 default              unchanged
```

C4.4 is explicit opt-in and remains subject to cross-language M4 human review.
It is not authorization to switch the default profile or retire C3.1.
