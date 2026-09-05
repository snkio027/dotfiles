# DX-COLOR-003 — M2A Binding Topology Evidence

<!-- markdownlint-disable MD013 -->

- **Milestone:** M2A / evidence only
- **Base:** `66d1c5b2016e1198034cf945aa73137b34d18231`
- **Languages:** Zig, C, C++23, Rust, Python
- **Cases:** 28
- **Cross-producer comparisons:** 15
- **Role / palette / visual / authority delta:** none

## Runtime under observation

The local evidence run used Neovim 0.12.5, clangd 23.1.0, ZLS 0.16.0,
rust-analyzer `f8996691e9`, Pyright 1.1.413, Ruff 0.16.4, Ty 0.0.75,
Zig 0.16.0, Rust 1.98.0, and Python 3.14.7.

The manifest records observable token behavior rather than version strings. Any
provider or parser update that changes the evidence fails the locked runtime
contract and requires a new observation and review.

## Evidence interpretation

- `Raw` means a direct per-client `textDocument/semanticTokens/full` response,
  decoded against that client's negotiated `semanticTokensProvider.legend`.
  The runtime contract separately compares this result with Neovim's
  `vim.lsp.semantic_tokens.get_at_pos()` output.
- `LSP-only` names a distinction present in the compared LSP signatures but
  absent from the compared Tree-sitter capture sets.
- `TS-only` names a distinction present in Tree-sitter but lost by the LSP
  provider.
- An em dash means neither producer adds a unique distinction for that case.
- Effective groups and roles describe the current C3.1 graph. M2A does not add
  or remap any highlight.

## Zig / ZLS

| Source semantic | Topology | Tree-sitter | Raw ZLS token | Effective | LSP-only | TS-only |
| --- | --- | --- | --- | --- | --- | --- |
| top-level `const` | module / immutable / container | `@variable` | `variable`; `declaration, static` | `@lsp.typemod.variable.static.zig` → `DxVariable` | module vs local; const vs var | — |
| top-level `var` | module / mutable / container | `@variable` | `variable`; `declaration, mutable, static` | `@lsp.typemod.variable.static.zig` → `DxVariable` | module vs local; var vs const | — |
| local `const` | local / immutable / automatic | `@variable` | `variable`; `declaration` | `@lsp.type.variable.zig` → `DxVariable` | local vs module; const vs var | — |
| local `var` | local / mutable / automatic | `@variable` | `variable`; `declaration, mutable` | `@lsp.type.variable.zig` → `DxVariable` | local vs module; var vs const | — |
| parameter | parameter / immutable / call | `@variable`, `@variable.parameter` | `parameter`; `declaration` | `@lsp.type.parameter.zig` → `DxParameter` | — | — |
| struct field | member / instance-dependent / aggregate | `@variable`, `@variable.member` | `property`; `declaration` | `@lsp.type.property.zig` → `DxMember` | — | — |

ZLS provides both investigated axes: `static` separates container bindings from
function locals, while `mutable` separates `var` from `const`. The current
visual graph intentionally normalizes all four value bindings to `DxVariable`.

## C / clangd

| Source semantic | Topology | Tree-sitter | Raw clangd token | Effective | LSP-only | TS-only |
| --- | --- | --- | --- | --- | --- | --- |
| file-scope global | file / mutable / static duration | `@variable` | `variable`; `declaration, definition, globalScope` | `@lsp.type.variable.c` → `DxVariable` | global vs local; external vs internal | — |
| file-scope `static` | file / mutable / static duration | `@variable` | `variable`; `declaration, definition, fileScope` | `@lsp.type.variable.c` → `DxVariable` | file-static vs global/local | — |
| function local | local / mutable / automatic | `@variable` | `variable`; `declaration, definition, functionScope` | `@lsp.type.variable.c` → `DxVariable` | local vs file | — |
| parameter | parameter / mutable / call | `@variable`, `@variable.parameter` | `parameter`; `declaration, definition, functionScope` | `@lsp.type.parameter.c` → `DxParameter` | — | — |
| struct member | member / instance-dependent / aggregate | `@property` | `property`; `classScope, declaration` | `@lsp.type.property.c` → `DxMember` | — | — |

Under clangd 23.1.0 and this C fixture, the direct full-token response describes
the tested file-static declaration with `fileScope`, not `static`. The same run
uses the mutually distinct `globalScope`, `fileScope`, and `functionScope`
modifiers. This scoped observation is enough to show that a cross-language
domain concept cannot be defined only as “has LSP static”; it is not a claim
about every clangd version, configuration, or C construct.

## C++23 / clangd

| Source semantic | Topology | Tree-sitter | Raw clangd token | Effective | LSP-only | TS-only | Existing-domain anomaly |
| --- | --- | --- | --- | --- | --- | --- | --- |
| namespace variable | namespace / mutable / static duration | `@variable` | `variable`; `declaration, definition, globalScope` | `@lsp.type.variable.cpp` → `DxVariable` | namespace vs local | — | — |
| namespace/file `static` | namespace / mutable / static duration | `@variable` | `variable`; `declaration, definition, fileScope` | `@lsp.type.variable.cpp` → `DxVariable` | file-static vs global/local | — | — |
| static data member | member / mutable / static duration | `@property`, `@variable.member` | `variable`; `classScope, declaration, definition, static` | `@lsp.typemod.variable.static.cpp` → `DxVariable` | static vs instance member | — | `EXISTING_ROLE_ANOMALY`: investigate `DxVariable` → `DxMember` |
| instance data member | member / instance-dependent / aggregate | `@property`, `@variable.member` | `property`; `classScope, declaration` | `@lsp.type.property.cpp` → `DxMember` | instance vs static member | — | — |
| function local | local / mutable / automatic | `@variable` | `variable`; `declaration, definition, functionScope` | `@lsp.type.variable.cpp` → `DxVariable` | local vs namespace | — | — |
| parameter | parameter / mutable / call | `@variable`, `@variable.parameter` | `parameter`; `declaration, definition, functionScope` | `@lsp.type.parameter.cpp` → `DxParameter` | — | — | — |

The static data member is not evidence for admitting `DxModuleBinding`. It is a
separate existing-domain classification question: source and Tree-sitter
evidence retain type membership, while clangd changes both token type and
modifiers. Current LSP foreground authority therefore renders the static member
as `DxVariable`, not the existing `DxMember`. M2A records this as
`EXISTING_ROLE_ANOMALY`; a later classification review must decide whether
member ownership should outrank the current variable/static foreground path.

## Rust / rust-analyzer

| Source semantic | Topology | Tree-sitter | Raw rust-analyzer token | Effective | LSP-only | TS-only |
| --- | --- | --- | --- | --- | --- | --- |
| `static` item | module / immutable / static | `@constant`, `@type`, `@variable` | `static`; `declaration` | `@constant.rust` → `DxConstant` | static vs const item | — |
| `const` item | module / immutable / constant item | `@constant`, `@type`, `@variable` | `const`; `declaration` | `@constant.rust` → `DxConstant` | const vs static item | — |
| local `let` | local / immutable / automatic | `@variable` | `variable`; `declaration` | `@lsp.type.variable.rust` → `DxVariable` | — | — |
| local `let mut` | local / mutable / automatic | `@variable` | `variable`; `declaration` | `@lsp.type.variable.rust` → `DxVariable` | — | — |
| parameter | parameter / immutable / call | `@variable`, `@variable.parameter` | `variable`; `declaration` | `@lsp.type.variable.rust` → `DxVariable` | — | parameter vs local |
| struct field | member / instance-dependent / aggregate | `@variable.member` | `property`; `declaration` | `@lsp.type.property.rust` → `DxMember` | — | — |

rust-analyzer distinguishes item kinds through `static` and `const` token
types. Its negotiated legend also advertises the `parameter` token type and
`mutable` modifier. However, a direct `textDocument/semanticTokens/full`
request to rust-analyzer 0.0.0 (`f8996691e9`, 2026-08-30) returned the following
at the exact declaration sentinels:

| Sentinel | Raw token type | Raw modifiers | Neovim decoded result |
| --- | --- | --- | --- |
| `let local_value` | `variable` | `declaration` | identical |
| `let mut mutable_value` | `variable` | `declaration` | identical |
| parameter `parameter_value` | `variable` | `declaration` | identical |

The run used the production rustaceanvim settings: Clippy is selected for
checking, with no semantic-token customization. This is a runtime emission
observation for the stated version, fixture, and configuration—not a claim that
rust-analyzer lacks those vocabulary entries or never emits them elsewhere.
The protocol response, negotiated legend, client ID, and Neovim-decoded token
are checked independently, so this result cannot come from confusing workspace
symbols or `SymbolKind` data with semantic tokens. Tree-sitter preserves the
parameter distinction that current LSP foreground authority loses.

## Python / Pyright, Ruff, and Ty

Pyright is the configured interactive client and the expected client in the
existing manifest. Ruff is the configured lint/code-action companion, while Ty
is documented in the production config as an on-demand CLI check. The observed
runtime topology does not match that intended ownership.

### Runtime Provider Topology Finding

Client IDs below are ephemeral identifiers from the recorded Neovim process;
they are included to show per-client attribution, not as stable configuration.

| Configured intent | Observed client | ID | Version evidence | `semanticTokensProvider` | Observed token contribution |
| --- | --- | ---: | --- | --- | --- |
| interactive Python LSP | Pyright | 5 | CLI 1.1.413; initialize `serverInfo` unreported | no | none |
| lint/code-action companion | Ruff | 6 | server 0.16.4 | no | none |
| on-demand CLI check only | Ty | 7 | server 0.0.75 (`a553dcc1a`, 2026-08-26) | yes | all five Python binding tokens below |

All three clients attached to the same fixture. Direct full-token requests are
sent only to clients that advertise the capability; Ty's response is decoded
with Ty's own legend and matched to the same Ty client ID in Neovim's applied
tokens. The contract separately asserts that Pyright and Ruff have no semantic
token capability. Ty's automatic attachment is an observed runtime fact and a
provider-ownership finding, not an authorized M2A configuration change.

| Source semantic | Topology | Tree-sitter | Raw LSP evidence | Effective | LSP-only | TS-only |
| --- | --- | --- | --- | --- | --- | --- |
| module binding | module / dynamic / module namespace | `@variable` | Pyright: none; Ty: `variable`, `definition` | `@lsp.type.variable.python` → `DxVariable` | — | — |
| class attribute | member / dynamic / class namespace | `@variable`, `@variable.member` | Pyright: none; Ty: `variable`, `definition` | `@lsp.type.variable.python` → `DxVariable` | — | member vs local |
| instance attribute | member / dynamic / instance namespace | `@variable`, `@variable.member` | Pyright: none; Ty: `variable`, no modifiers | `@lsp.type.variable.python` → `DxVariable` | — | member vs local |
| function local | local / dynamic / function namespace | `@variable` | Pyright: none; Ty: `variable`, `definition` | `@lsp.type.variable.python` → `DxVariable` | — | local vs member |
| parameter | parameter / dynamic / call | `@variable`, `@variable.parameter` | Pyright: none; Ty: `parameter`, `definition` | `@lsp.type.parameter.python` → `DxParameter` | — | — |

Neither producer distinguishes the lowercase module binding from the local
binding. Ty distinguishes class from instance assignment through `definition`,
but that is declaration-state evidence rather than a stable ownership or scope
classification. M2A therefore does not reinterpret it as module topology.

## Cross-language result

The source-language concept “non-local value binding” is real, but the evidence
paths do not form one stable provider vocabulary:

- ZLS uses `static` for Zig container scope.
- clangd 23.1.0 uses `globalScope`, `fileScope`, and `functionScope` in the
  tested C fixture; its tested file-static declaration does not receive
  `static`.
- rust-analyzer advertises `parameter` and `mutable`, but its raw full response
  uses `variable; declaration` for all three tested local/parameter declarations.
- Python's configured Pyright client provides no semantic tokens; the
  concurrently enabled Ty provider does not distinguish module from local
  bindings.

The systems-language evidence is sufficient to justify continued role-design
research, but not sufficient to admit one role whose proposed definition spans
module scope, namespace scope, type ownership, linkage, static duration, and
constant-item semantics. The Python result and the Pyright/Ty provider split
also need an explicit runtime ownership decision before a universal adapter
contract could be reviewed.

The C++ static data member is excluded from that admission argument. It remains
an independently tracked question about classifying evidence into the existing
`DxMember` role.

The visual-value question remains untested by design: M2A proves available
distinctions, not that a developer should perceive them as a separate color
within 50 ms.

## Reproduction gates

The runtime contract disables only recursive file-watcher registration for its
immutable fixtures. It otherwise loads the production Neovim configuration,
requires the declared clients, records their negotiated capability topology,
decodes direct per-client `textDocument/semanticTokens/full` responses against
their legends, and cross-checks those signatures with Neovim's client-ID-bound
tokens. It then compares the observed Tree-sitter captures, effective groups,
and current roles against `color_manifest.lua`.

```bash
nvim -u NONE -i NONE --headless \
  "+set rtp^=$PWD/home/dot_config/nvim" \
  "+luafile tests/nvim/color_unit_contract.lua" +qa

bash tests/nvim/color/validate_fixtures.sh

nvim -n --headless \
  "+luafile tests/nvim/binding_evidence.lua" +qa

bash tests/nvim/cold_start.sh
```

Tier-2B invokes the same binding evidence contract from the Dev Container
lifecycle test after provisioning has completed.

## Decision

DEFER DxModuleBinding
