# DX-COLOR-003 — Semantic Highlighting Architecture

- **Document ID:** DX-COLOR-003-ARCH
- **Status:** Normative Development Specification
- **Baseline:** `19f0570ee33025832ff1d1d49269d303677d9c0f`

---

## 1. Problem statement

The current DX-COLOR-002 implementation successfully established:

- a 23-role semantic model;
- Tree-sitter and LSP mappings;
- language-specific Semantic Authority decisions;
- `LspForegroundPassthrough`;
- Tier-1 / Tier-2 runtime verification.

The remaining architectural debt is that one `mappings.lua` currently contains several different responsibilities:

```text
Tree-sitter base bindings
LSP base bindings
ZLS adaptations
rust-analyzer adaptations
clangd adaptations
authority suppression
editor UI
diagnostics
completion
git/diff integration
```

This makes provider dialects and universal semantics too easy to mix.

DX-COLOR-003 extracts a stable internal domain and treats Tree-sitter grammars and language servers as external evidence producers.

---

## 2. Architectural model

The system is best understood as:

> **Anti-Corruption Adapters + Semantic Authority Arbitration + Visual Projection**

It is not merely a colorscheme.

```text
┌────────────────────────────────────────────────────────────┐
│                    External Evidence                       │
│                                                            │
│ Tree-sitter captures          LSP semantic tokens          │
│ injected captures             LSP modifiers                │
│                               server extensions             │
└──────────────────┬───────────────────┬─────────────────────┘
                   │                   │
                   ▼                   ▼
┌────────────────────────────────────────────────────────────┐
│                 Binding / Adapter Layer                    │
│                                                            │
│ generic vocabulary       grammar/provider dialect          │
└───────────────────────────┬────────────────────────────────┘
                            ▼
┌────────────────────────────────────────────────────────────┐
│                Semantic Authority Policy                   │
│                                                            │
│ foreground authority     style authority                   │
│ provider taxonomy loss   passthrough decisions             │
└───────────────────────────┬────────────────────────────────┘
                            ▼
┌────────────────────────────────────────────────────────────┐
│                    DX Semantic Domain                      │
│                                                            │
│ DxCallable DxType DxVariable DxMember ...                 │
└───────────────────────────┬────────────────────────────────┘
                            ▼
┌────────────────────────────────────────────────────────────┐
│                     Visual Profile                         │
│                                                            │
│ hue / luminance / visual weight / text style              │
└───────────────────────────┬────────────────────────────────┘
                            ▼
┌────────────────────────────────────────────────────────────┐
│                 Neovim Highlight Link Graph                │
└────────────────────────────────────────────────────────────┘
```

---

## 3. Actors and responsibilities

### 3.1 Tree-sitter

Tree-sitter is a **syntactic evidence producer**.

It is strong at:

- local grammar structure;
- distinguishing captures such as:
  - `@keyword.modifier`
  - `@keyword.function`
  - `@type.builtin`
  - `@variable.parameter`;
- injection parsing;
- syntax-level distinctions that LSP may collapse.

It is not responsible for:

- choosing DX roles directly;
- deciding final colors;
- cross-file symbol semantics;
- resolving server-specific semantic meaning.

Mental model:

> Tree-sitter tells us what the source structurally looks like.

---

### 3.2 Language servers

Examples:

```text
C/C++   -> clangd
Zig     -> ZLS
Rust    -> rust-analyzer
Python  -> Pyright
```

Language servers are **semantic evidence producers**.

For highlighting, the relevant evidence is primarily:

```text
semantic token type
semantic token modifiers
filetype
attached client/provider
```

A language server never chooses the DX color.

Mental model:

> A language server tells us what a symbol means according to its semantic model.

---

### 3.3 Neovim

Neovim is:

- the LSP client;
- the Tree-sitter host;
- the renderer;
- the producer of highlight namespaces such as:
  - `@lsp.type.*`
  - `@lsp.mod.*`
  - `@lsp.typemod.*`.

Neovim is not the semantic-domain owner.

Use the term **Highlight Link Graph**, not “highlight inheritance tree”.

---

### 3.4 DX adapters

Adapters translate external vocabulary into internal meaning.

Examples:

```text
ZLS keyword on `fn`
  external: keyword
  internal evidence: too coarse
  authority: Tree-sitter
  result: DxFunctionKeyword

clangd generic `type` on `int`
  external: type
  internal evidence: too coarse for builtin-vs-user-type
  authority: Tree-sitter
  result: DxBuiltin
```

Adapter rules MUST be evidence-based.

Adapters MUST NOT contain raw HEX values.

---

### 3.5 Semantic Authority

Semantic Authority answers:

> Which producer is allowed to determine a visual attribute for this evidence family?

Authority is attribute-specific.

Minimum model:

```text
foreground authority
style authority
background authority
```

Current DX primarily governs foreground.

Example:

```text
Tree-sitter:
  @type.builtin.zig
  fg = DxBuiltin

LSP:
  generic type.zig
  foreground authority = suppressed

LSP deprecated modifier:
  style authority = allowed
  strikethrough = true

Final:
  DxBuiltin foreground + strikethrough
```

`LspForegroundPassthrough` remains a first-class mechanism.

It must:

- have no foreground;
- have no dotted parent;
- not accidentally re-enter Neovim dotted-group fallback.

---

## 4. Core invariants

The following are normative.

### INV-001 — External vocabulary does not define the domain

Bad:

```text
ZLS says "static"
-> therefore role is DxStaticVariable
```

Good:

```text
ZLS emits variable + static
-> adapter determines language meaning
-> domain role is selected only if the role can be defined without LSP terminology
```

---

### INV-002 — Same meaning, same visual meaning

If two languages produce the same internal semantic role:

```text
Rust local variable
Zig local variable
C++ local variable
Python local variable
```

they MUST share `DxVariable`.

Language-specific colors are forbidden unless the internal semantic meaning is actually different.

---

### INV-003 — Syntax binding is language/provider-specific

Universal:

```text
DxCallable
DxVariable
DxMember
```

Specific:

```text
which Tree-sitter capture maps to the role
which LSP token maps to the role
which producer has authority
```

---

### INV-004 — Authority follows preserved distinction

Do not encode:

```text
Tree-sitter always wins
```

or:

```text
LSP always wins
```

Authority is evidence-family specific.

Examples already proven by the baseline:

```text
Zig generic type          -> Tree-sitter foreground authority
Zig generic keyword       -> Tree-sitter foreground authority
Zig struct/enum evidence  -> LSP can retain authority
Rust rich semantic types  -> LSP can retain authority
C/C++ generic type family -> Tree-sitter when builtin distinction is lost
```

---

### INV-005 — No evidence, no special case

A provider-specific mapping may only be added when:

1. a real fixture exists;
2. raw Tree-sitter capture is observed;
3. raw LSP token/modifiers are observed where applicable;
4. effective final highlight is observable;
5. the intended role is semantically defined.

Speculative typemod matrices are prohibited.

---

### INV-006 — Domain roles are provider-independent

A role name must be explainable without mentioning:

- clangd;
- ZLS;
- rust-analyzer;
- Pyright;
- LSP token names;
- Tree-sitter capture names.

Role-admission question:

> “Can this role be described purely as a programming-language semantic concept?”

If no, do not admit it.

---

### INV-007 — Color and semantic authority are separate

Adapters never choose colors.

Visual profiles never interpret LSP semantics.

---

## 5. Target module structure

The target is intentionally modular but not framework-heavy.

```text
home/dot_config/nvim/lua/theme/
├── init.lua
├── compose.lua
├── domain.lua
├── palette.lua
├── authority.lua
│
├── visual/
│   ├── c3_1.lua
│   └── c4_airy.lua
│
├── bindings/
│   ├── treesitter.lua
│   ├── lsp.lua
│   ├── ui.lua
│   └── plugins.lua
│
└── adapters/
    ├── zls.lua
    ├── clangd.lua
    ├── rust_analyzer.lua
    └── pyright.lua
```

Do **not** create one theme per language.

Do **not** introduce per-language palettes.

---

## 6. Module contracts

### 6.1 `domain.lua`

Purpose:

- canonical registry of DX semantic roles;
- semantic descriptions;
- role family classification;
- closure source of truth.

It MUST NOT:

- contain Tree-sitter group names;
- contain LSP group names;
- contain colors;
- require Catppuccin;
- require plugin modules.

Suggested contract:

```lua
local M = {}

M.roles = {
  DxKeyword = {
    family = "grammar",
    description = "General grammar or control keyword",
  },
  DxFunctionKeyword = {
    family = "grammar",
    description = "Keyword that introduces a function declaration",
  },
  -- ...
}

return M
```

Tests should derive the role closure from this registry rather than duplicate a hard-coded count where practical.

---

### 6.2 `palette.lua`

Purpose:

- normalize host-theme colors;
- hold custom raw source HEX values where named host colors are insufficient;
- expose state/UI colors.

Raw source HEX MUST live only here or in a single explicitly designated visual-palette source.

No external binding knowledge is allowed.

---

### 6.3 `visual/c3_1.lua`

Purpose:

- preserve the exact current C3.1 role rendering during architecture extraction.

M1 requirement:

> The C3.1 visual output must remain behaviorally equivalent to the baseline.

---

### 6.4 `visual/c4_airy.lua`

Purpose:

- opt-in C4 visual projection;
- maps `Dx*` roles to visual attributes.

It does not know:

- Tree-sitter capture names;
- LSP token names;
- provider names.

Example shape:

```lua
function M.roles(p)
  return {
    DxVariable = { fg = p.ui.text },
    DxType = { fg = p.code.c4_type },
    -- ...
  }
end
```

C4 is not default until human visual acceptance.

---

### 6.5 `bindings/treesitter.lua`

Purpose:

- generic Tree-sitter vocabulary -> DX roles.

Examples:

```text
@function            -> DxCallable
@type                -> DxType
@variable            -> DxVariable
@variable.parameter  -> DxParameter
@property            -> DxMember
```

This is the fallback that also serves injected languages.

It MUST remain provider-independent.

---

### 6.6 `bindings/lsp.lua`

Purpose:

- generic standard LSP vocabulary -> DX roles.

Examples:

```text
@lsp.type.function      -> DxCallable
@lsp.type.method        -> DxCallable
@lsp.type.class         -> DxType
@lsp.type.parameter     -> DxParameter
@lsp.type.property      -> DxMember
```

Only distinctions that are safe at the generic LSP level belong here.

---

### 6.7 `adapters/zls.lua`

Purpose:

- ZLS/Zig-specific taxonomy translation and authority rules.

Initial rules must be migrated from existing proven behavior, including:

```text
@lsp.type.type.zig
  -> foreground passthrough

@lsp.type.keyword.zig
  -> foreground passthrough

ZLS builtin / keywordLiteral / errorTag / escapeSequence
  -> existing proven DX roles
```

No new ZLS semantics may be added without fixture evidence.

Important limitation:

Neovim highlight group names contain token/modifier/filetype, not necessarily provider identity. The adapter name represents the evidence provenance under the current “one primary semantic-token server per filetype” operating assumption.

If simultaneous competing semantic-token providers are introduced in the future, static highlight links may be insufficient. That is outside DX-COLOR-003 scope.

---

### 6.8 `adapters/clangd.lua`

Purpose:

- clangd extensions;
- C/C++ taxonomy-loss handling.

Existing behavior to preserve:

```text
@lsp.type.type.c
@lsp.type.type.cpp
  -> foreground passthrough

concept
  -> DxType
```

Do not globally suppress all clangd semantic tokens.

---

### 6.9 `adapters/rust_analyzer.lua`

Purpose:

- rust-analyzer extensions;
- Rust-specific high-value distinctions.

Existing behavior to preserve includes:

```text
typeAlias / union / selfTypeKeyword -> DxType
attribute namespace exception       -> DxMeta
```

Rust lifetime Tree-sitter extension remains source evidence and must stay independently verified.

---

### 6.10 `adapters/pyright.lua`

Purpose:

- only Pyright-specific behavior actually observed in fixtures.

Do not invent semantic-token rules for capabilities Pyright does not expose in the current runtime.

---

### 6.11 `authority.lua`

Purpose:

- define reusable authority primitives;
- define the root foreground passthrough group;
- avoid duplicating magic group construction.

Suggested API:

```lua
M.foreground_passthrough = "LspForegroundPassthrough"

function M.base_groups()
  return {
    [M.foreground_passthrough] = {},
  }
end

function M.suppress_foreground()
  return { link = M.foreground_passthrough }
end
```

Keep it simple. Do not build a runtime arbitration engine.

---

### 6.12 `bindings/ui.lua` and `bindings/plugins.lua`

These isolate non-source concerns from semantic source mappings.

`ui.lua` owns:

```text
CursorLine
CursorLineNr
Visual
Search
Float
Pmenu
Diagnostics
Git/Diff UI if treated as editor state
```

`plugins.lua` owns plugin highlight integration such as Blink/Snacks where appropriate.

Source semantic adapters must not contain UI chrome.

---

### 6.13 `compose.lua`

Purpose:

- deterministic composition order.

Recommended order:

```text
authority base groups
visual role definitions
generic Tree-sitter bindings
generic LSP bindings
provider adapters
UI bindings
plugin bindings
```

Later layers may override earlier groups only intentionally.

The composition order must be documented and tested.

---

### 6.14 `init.lua`

Assembly only.

Target responsibility:

```text
resolve host palette
select visual profile
compose highlight graph
return final table
```

No provider-specific mappings belong here.

---

## 7. Current domain role closure

The current baseline has 23 roles.

### Grammar

```text
DxKeyword
DxFunctionKeyword
```

### Execution

```text
DxCallable
```

### Type system

```text
DxType
DxBuiltin
DxLifetime
```

### Object / bindings

```text
DxVariable
DxMember
DxParameter
```

### Meta / organization

```text
DxMeta
DxNamespace
```

### Data

```text
DxString
DxNumber
DxConstant
```

### Control / syntax

```text
DxLabel
DxOperator
DxPunctuation
```

### Prose

```text
DxComment
DxDocComment
```

### State

```text
DxError
DxWarn
DxInfo
DxHint
```

M1 MUST preserve this closure exactly.

---

## 8. Candidate role admission: module/non-local binding

TokyoNight/ZLS evidence shows that `variable + static` can carry useful scope/storage information.

DX-COLOR-003 does **not** automatically approve `DxStaticVariable`.

The candidate semantic concept is:

> A value binding whose program scope/storage is non-local to the current function/block and belongs to a module, namespace, type, or persistent/static storage domain.

Working candidate name:

```text
DxModuleBinding
```

This role is **not part of M1**.

Before admission, M2 must collect evidence for representative cases in:

```text
Zig
C
C++
Rust
Python where provider evidence exists
```

The role may be introduced even if only one adapter initially binds to it, but its semantic definition must remain language/provider independent.

Never define the role as:

> “a variable with the LSP `static` modifier”.

---

## 9. Injection handling

Injected languages frequently have Tree-sitter evidence without LSP semantic evidence.

Therefore:

```text
generic Tree-sitter bindings
```

must remain complete enough to render a valid fallback.

Injection fallback belongs in `bindings/treesitter.lua`, not `domain.lua`.

No injected-language-specific adapter is required until a real deficiency is observed.

---

## 10. Style composition

Foreground semantics and presentation styles are separate.

Example:

```text
DxType foreground
+
deprecated strikethrough
```

must be composable.

Rules:

- semantic foreground must not be destroyed by style-only modifiers;
- diagnostic undercurl must preserve source foreground;
- reference/search/selection background must not redefine semantic foreground unless explicitly intended;
- `LspForegroundPassthrough` suppresses foreground authority only.

---

## 11. Host-theme boundary

Catppuccin Mocha remains the host theme.

DX owns:

- source semantic visual language;
- selected interaction/UI overrides;
- state semantics defined by this contract.

Catppuccin continues to provide:

- base surface system;
- plugin defaults not explicitly governed by DX;
- named host colors.

TokyoNight is a design reference only.

DX-COLOR-003 MUST NOT:

- add TokyoNight as a required plugin;
- copy TokyoNight wholesale;
- change the default colorscheme away from Catppuccin.

---

## 12. Architecture Definition of Done

Architecture extraction is complete only when:

- `mappings.lua` responsibilities have been separated;
- current C3.1 visual behavior is unchanged;
- 23-role closure remains unchanged;
- all current sentinels pass;
- provider-specific rules are isolated;
- raw source HEX remains centralized;
- no speculative provider mappings exist;
- full CI is green;
- a diff review can explain every override by responsibility layer.

---

## 13. Evidence baseline references

These references are research inputs, not runtime dependencies.

### Current repository baseline

```text
snkio027/dotfiles
  baseline commit:
    19f0570ee33025832ff1d1d49269d303677d9c0f

  home/dot_config/nvim/lua/theme/init.lua
  home/dot_config/nvim/lua/theme/palette.lua
  home/dot_config/nvim/lua/theme/semantic.lua
  home/dot_config/nvim/lua/theme/mappings.lua
  home/dot_config/nvim/lua/plugins/ui.lua

  tests/nvim/color_manifest.lua
  tests/nvim/color_unit_contract.lua
  tests/nvim/color_contract.lua
```

### TokyoNight design reference

```text
folke/tokyonight.nvim
  lua/tokyonight/colors/night.lua
  lua/tokyonight/colors/storm.lua
  lua/tokyonight/groups/treesitter.lua
  lua/tokyonight/groups/semantic_tokens.lua
```

Relevant observations:

- Night inherits the Storm foreground palette and primarily darkens background surfaces.
- ordinary Tree-sitter variables use the normal foreground;
- generic LSP variable foreground is intentionally empty;
- `variable.static` is visually redirected to the Constant family;
- operator color is intentionally high-energy;
- comments are strongly de-emphasized.

Do not copy these mappings blindly; they are evidence for visual/authority design principles.

### ZLS semantic-token reference

```text
zigtools/zls
  src/features/semantic_tokens.zig
  tests/lsp_features/semantic_tokens.zig
```

Relevant observation:

ZLS can emit `variable` with modifiers including `static`, `mutable`, and `declaration`, and can emit coarse `keyword` tokens where Tree-sitter retains finer syntax distinctions.

### Neovim reference

Use the installed Neovim help for the exact running version:

```text
:help lsp-semantic-highlight
:help treesitter-highlight
:help nvim_set_hl()
```

The running Neovim behavior is authoritative for highlight-link resolution.
