# DX-COLOR-003 E — batch 2: visual migration

Base: `41423d77b31f72e886300add6be56127e35fb68e` (PR #59 merged; main CI `34749439759` successful). This batch implements the fixed E visual input on the existing semantic architecture. It does not approve any REVIEW/GAP classification from [batch 1](E-SEMANTIC-REVIEW.md), switch providers, upgrade dependencies, alter fonts/Ghostty, or authorize apply.

## Production delta

| `palette.code` | C4.4 | E |
| --- | --- | --- |
| keyword | `#BB9AF7` | `#79AAFF` |
| keyword_function | `#7DCFFF` | `#79AAFF` |
| callable | `#E6B35C` | `#FFB266` |
| type | `#2AC3DE` | `#3DD1BB` |
| meta | `#D16DDB` | `#FF8F7D` |
| namespace | `#5EA1FF` | `#DB8FEE` |
| number | `#F09A6C` | `#F2D675` |
| constant | `#DCC66A` | `#F2D675` |

All eleven remaining source tokens, five state colors, Mocha surfaces, `Normal.bg #1A1B2A`, and styles remain unchanged. There are still 23 roles; the 19 source roles intentionally use 17 colors. Keyword/function-keyword and number/constant remain different semantic identities despite sharing RGB.

`palette.lua` remains the only production HEX owner. The existing `visual/c4.lua` and `visual_contracts/c4.lua` paths are retained with E descriptions; there is one production projection and no selector or compatibility runtime.

Seven decorative consumers retain their complete composed definitions through three independent `ui.accent_*` palette entries:

- Quote / H1 / Hint: `#BB9AF7`.
- H3: `#2AC3DE`.
- NeotestMarked / DapBreakpointCondition / CodeInline: `#F09A6C`.

The names above abbreviate the existing `RenderMarkdown*` groups where applicable. H1/H3 remain bold, inline code has no background. NeotestMarked inherits bold from the locked Catppuccin integration in both base and E; the runtime check preserves that observed attribute rather than assuming an omitted composed attribute means false. Existing Dx-linked Blink kinds follow E; Keyword/File/Folder kinds retain their neutral UI foreground and are not newly linked to DxKeyword.

## Visual and semantic contracts

- An independent 19-HEX test oracle checks every source value, token closure, 17 distinct colors, and the exact two sharing pairs. No expected colors are copied from the production visual function.
- Existing native link identity, measured foreground, 23-role mapping, 42 sentinels, raw/client-bound tokens, priority and provider contracts remain intact. The M2 manifest, language fixtures, adapters, authority and generic TS/LSP bindings are unchanged.
- Compatible C4.4 contrast, body/prose hierarchy, state isolation and pairing checks remain. Eight contrast ranges now describe E against the actual runtime background. E keyword/function-keyword contrast is 7.298; callable 9.571; type 8.942; namespace 7.435; meta 7.679; number/constant 11.872.
- Type/Builtin's OKLab floor is explicitly rebased from 0.17 to 0.10 (E distance 0.1151). Type/Lifetime distance is only 0.0342: the previous 0.07 SHOULD-SEPARATE requirement is **not met**. Fixed E accepts this proximity; Rust human distinguishability remains to be evaluated. Neither this exception nor intentional sharing changes semantic identity.
- The coarse green-dominance heuristic now also admits E's teal Type (G minus B = 22); builtin/string retain their green requirement. Blue grammar, redward-purple namespace, teal type and orange callable replace the old hue-direction assertions.
- Fourteen visual negative controls require specific error markers. Private policy/pairing checks exercise relational failures independently of the exact-HEX oracle; public verification always runs both. No production bypass flag was added.

## Graph preservation

The graph remains 226 groups. Only the eight approved Dx role foreground fields differ; every other complete group definition is identical to base, including the seven decorative consumers.

```text
E resolved:       44df09042fd6fcb77f4421244a9eb1336c124ce394828cc67e5160cba314c701
M5 C4.4 resolved: 51cfaae3c02ec25551f1a8afd27427d3919d6b53c3b05f5ae26ff6c125aa6666
```

The unit test rolls back exactly eight role foregrounds and must reconstruct the complete M5 digest, then runs the existing historical graph checks unchanged. This rejects link, group, background and style-authority drift rather than normalizing those contracts away. The four existing graph negative controls and batch-1 same-RGB wrong-link controls remain.

## Execution and remaining gates

Local validation uses isolated config/state/cache, the exact base's 70 pinned plugin copies, and installed tools without an install/update. Versions remain those recorded in batch 1: Neovim 0.12.5, clangd 23.1.1, rust-analyzer `9074e9b4c6`, Zig/ZLS 0.16.0, Ty 0.0.80, Ruff 0.16.7, rustc/cargo 1.98.1. Installed parser binaries are reused; this is not a new empty-XDG provisioning claim.

- Unit, 14 visual negative controls, shared-color identity controls, graph and historical reconstruction: PASS.
- Strict C/C++/Rust/Zig/Python runtime and 23-role actual visual/style checks against resolved Normal background: PASS.
- Seven UI runtime foreground/style checks and sixteen Dx-linked Blink kinds: PASS. Separate base/E process observations of the seven UI groups are identical.
- M2A 28/28 cases + 15/15 comparisons; M2B 7/7; M2B-B 13/13: PASS.
- Python ownership and raw Ty token → same Neovim client ID → actual DxVariable foreground: PASS. Installed Pyright remains disabled/unattached; Ty + Ruff attach, Ty alone produces semantic tokens.
- Five-language compiler fixture validation: PASS. Zig cache is temporary; no toolchain update.
- Process-only same-RGB wrong-link injections for function-keyword and number: both rejected by the real color runtime with exit 1 and `DX_IDENTITY_MISMATCH`.
- Process-only Markdown H1 borrowing E keyword blue again: rejected by the actual visual runtime with exit 1 and `E_UI_PRESERVATION`.
- StyLua, ShellCheck/shfmt for the touched Lifecycle entrypoint, diff checks and secret scan: PASS. All 70 plugin checkouts and the isolated config lock match the committed lock.

Remote Validate / Locked Cold Start / double Lifecycle are PR gates, not preclaimed successes. Actual macOS screenshot review is **PENDING**, not replaced by headless checks or browser drawings. Reuse the existing C++ `PacketDecoder`/`BindingProbe`, Rust imports/`FrameReader`/`fetch_stream`, Zig `NetworkBuffer`, Python `DownloadSummary`, C `Buffer`, and Markdown fixture. Hold font, size, background and viewport constant; include completion, diagnostics, search/selection and stopped-line contexts. No new visual comfort or state-overlay acceptance is claimed here.

Stop at this PR for review. Merge, daily activation and any third-batch semantic change remain separate decisions.
