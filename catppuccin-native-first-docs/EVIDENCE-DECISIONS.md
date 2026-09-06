# Catppuccin native-first evidence and decisions

Status: E1 review-ready evidence record.

## Fixed baseline

- Restored production base: `1eeb84a54fb7f37e58f2df62897b9268e20e7cb8`.
- Production control: Catppuccin Mocha with the M5/C4.4 projection.
- Locked Catppuccin commit: `edefef779ab08ce1a4a404713e3012b0d202bd35`.
- Production files, provider configuration and lockfiles: unchanged by E1.

## Experiment contract

The four cases run in independent processes and independent writable data
snapshots. Native cases retain production UX settings and integrations but
remove the complete C4.4 `custom_highlights` projection. Each run records ten
location-level observations: two existing M2 evidence locations in each of Zig,
C, C++, Rust and Python.

The record keeps these layers separate:

1. Facts: actual source Head/Tree/dirty state, run ID, fixture and lock digests,
   plugin checkouts, parser/query identities, provider executable versions,
   Neovim version, clients, capabilities, raw and decoded semantic tokens,
   complete applied groups, priorities and resolved attributes.
2. Existing policy baseline: the M2 source meaning and previously approved DX
   effective classification, included only for comparison.
3. Visual decision: not inferred by the harness.

## Automated result

Local rerun of the E1 change set rooted at the restored base, with Neovim
`0.12.5` and the locked Catppuccin checkout, produced:

| Case | Normal background | Post-fixture runtime graph | Location evidence |
| --- | --- | --- | ---: |
| M5/C4.4 | `#1A1B2A` | 1629 / `6ae44cf2...c1ab` | 10/10 |
| Native Mocha | `#1E1E2E` | 1540 / `7e86232f...b12a` | 10/10 |
| Native Macchiato | `#24273A` | 1540 / `f4052865...fe91` | 10/10 |
| Native Frappé | `#303446` | 1540 / `4c8f1260...c3db` | 10/10 |

All four runs verify private resolved data roots and seed immutability, the
locked Catppuccin commit `edefef779ab08ce1a4a404713e3012b0d202bd35`,
five-language parser/query identity, expected client attachment, exact
raw-to-Neovim semantic-token agreement, manifest-declared Tree-sitter captures,
and complete semantic type/modifier/typemod application. Native runs also prove
that neither the `theme` module nor `DxVariable` is loaded. The generated
`summary.md` and four full JSON files are local review artifacts rather than
committed mutable snapshots.

Foreground authority is recorded as one of `unique_top_foreground`,
`shared_top_foreground`, `ambiguous_top_foreground`, or `no_foreground`.
Equal-priority groups with different foregrounds are preserved as ambiguity;
array order never invents a winner. A semantic group applied with no foreground
remains distinct from a group that was not applied.

The four-report summary fails closed unless all reports share one run ID and
the same input identity, observation identity/position set, and normalized raw
token facts. It deliberately does not require visual winners or attributes to
match across flavours. Highlight graph digests use an explicit ordered attribute
encoding so repeated processes cannot vary through JSON object key order.

The attached provider topology remained ZLS for Zig, clangd for C/C++,
rust-analyzer for Rust, and Ruff plus semantic-token-producing Ty for Python.
Representative authority changes were:

- Local variable: provider-specific `@lsp.type.variable.*` in M5; Tree-sitter
  `@variable.*` in native cases.
- Struct field: provider-specific `@lsp.type.property.*` in both families.
- C++ static data member: `variable.classScope.cpp` in M5; native cases expose
  equal-priority `@property.cpp` and `@variable.member.cpp` with the same
  foreground, recorded as shared rather than ordered.
- Python instance attribute: `@lsp.type.variable.python` in M5; native cases
  expose equal-priority `@variable.python` and `@variable.member.python` with
  different foregrounds, recorded as ambiguous rather than assigned a winner.

The M5 control produced ten unique top foregrounds. Each native flavour
produced eight unique, one shared-same-foreground, and one ambiguous
observation. These classifications are evidence facts, not policy verdicts.

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
