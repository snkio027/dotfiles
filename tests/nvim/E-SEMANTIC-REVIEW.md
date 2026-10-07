# DX-COLOR-003 E — batch 1: shared-color evidence

Base: `d77b08afc0db769b30159bb94d52ac8d91b0bf3a`. Scope: tests and this incremental record only. E is the sole next visual input; production remains C4.4. No palette, provider, adapter, fixture, dependency, font, or daily configuration change; no apply or runtime selector. This is not a new parallel semantic specification.

## Fixed input for batch 2 (not deployed here)

Exactly eight `palette.code` changes: keyword/function-keyword `#79AAFF`, namespace `#DB8FEE`, type `#3DD1BB`, callable `#FFB266`, meta `#FF8F7D`, number/constant `#F2D675`. All other source values remain as in the base, including builtin `#9ECE6A`. E will have 19 source roles / 17 colors; domain remains 23 roles. State colors, Normal background `#1A1B2A`, Mocha surfaces and styles remain unchanged. This batch does not evaluate E's visual comfort or replace C4.4's numerical oracle.

## Evidence correction

- `binding_evidence.lua` and `python_provider_ownership.lua` previously reverse-looked up role names by RGB. Both now use the same test-only `highlight_evidence.lua`.
- Identity comes from Neovim's native `synIDtrans` / `synIDattr` link resolution, including actual implicit `@capture.language` fallback. No RGB inference, manifest echo, dotted-name classifier, or new runtime policy. Explicit direct attributes do not inherit a guessed parent identity.
- Effective foreground is independently compared to the resolved role foreground. M2 observations record the observed role, not a copied expectation. Client-bound/raw tokens, capture lists, winning group/source and unique top-priority foreground checks remain intact.
- `color_contract.lua` previously treated matching foreground as its position-level ROLE_ASSERT. It now also checks the actual winning role for every existing sentinel and six live TS/LSP bindings covering the two shared pairs; its independent 23-role palette mapping, capture/protocol/authority checks and diagnostics remain.
- `color_unit_contract.lua` already asserts explicit graph links and has no global one-RGB/one-role requirement. It now runs the small shared-color contract through the existing Tier-1 entrypoint (therefore existing Validate/Locked/Lifecycle wiring). No new CI job.
- `visual_contracts/c4.lua` contains deliberate C4.4 pairing/contrast constraints, not a semantic classifier. Those constraints and historical graph reconstruction remain unchanged in this batch. `production_visual_runtime.lua` still checks concrete attributes and the C4.4 visual contract; it is complementary, not the source of role identity.

Shared-color controls operate on real Neovim highlight definitions (not new language fixtures): both E pairs pass, including inherited groups and LSP number/enumMember links. Function-keyword -> keyword and number -> constant wrong links fail while RGB remains identical. Direct child overrides, even with matching RGB, and mismatched measured foreground fail. Mutated highlight definitions are restored on success/failure. Separately replacing the assertion with color-only acceptance for each pair makes the existing runner exit 1. These group-level controls are not claimed as additional raw-provider observations.

## KEEP / REVIEW / GAP

Status labels are review notes, not runtime configuration or newly approved classifications. Locations below refer to existing tags in `color_manifest.lua` and their original language fixtures.

| Status | Existing evidence / boundary | Current outcome and next action |
| --- | --- | --- |
| KEEP | `cpp.classification.*`, `cpp.behavior.*` | clangd variable+classScope -> DxMember; static/readonly/defaultLibrary alone do not own member foreground. Preserve 6 corrected members + 2 existing members + 5 variable negatives. |
| KEEP | `c.int.builtin`, `cpp.int.builtin`, `zig.u8.builtin` | Type-taxonomy loss suppresses the provider foreground; actual Tree-sitter builtin remains DxBuiltin. Preserve C regression alongside C++. |
| KEEP | `rust.lifetime.*`, `rust.must_use.attribute`, `rust.dispatch.label` | Lifetime, attribute and label retain distinct semantic roles and authority. No new rule for all attributes or all control labels. |
| KEEP | `zig.pub.keyword`, `zig.fn.keyword`, `zig.sizeof.builtin` | Keyword/function-keyword remain distinct roles despite future shared blue. Zig builtin operation remains DxMeta; not proof that all special operations execute at compile time. |
| KEEP | Python provider contract | Installed Pyright remains disabled/unattached; Ty+Ruff attached, Ty sole semantic producer. Empty `pyright.lua` is not evidence that Pyright is active. |
| REVIEW | `rust.binding.static_item`, `rust.binding.const_item`, `zig.binding.top_level_const` / `local_const` | Rust static/const currently use TS DxConstant; Zig const bindings use LSP DxVariable (container scope adds static). Preserve observations; do not turn all immutable bindings yellow. |
| REVIEW | `rust.binding.parameter`, `python.binding.class_attribute` / `instance_attribute` | Current winning roles are DxVariable despite more specific TS parameter/member captures. This is observed provider/authority behavior, not an approval to change precedence. Any correction needs declaration/reference negatives and explicit review. |
| GAP | Rust `Status::Finished(code)` / `Ok(summary)` in `color/rust/src/main.rs`; Zig enum/error examples in `color/zig/src/main.zig` | Code exists, but no dedicated declaration/use/pattern evidence matrix for all variant/construction forms. Do not infer a universal constructor or enum-variant rule from an HTML color sample. |
| GAP | `std`/`@import` paths, aliases; function-pointer variables, closure bindings, callable fields | Existing namespace/callable links do not provide the complete alias-vs-entity or call-site-vs-binding matrix. Add legal minimal cases only after a specific review question is chosen. DxModuleBinding remains deferred. |
| GAP | Python `@dataclass` / `@property`, C++ template parameters and constructors, Zig type-returning functions | Some forms are present, but complete location-sensitive evidence is absent. No naming heuristic or blanket mapping adopted. |
| KEEP / GAP | deprecated and readonly/defaultLibrary composition | Existing style/foreground governance stays protected. Incomplete syntax, pre-attach fallback and broad UI-state visual acceptance are not newly established by this batch. |

## UI consumer inventory before E deployment

Blink function/method/constructor, type and module kinds already link to Dx roles and should follow their semantic colors. No binding changes needed.

Seven decorative consumers will otherwise move with the eight-value E delta: `RenderMarkdownQuote`, `RenderMarkdownH1`, `RenderMarkdownHint` (keyword); `RenderMarkdownH3` (type); `NeotestMarked`, `DapBreakpointCondition`, `RenderMarkdownCodeInline` (number). Batch 2 must preserve their current appearance via minimal independent palette/UI references, unless separately approved. They are not silently classified as source semantics. `CursorLineNr`, `SnacksIndentScope`, `NeotestFocused` and H2 borrow unchanged member color. Diagnostic state, stopped-line and background definitions do not change here.

## Local execution evidence

Isolated config/state/cache and 70 plugin copies checked out to the exact base lock; installed Mason tools reused, with no install/update. Daily files remain untouched. Versions: Neovim 0.12.5, clangd 23.1.1, rust-analyzer `9074e9b4c6` (2026-09-06), Zig/ZLS 0.16.0, Ty 0.0.80, Ruff 0.16.7, rustc/cargo 1.98.1. Parser binaries reused from the installed set; this is not a fresh-XDG parser download proof.

- C4.4 unit + new shared-color controls: PASS; existing graph remains `226 / 51cfaae3c02ec25551f1a8afd27427d3919d6b53c3b05f5ae26ff6c125aa6666`; 23 roles / 42 sentinels preserved.
- Strict C/C++/Rust/Zig/Python color runtime: PASS; actual configured servers attached, existing sentinels checked.
- M2A: 28/28 observations + 15/15 comparisons. M2B: 7/7. M2B-B: 13/13. All PASS with unchanged manifest.
- Python ownership unit/runtime and raw Ty -> client-ID-bound token -> actual foreground: PASS.
- C4.4 production visual runtime and five-language compiler fixture validation: PASS.
- Two color-only mutation probes: rejected with runner exit 1 (one per approved shared pair).
- Additional process-only sharing (`keyword_function = keyword`, `constant = number`, no E deployment): strict five-language color runtime and M2 28/28 + 15/15 + 7/7 + 13/13 PASS. Independently wrong-linking each shared pair after ColorScheme makes the real color runtime exit 1 with `DX_IDENTITY_MISMATCH`, despite identical RGB. Test scripts/logs are local validation artifacts, not new production switches.
- Full fresh-XDG Locked Cold Start and double-lifecycle container validation: remote PR gates pending, not claimed as locally completed. macOS E screenshots and E activation: NOT RUN / NOT AUTHORIZED by this batch.

Stop after this narrow PR for review. Batch 2 may migrate visuals only after shared-color evidence review; batch 3 requires individual semantic decisions. No automatic merge, deployment or dependency updates follow from these results.
