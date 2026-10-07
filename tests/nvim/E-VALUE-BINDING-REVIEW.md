# E batch 3 — value bindings and named constants

Base: `98d50388f5a478a6009cc6fbf4cfeacb7b174f2a` (PR #61 merge).
Base main CI: [34752978218](https://github.com/snkio027/dotfiles/actions/runs/34752978218), completed/success.
Status: **evidence and recommendations for review; no CHANGE authorized**.

## Inventory, not a replacement specification

Reuse the domain, generic LSP bindings and C++ member decisions. `readonly` and
`static` are not generic permission to override variable identity. PR #61's
14 alias positions remain protected; its review decision is KEEP. Its manifest
and evidence document remain the original review snapshots, not rewritten here.

Nine existing declarations already cover C++ namespace/local variables,
namespace/local static and namespace constexpr, plus Rust let/let mut/const/static.
Add eleven reference markers to existing code and two C++ local declarations:
runtime-initialized `const` and same-scope `constexpr`, each with a reference.
That is **13 new observed positions, 11 declaration/reference pairs (22 positions,
9 reused)**. Only two objects and their consuming expression are new fixture code.

Existing approved protections: C++ namespace variables (including readonly),
function-local static, fields and static data members. Existing but pending
cross-language policy: Rust let/let mut/const/static. Missing before this change:
paired uses and the same-scope const/constexpr capability control. Zig stays out.

## Facts, observations and proposed policy

All roles below are observed at both paired positions, not inferred from RGB.
KEEP entries are recommendations to preserve these results, not blanket approval
of every language construct that happens to share a modifier or spelling.

| Construct / pair | Current role | Proposed role / decision | Reason and implementation boundary |
| --- | --- | --- | --- |
| C++ `namespace_counter`, `local_value` | DxVariable | DxVariable / KEEP | Ordinary objects retain value-binding identity. |
| C++ `namespace_static_counter`, `function_static_count` | DxVariable | DxVariable / KEEP | Storage duration/linkage is not member or constant identity. |
| C++ `runtime_readonly`, initialized from a parameter | DxVariable | DxVariable / KEEP | Non-reassignability alone must not make an ordinary binding yellow. |
| C++ namespace `namespace_readonly`, local `local_constant` constexpr objects | DxVariable | KEEP current role; DEFER selective yellow migration | Preserve the approved namespace rule. Current same-scope evidence cannot separate runtime const from constexpr; no CHANGE is requested. |
| Rust `local_value` / `mutable_value` (`let` / `let mut`) | DxVariable | DxVariable / KEEP | Mutability is a binding attribute, not a different primary entity. |
| Rust `MAX_CAPACITY` const item | DxConstant | DxConstant / KEEP for this pair | Language constant item; declaration and reference have different available evidence. See naming limit below. |
| Rust `MODULE_COUNTER` immutable static item | DxConstant | KEEP this observed visual grouping; DEFER a universal static policy | A storage allocation, not the same language construct as const. Shared yellow is a visual grouping, not a claim of semantic equivalence. |
| Previously approved C++ fields / static members | DxMember | Existing decision protected | Original 7 classification / 13 behavior checks remain; no new member classification. |

Suggested design direction: `DxConstant` describes a **constant-family entity or
an explicitly reviewed visual grouping**, not every readonly binding. A change
to production still needs separate approval and independently sufficient evidence.

Language basis: C++ const qualification does not itself make an initializer a
constant expression; constexpr objects have additional constant-initialization
requirements. Static storage is a separate axis ([C++23 N4950: dcl.type.cv,
dcl.constexpr, basic.stc.static](https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2023/n4950.pdf)).
Rust [let statements](https://doc.rust-lang.org/reference/statements.html#let-statements)
introduce bindings. A [const item](https://doc.rust-lang.org/reference/items/constant-items.html)
is not associated with one specific memory location; a
[static item](https://doc.rust-lang.org/reference/items/static-items.html)
represents a storage allocation. These facts constrain, but do not dictate, the visual decision.

## What the providers can actually prove

### C++: a same-scope counterexample to modifier-based yellow

Both new local declarations have clangd type `variable` with
`declaration, definition, functionScope, readonly`. Both references have
`variable + functionScope, readonly`. Their Tree-sitter capture is `variable`.
The runtime contract compares these two actual protocol/capture signatures;
both resolve through `@lsp.type.variable.cpp` to DxVariable.

Thus the current token/capture evidence cannot select local constexpr without
also selecting runtime const. This does not claim the distinction is impossible
with other evidence. It rejects a readonly heuristic and defers additional machinery.
Namespace constexpr stays covered by its earlier protected expectation.

### Rust: distinct raw entities, currently shared TS foreground

Settled references are `variable` (let), `variable + mutable` (let mut),
`const + constant, public` (const item), and `static + public` (static item).
Variable foregrounds are LSP-owned at priority 125. For the two named items the
semantic token has **no applied foreground**; `@constant.rust` wins from Tree-sitter
at priority 100, resolving to DxConstant. The manifest checks both the empty LSP
foreground list and the actual TS winner rather than inventing an LSP owner.

The locked [Rust query](https://github.com/nvim-treesitter/nvim-treesitter/blob/19071296d3d643b48615ee574a20e8a03ac40872/runtime/queries/rust/highlights.scm)
explicitly captures const declarations, and also classifies all-capital identifiers
as constants. These fixtures use all-capital names: **they do not establish a
spelling-independent rule for all const references or immutable static items**.
No naming heuristic is introduced here. Broader policy remains DEFER; raw const
versus static is available, but whether to give it foreground authority is not approved.

## Evidence and timing boundaries

Use the existing raw `semanticTokens/full` decoder, same-client native token
comparison, actual captures/applied priorities, native highlight-link identity,
and actual foreground comparison. New explicit snapshots live under
`classification_reviews.value_binding`; they do not derive expected roles from
the observed color. Same-color wrong-link and wrong-foreground controls remain.

Reuse the alias bounded polling helper without changing its timeouts: whole
language/topic raw matrix, then client-bound native matrix. Null is pending;
errors/malformed data fail. This proves matching within finite observation
windows, **not an independent server-ready event or first-frame stability**.

Existing declarations retain their earlier strict capture path. A later separate
raw probe adds `public` to the Rust static declaration, `constant, public` to the
const declaration, and `mutable` to let mut. Their foreground roles are unchanged.
Do not rewrite the earlier modifier snapshots as if they were later observations.
Pair checks compare actual roles from separately collected declaration/reference
samples; they do not assert both were captured in one settled response or that
all intermediate frames agree.

## Validation and exclusions

Local validation uses isolated config/state/cache with the exact 70-plugin lock,
existing parser binaries and installed Mason tools; no install/update or fresh
download claim. Neovim 0.12.5, clangd 23.1.1, rust-analyzer `9074e9b4c6`
(2026-09-06), rustc 1.98.1. Results and precise candidate SHA belong in the PR.

Required existing regressions remain: 23 roles, 42 sentinels, M2 28/28 and 15/15,
member 7/7 and 13/13, alias 14/14, five-language compile/runtime, Python ownership,
and same-color identity negatives. Lifecycle additionally requires the new
13/13-position and 11/11-pair completion marker.

Local unit, five-language compiler/color runtime, production visual and Python
ownership checks passed; the complete binding harness passed twice. Disposable
process-only injections also returned exit 1: a new const position linked to
DxConstant with identical RGB failed `DX_IDENTITY_MISMATCH`; perpetual protocol
null in the new review stage failed its bounded wait. Neither emitted the new
success marker. These injections are local evidence, not new CI jobs or switches.

E graph is unchanged: `226 / 44df09042fd6fcb77f4421244a9eb1336c124ce394828cc67e5160cba314c701`.
No production mapping, HEX, roles, provider, dependency, lock, font or Ghostty
change; no apply or automatic merge. No new human visual verdict is claimed.
Callable, Zig bindings, naming-independent Rust item coverage and any selective
constexpr migration remain separate questions, not silently accepted rules.
