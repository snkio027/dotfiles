# E batch 3 — alias identity evidence

Base: `081c92757e01a6464f3f49e6fd0e5eedc4fc5921` (PR #60 merge).
Status: **classification review pending; no production correction proposed**.
This is the first, bounded topic of batch 3, not approval of the remaining semantic backlog.

## Question and scope

Do namespace/module aliases and type aliases preserve the identity of the entity
they name, including when a type occurs before `::`? Add six C++ and eight Rust
positions to the existing fixtures and `classification_reviews.alias_identity`.
The manifest records settled observations separately from source meaning; it does
not redefine `use`, alias syntax, immutability, constructors or callable values.

Language facts: a C++ namespace alias names a namespace; an alias-declaration
introduces a typedef-name, not a new type ([C++23 draft N4950, namespace.alias / dcl.typedef](https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2023/n4950.pdf)).
Rust [`use`](https://doc.rust-lang.org/reference/items/use-declarations.html)
can alias either a module or a type; [`type`](https://doc.rust-lang.org/reference/items/type-aliases.html)
gives an existing type a new name. Rust's name-resolution “type namespace” also
contains modules: that language term is **not** the DX role `DxType`.

## Settled observations

All groups below are actual LSP foreground owners at priority 125; the manifest
retains exact modifiers, TS captures, applied groups and independent role expectations.

| Positions | Raw provider type | Winning group → observed role |
| --- | --- | --- |
| C++ `route` namespace alias declaration/reference (2) | clangd `namespace` | `@lsp.type.namespace.cpp` → DxNamespace |
| C++ `AliasPayload` declaration/reference/qualifier, terminal `Payload` (4) | clangd `class` | `@lsp.type.class.cpp` → DxType |
| Rust `route` module alias declaration/reference (2) | rust-analyzer `namespace` | `@lsp.type.namespace.rust` → DxNamespace |
| Rust explicit `AliasPayload` declaration/reference/qualifier (3) | rust-analyzer `typeAlias` | `@lsp.type.typeAlias.rust` → DxType |
| Rust `ImportedPayload` use-as declaration/reference, terminal `Payload` (3) | rust-analyzer `struct` | `@lsp.type.struct.rust` → DxType |

Important boundaries: both languages' type qualifier has a TS `module` capture
as well as `type` (Rust also has `variable`), but the resolved LSP entity keeps
DxType. Rust's module use-as and type use-as must not share a syntax-only rule.
No capitalization heuristic, extra role, priority override or adapter change is needed.

## Initialization is not semantic readiness

An initial raw capture reported both Rust use-as declarations as
`variable + declaration` → DxVariable; explicit type-alias references initially
reported `struct`. An independent process, after further analysis time, returned
the settled identities above. This is **not evidence of a permanent alias defect**.
The pinned RA [rename classifier](https://github.com/rust-lang/rust-analyzer/blob/9074e9b4c6bc31d7986ccf4e22d18af70e5508da/crates/ide-db/src/defs.rs#L624)
tries to resolve the target; its [syntax fallback](https://github.com/rust-lang/rust-analyzer/blob/9074e9b4c6bc31d7986ccf4e22d18af70e5508da/crates/ide/src/syntax_highlighting/highlight.rs#L781)
can classify a rename as Local. The observed transition is consistent with that
fallback; no claim is made to have instrumented its internal cause.

The existing binding harness now waits on the **whole alias raw-token matrix**,
then independently waits for the same client-ID-bound native tokens. Protocol null
means pending, never PASS. Protocol errors and malformed data still fail. Polling
is bounded (15-second poll windows; each synchronous request also has its existing
15-second timeout), not a fixed sleep or a strict 15-second total deadline.
Existing M2 captures keep their original strict request behavior.

## Verification and decision boundary

Local isolated config/state/cache, exact 70-plugin lock; existing Mason tools and
parser binaries reused without install/update. Neovim 0.12.5, clangd 23.1.1,
rust-analyzer `9074e9b4c6` (2026-09-06), rustc 1.98.1. No fresh-download claim.

- Unit: 23 roles / 42 sentinels, 14 alias locators, existing shared-color controls PASS.
- Binding runtime: original 28/28, 15/15, 7/7, 13/13 and new 14/14 PASS.
- All five compiler fixtures warning-clean PASS; C remains a clangd regression guard.
- E graph remains `226 / 44df09042fd6fcb77f4421244a9eb1336c124ce394828cc67e5160cba314c701`.
- Local process-only negative injection: module/type wrong links with matching RGB
  are rejected by identity checks; perpetual alias-stage protocol null is rejected
  nonzero without the completion marker. These fault injections are local evidence,
  not additional CI jobs or production switches.
- Locked Cold Start and double Lifecycle run the extended existing harness;
  Lifecycle additionally requires the 14/14 marker. Remote results belong to this PR's CI.

Recommendation for review: **KEEP the existing production mapping for this scope**.
New semantic correction, Zig aliases, const/let rules and callable cases remain
unapproved. No `home/`, HEX, provider, lock, font, Ghostty, or daily-config change;
no apply. This evidence does not claim a new human visual acceptance session.
