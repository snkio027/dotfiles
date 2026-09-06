# Catppuccin native-first evidence and decisions

Status: E1 review-ready evidence record.

## Fixed baseline

- Restored production base: `1eeb84a54fb7f37e58f2df62897b9268e20e7cb8`.
- Production control: Catppuccin Mocha with the M5/C4.4 projection.
- Locked Catppuccin commit: `edefef779ab08ce1a4a404713e3012b0d202bd35`.
- Production files, provider configuration and lockfiles: unchanged by E1.

## Experiment contract

The four cases run in independent processes. Native cases retain production UX
settings and integrations but remove the complete C4.4 `custom_highlights`
projection. Each run records ten location-level observations: two existing M2
evidence locations in each of Zig, C, C++, Rust and Python.

The record keeps these layers separate:

1. Facts: paths, versions, clients, capabilities, parser/query sources, raw and
   decoded semantic tokens, applied groups, priorities and resolved attributes.
2. Existing policy baseline: the M2 source meaning and previously approved DX
   effective classification, included only for comparison.
3. Visual decision: not inferred by the harness.

## Automated result

Local run on the restored base, with Neovim `0.12.5` and the locked Catppuccin
checkout, produced:

| Case | Normal background | Post-fixture runtime graph | Location evidence |
| --- | --- | --- | ---: |
| M5/C4.4 | `#1A1B2A` | 1629 / `15d45965...37e7` | 10/10 |
| Native Mocha | `#1E1E2E` | 1540 / `e9f18af7...16cf` | 10/10 |
| Native Macchiato | `#24273A` | 1540 / `7861cb31...042` | 10/10 |
| Native Frappé | `#303446` | 1540 / `452c8ea1...e1ca8` | 10/10 |

All four runs verified private `stdpath` roots, locked Catppuccin commit
`edefef779ab08ce1a4a404713e3012b0d202bd35`, five-language parser/query
availability, expected client attachment, and exact raw-to-Neovim semantic-token
agreement. Native runs also proved that neither the `theme` module nor
`DxVariable` was loaded. The generated `summary.md` and four full JSON files are
local review artifacts rather than committed mutable snapshots.

The attached provider topology remained ZLS for Zig, clangd for C/C++,
rust-analyzer for Rust, and Ruff plus semantic-token-producing Ty for Python.
Representative authority changes were:

- Local variable: provider-specific `@lsp.type.variable.*` in M5; Tree-sitter
  `@variable.*` in native cases.
- Struct field: provider-specific `@lsp.type.property.*` in both families.
- C++ static data member: `variable.classScope.cpp` in M5; Tree-sitter
  `@variable.member.cpp` in native cases.
- Python instance attribute: `@lsp.type.variable.python` in M5; Tree-sitter
  `@variable.member.python` in native cases.

These are authority and visual observations under the same token facts. E1 does
not yet classify the native differences as policy preservation or violation.

A successful run means only:

```text
HARNESS PASS
POLICY VERDICT NOT EVALUATED
VISUAL PREFERENCE NOT RECORDED
```

Locked Cold Start repeats the same four-process experiment after the production
M5 contracts pass. Environment failures remain failures; native visual or policy
differences remain observations.

## Human decision

Pending. The user must select one of:

```text
SELECT NATIVE MOCHA
SELECT NATIVE MACCHIATO
SELECT NATIVE FRAPPE
RETAIN M5
NEEDS ANOTHER COMPARISON
```

No selection, production change, merge or apply is implied by E1.
