# DX-COLOR-004 M0/M1 — Storm Host Prototype

Status: **implementation candidate; review required**

Base: `f0202dcfea71d9dc8b84ef18eb02f5fb42344f20`

## M0 decision and scope freeze

Real A/B use established TokyoNight Storm as the preferred visual system.
DX-COLOR-004 therefore changes the visual host while preserving the semantic
architecture released by DX-COLOR-003.

The historical baseline remains immutable:

```text
DX-COLOR-003 M5 graph
226 groups
51cfaae3c02ec25551f1a8afd27427d3919d6b53c3b05f5ae26ff6c125aa6666
```

This milestone does not reinterpret or rewrite that release. It starts a new
provenance line from the exact M5 merge commit.

### Ownership contract

```text
TokyoNight Storm owns
  Normal and editor surfaces
  CursorLine, gutter, floats, menus, and selection
  diagnostics presentation
  completion and plugin UI

DX owns
  23-role Semantic Domain
  Tree-sitter and LSP bindings
  provider adapters
  semantic foreground authority and suppression
  deprecated presentation-style authority
```

Diagnostics remain a shared invariant: TokyoNight chooses their presentation,
while DX verifies severity and non-color cues without claiming diagnostic HEX
ownership.

### Non-goals

- no new semantic role or `DxModuleBinding` work;
- no binding, provider, or LSP ownership change;
- no language-specific palette;
- no runtime selector or live theme switching;
- no unrelated plugin or tool upgrade;
- no local `chezmoi apply`;
- no M2, M3, M4, or M5 work.

## M1 implementation

TokyoNight Storm becomes the candidate runtime host. Its official named color
table is projected into the existing DX roles; this milestone does not invent
a second palette of raw HEX values.

The active composition contains only:

```text
authority base
→ visual roles
→ generic Tree-sitter bindings
→ generic LSP bindings
→ ZLS adapter
→ clangd adapter
→ rust-analyzer adapter
→ Pyright adapter
```

The former DX UI and plugin layers are deliberately absent from the active
composition so TokyoNight can own those surfaces. Their files are retained for
the later M3 ownership audit rather than deleted during the prototype.

### Host semantic-token sanitization

TokyoNight includes its own LSP semantic-token foreground rules. Allowing
those rules to coexist with the governed DX graph would create competing
foreground authorities—for example, a host `defaultLibrary` typemod can
override the DX classification of a C primitive type.

The theme hook therefore removes host `@lsp.*` entries that are outside the DX
overlay before installing that overlay. It retains
`@lsp.type.unresolvedReference`, whose undercurl is a non-color error cue rather
than a source-semantic foreground owner.

This is not a copy of TokyoNight's semantic taxonomy. It is the boundary that
lets TokyoNight own the visual host while DX remains the sole semantic-token
foreground authority.

## Graph governance

The M1 Storm overlay is frozen independently as:

```text
152 groups
81d6f18ac0b493b26924e30d3506c604dcb8cb0900d7e36b040482608184ab30
```

The smaller count is intentional: editor surfaces and plugin integrations are
now host-owned rather than copied into the DX overlay.

The tests also reconstruct the historical M5 graph from its semantic layers,
historical palette, and historical UI/plugin bindings, and require the exact
frozen result:

```text
226 groups
51cfaae3c02ec25551f1a8afd27427d3919d6b53c3b05f5ae26ff6c125aa6666
```

All older graph-provenance checkpoints remain intact. The Storm oracle is a new
candidate oracle, not a replacement for the historical release evidence.

## Runtime evidence contract

The local and remote gates must prove:

- the active colorscheme is exactly `tokyonight-storm`;
- all 23 DX roles resolve from TokyoNight's named Storm palette;
- representative Tree-sitter and LSP evidence still reaches the intended DX
  role;
- actual `Normal`, `CursorLine`, gutter, float, menu, diagnostic, and plugin UI
  values come from TokyoNight;
- the DX overlay contains no host-owned UI or plugin groups;
- diagnostic error presentation retains a non-color cue;
- raw/client-bound M2 semantic evidence and all M2 classification contracts
  remain valid;
- no current or historical graph oracle drifts silently.

Visual harmony is not approved by automation. M1 only proves a viable Storm
host prototype. Palette alignment and human A/B authority remain in M2 and M4.

## Milestone result

```text
M0 scope and ownership freeze       implemented
M1 Storm host prototype             implemented
23-role Domain                      preserved
Tree-sitter/LSP/adapters/authority  preserved
M2 evidence                         preserved
DX-COLOR-003 M5 provenance          preserved
M2+                                 not started
```

This record becomes frozen only after substantive review, remote CI, and merge.
