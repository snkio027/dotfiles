# DX-COLOR-003 — M2B-B C++ Static Data Member Correction

<!-- markdownlint-disable MD013 -->

- **Milestone:** M2B-B / narrow behavior correction
- **Base:** `6d44ffe3108311396ceaedef527a24c6d3b1cebd`
- **Language / provider:** C++23 / clangd
- **Approved decision:** `RECLASSIFY STATIC DATA MEMBER TO DxMember`
- **Domain / palette / visual-profile delta:** none

## Objective

Implement the classification approved by M2B-A without redefining generic
`static` semantics. For C++ static data members, type-member ownership is the
foreground identity; static storage, readonly state, and default-library
provenance are orthogonal.

The frozen M2B-A report remains the pre-correction evidence record. This file
records the separately reviewed behavior change.

## Adapter policy

The clangd/C++ adapter owns exactly four new filetype-specific groups:

```text
@lsp.typemod.variable.classScope.cpp
    -> DxMember

@lsp.typemod.variable.static.cpp
    -> LspForegroundPassthrough

@lsp.typemod.variable.readonly.cpp
    -> LspForegroundPassthrough

@lsp.typemod.variable.defaultLibrary.cpp
    -> LspForegroundPassthrough
```

The provider-independent rules remain unchanged:

```text
@lsp.typemod.variable.static
    -> DxVariable

@lsp.typemod.variable.readonly
    -> DxVariable

@lsp.typemod.variable.defaultLibrary
    -> DxVariable
```

No generic modifier maps to `DxMember`. C, Zig, Rust, Python, and other
providers/filetypes retain their existing semantics. Ordinary C++ variables
still inherit `DxVariable` from their base type after an orthogonal modifier's
filetype-specific foreground is suppressed.

## Runtime closure

The runtime harness independently checks the raw clangd
`textDocument/semanticTokens/full` response, Neovim's client-ID-bound decoded
token, every applied semantic type/modifier/typemod extmark, its priority, each
foreground-owning group, the effective winner, and the final DX role.

| C++ occurrence | Raw clangd token | Effective foreground | Final role |
| --- | --- | --- | --- |
| in-class inline static declaration/definition | `variable`; `classScope, declaration, definition, static` | `variable.classScope.cpp` @ 127 | `DxMember` |
| class-qualified static reference | `variable`; `classScope, static` | `variable.classScope.cpp` @ 127 | `DxMember` |
| out-of-class static definition | `variable`; `classScope, declaration, definition, static` | `variable.classScope.cpp` @ 127 | `DxMember` |
| readonly static-member declaration/definition | `variable`; `classScope, declaration, definition, readonly, static` | `variable.classScope.cpp` @ 127 | `DxMember` |
| class-qualified readonly static-member reference | `variable`; `classScope, readonly, static` | `variable.classScope.cpp` @ 127 | `DxMember` |
| standard-library `path::preferred_separator` | `variable`; `classScope, defaultLibrary, readonly, static` | `variable.classScope.cpp` @ 127 | `DxMember` |
| instance member declaration | `property`; `classScope, declaration` | `type.property.cpp` @ 125 | `DxMember` |
| instance member reference | `property`; `classScope` | `type.property.cpp` @ 125 | `DxMember` |
| namespace global variable | `variable`; `declaration, definition, globalScope` | `type.variable.cpp` @ 125 | `DxVariable` |
| namespace file-static variable | `variable`; `declaration, definition, fileScope` | `type.variable.cpp` @ 125 | `DxVariable` |
| function-local static variable | `variable`; `declaration, definition, functionScope, static` | `type.variable.cpp` @ 125 | `DxVariable` |
| ordinary local variable | `variable`; `declaration, definition, functionScope` | `type.variable.cpp` @ 125 | `DxVariable` |
| namespace readonly variable | `variable`; `declaration, definition, globalScope, readonly` | `type.variable.cpp` @ 125 | `DxVariable` |

## Equal-priority foreground contract

For each corrected static-member occurrence, Neovim applies `classScope.cpp`
and every modifier present in the raw clangd token at semantic-token priority
127. The tested modifier set is:

```text
@lsp.typemod.variable.classScope.cpp
@lsp.typemod.variable.static.cpp
@lsp.typemod.variable.readonly.cpp
@lsp.typemod.variable.defaultLibrary.cpp
```

Only the `classScope.cpp` group resolves a foreground. The other three groups
link to the empty authority passthrough group and therefore carry no highlight
attributes that can compete for foreground. The harness requires the unique
highest-priority foreground to be `classScope.cpp -> DxMember`; any second
foreground at priority 127 fails closed.

The function-local static control still receives the `static.cpp` extmark, but
it has no `classScope` token. Its base `type.variable.cpp` foreground therefore
remains authoritative and resolves to `DxVariable`. The namespace readonly
control proves the equivalent behavior for `readonly.cpp`.

The standard-library probe is evidence-backed rather than speculative: local
clangd 23.1.0 emits `variable + classScope + defaultLibrary + readonly + static`
for `std::filesystem::path::preferred_separator`, and Neovim applies all four
modifier typemods while preserving `classScope.cpp` as the sole priority-127
foreground.

## Graph governance

The historical M1 oracle remains immutable:

```text
M1 graph count      221
M1 graph SHA-256    05ff81df9019ace7bee14a494db1a9e39c7d18426f3b78bae1ef3012a068a276
```

The M2B-B graph is frozen separately:

```text
M2B-B graph count   225
M2B-B graph SHA-256 a2db03bf6a138c0784d74277adf6f7ee706a5398336305385ced7d3725c0dedf
```

The four-group delta is exactly:

```text
@lsp.typemod.variable.classScope.cpp
@lsp.typemod.variable.static.cpp
@lsp.typemod.variable.readonly.cpp
@lsp.typemod.variable.defaultLibrary.cpp
```

The unit contract removes only those four groups from the current graph and
requires the reconstructed graph to equal the historical 221-group M1 digest.
An additional group or attribute change therefore fails either the current
M2B-B oracle or the reconstructed historical oracle.

## Preserved contracts

```text
Domain roles                    23 / unchanged
semantic rendering sentinels    42 / unchanged
M2A binding case topology       28 / preserved
M2A producer comparisons        15 / unchanged
M2B-A classification topology   7 / preserved
Catppuccin palette              Mocha / unchanged
C3.1 visual role values         unchanged

DxModuleBinding                 DEFERRED
Python provider ownership       NOT TOUCHED
C4                              NOT STARTED
plugin/tool versions            unchanged
```

## Reproduction gates

```bash
nvim -u NONE -i NONE --headless \
  "+set rtp^=$PWD/home/dot_config/nvim" \
  "+luafile tests/nvim/color_unit_contract.lua" +qa

bash tests/nvim/color/validate_fixtures.sh

nvim -n --headless \
  "+luafile tests/nvim/binding_evidence.lua" +qa

bash tests/nvim/cold_start.sh
```

Tier-2B runs the same 13-case behavior contract after Dev Container
provisioning and requires both the M2B-A and M2B-B completion markers.
