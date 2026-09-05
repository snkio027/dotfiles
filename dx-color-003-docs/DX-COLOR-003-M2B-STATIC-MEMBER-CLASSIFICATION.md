# DX-COLOR-003 — M2B C++ Static Data Member Classification

<!-- markdownlint-disable MD013 -->

- **Milestone:** M2B-A / evidence and classification only
- **Base:** `085e36c4badc6e4df548c6f74dfbd3c2e158e04f`
- **Language / provider:** C++23 / clangd
- **Cases:** 7
- **Role / palette / visual / authority / adapter delta:** none

## Question

Should a C++ static data member be classified as `DxMember` or `DxVariable` in
the DX semantic domain?

This review does not ask whether `static` deserves a distinct color and does
not reopen `DxModuleBinding`. It compares member ownership with storage-duration
evidence while preserving the current C3.1 rendering graph.

## Hypothesis

> Ownership semantics outrank storage-duration semantics for foreground
> classification.

A static data member belongs to a type even though it has static storage
duration and is not tied to an object instance. `static` changes storage and
access characteristics; it does not turn the declared entity into a namespace
or function-local variable.

## Runtime under observation

The local evidence run used Neovim 0.12.5, clangd 23.1.0, and the production
C3.1 theme graph. Raw tokens came from a direct per-client
`textDocument/semanticTokens/full` request decoded against clangd's negotiated
legend. Neovim-applied tokens and highlight extmarks were inspected separately.

At this runtime Neovim applies semantic highlights at these priorities:

```text
@lsp.type.*      125
@lsp.mod.*       126
@lsp.typemod.*   127
Tree-sitter      100
```

The test derives the complete expected group set from each raw type/modifier
signature, compares it with the extmarks Neovim actually applied, and then
checks every applied group that resolves a foreground.

## Evidence matrix

| Source occurrence | Source identity | Tree-sitter captures | Raw clangd token | Current foreground path | Current role |
| --- | --- | --- | --- | --- | --- |
| instance data member declaration | member | `property`, `variable.member` | `property`; `classScope, declaration` | `@lsp.type.property.cpp` @ 125 | `DxMember` |
| instance member access | member | `_parent`, `property` | `property`; `classScope` | `@lsp.type.property.cpp` @ 125 | `DxMember` |
| inline static data member declaration/definition | member | `property`, `variable.member` | `variable`; `classScope, declaration, definition, static` | `@lsp.typemod.variable.static.cpp` @ 127 | `DxVariable` |
| class-qualified static member access | member | `variable` | `variable`; `classScope, static` | `@lsp.typemod.variable.static.cpp` @ 127 | `DxVariable` |
| out-of-class static data member definition | member | `variable` | `variable`; `classScope, declaration, definition, static` | `@lsp.typemod.variable.static.cpp` @ 127 | `DxVariable` |
| namespace-scope variable | variable | `variable` | `variable`; `declaration, definition, globalScope` | `@lsp.type.variable.cpp` @ 125 | `DxVariable` |
| namespace/file-static variable | variable | `variable` | `variable`; `declaration, definition, fileScope` | `@lsp.type.variable.cpp` @ 125 | `DxVariable` |

## Neovim-applied modifier groups

For every modifier, Neovim applies both a modifier-only group at priority 126
and a type-plus-modifier group at priority 127. Group order below is normalized;
the test does not treat Lua table iteration order as semantic evidence.

### Instance data member declaration

```text
@lsp.type.property.cpp                         @125  foreground DxMember
@lsp.mod.classScope.cpp                        @126  no foreground
@lsp.mod.declaration.cpp                       @126  no foreground
@lsp.typemod.property.classScope.cpp            @127  no foreground
@lsp.typemod.property.declaration.cpp           @127  no foreground
```

Instance access applies the corresponding three-group subset for
`property + classScope`; only the base property group has a foreground.

### Inline declaration and out-of-class definition

```text
@lsp.type.variable.cpp                         @125  foreground DxVariable
@lsp.mod.classScope.cpp                        @126  no foreground
@lsp.mod.declaration.cpp                       @126  no foreground
@lsp.mod.definition.cpp                        @126  no foreground
@lsp.mod.static.cpp                            @126  no foreground
@lsp.typemod.variable.classScope.cpp            @127  no foreground
@lsp.typemod.variable.declaration.cpp           @127  no foreground
@lsp.typemod.variable.definition.cpp            @127  no foreground
@lsp.typemod.variable.static.cpp                @127  foreground DxVariable
```

The class-qualified reference applies the five-group subset for
`variable + classScope + static`. Its two foreground candidates are the base
variable group at 125 and the static typemod at 127; both resolve to
`DxVariable`, and the higher-priority typemod wins.

### Namespace controls

The namespace/global control applies `variable`, `declaration`, `definition`,
and `globalScope` groups. The file-static namespace control substitutes
`fileScope`. Only `@lsp.type.variable.cpp` has a foreground in either case.

## Modifier competition finding

Multiple clangd modifiers do create multiple Neovim typemod extmarks at the
same priority. They do not currently create competing modifier foregrounds:

```text
classScope typemod    no foreground
declaration typemod   no foreground
definition typemod    no foreground
static typemod        DxVariable foreground
```

The current result is therefore deterministic for this graph. The anomaly is
not an accidental equal-priority tie; it is the explicit generic
`variable.static -> DxVariable` foreground taking precedence over the base
variable and Tree-sitter evidence.

## Classification reasoning

The seven cases establish all of the following within the tested fixture and
provider version:

1. Instance member declaration and access already resolve to `DxMember`.
2. Static member declaration, reference, and definition retain the same source
   ownership: each names a member of `BindingProbe`.
3. clangd consistently preserves that ownership as `classScope` on all three
   static-member occurrences, even though it changes the token type from
   `property` to `variable`.
4. Namespace variables use `globalScope` or `fileScope`, not `classScope`.
5. Tree-sitter preserves member identity for the in-class declaration but not
   for the qualified reference or out-of-class definition. Tree-sitter alone
   cannot implement a complete occurrence-level rule.
6. Static storage does not provide a semantic reason to classify a type-owned
   entity as an ordinary namespace or local variable.

The stable domain concept already exists: `DxMember`. No new role is needed.

## Decision

RECLASSIFY STATIC DATA MEMBER TO DxMember

This is a classification decision, not a rendering change. The current fixture
continues to render all three static-member occurrences as `DxVariable` so the
evidence commit remains behavior-preserving.

## Follow-up boundary

Any M2B-B implementation must be a separate, narrowly reviewed change. It must
not define “member” as “has the LSP `static` modifier” and must prove that the
chosen clangd/C++ adapter rule does not recolor namespace, file-scope, or
function-local static variables. In particular, a bare generic
`@lsp.typemod.variable.static` remap is not authorized by this decision.

The implementation must also account for Neovim's equal-priority typemod
composition so a `classScope` rule cannot race a conflicting `static` foreground.

## Preserved contracts

```text
Domain roles                    23 / unchanged
semantic rendering sentinels    42 / unchanged
M2A binding cases               28 / unchanged
M2A producer comparisons        15 / unchanged
C3.1 highlight graph            221 / unchanged
C3.1 graph SHA-256              unchanged

DxModuleBinding                 DEFERRED
Python provider ownership       NOT TOUCHED
C4                              NOT STARTED
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

Tier-2B runs the same evidence contract after Dev Container provisioning and
requires both the M2A and M2B completion markers.
