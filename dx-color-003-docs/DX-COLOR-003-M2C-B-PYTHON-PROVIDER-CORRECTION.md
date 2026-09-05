# DX-COLOR-003 M2C-B — Explicit Python Provider Ownership

<!-- markdownlint-disable MD013 -->

- **Milestone:** M2C-B / narrow behavior correction
- **Base:** `5822ddd8982680912484c3aa6dfd661cca59e634`
- **Approved M2C-A decision:** `ADOPT TY AS INTERACTIVE SEMANTIC PROVIDER`
- **Theme graph delta:** none
- **Plugin / tool delta:** none

## Production decision

```text
Ty = primary interactive Python LSP
Ruff = lint/fix/code-action companion
Pyright = installed rollback asset; explicitly disabled
```

M2C-A proved that installing Ty through Mason previously allowed
`mason-lspconfig` automatic enable to attach it even though repository intent
still selected Pyright. M2C-B removes that ownership mismatch through LazyVim's
existing selection seam:

```lua
vim.g.lazyvim_python_lsp = "ty"
vim.g.lazyvim_python_ruff = "ruff"
```

No custom activation or provider-arbitration framework is introduced. The
locked LazyVim Python extra expands this declaration into explicit server
state: Ty and Ruff are enabled, while Pyright is disabled and therefore placed
in the `mason-lspconfig` automatic-enable exclusion set.

## Installation is not activation

Mason continues to own all three packages:

```text
Installed
  ty       true
  ruff     true
  pyright  true

Enabled
  ty       true
  ruff     true
  pyright  false

Attached to a Python buffer
  ty
  ruff
```

Pyright remains in the versioned tool inventory and its dormant settings stay
available as a rollback asset. It receives no native enable call and cannot
attach under the M2C-B production contract. Returning to Pyright is an explicit
future ownership decision, not an incidental consequence of installation.

The `<leader>cT` `ty check` action remains useful. Whole-project CLI checking
and interactive LSP ownership are compatible responsibilities.

## Capability ownership

Runtime evidence must derive ownership from the capabilities negotiated by the
clients attached to the same Python fixture:

| Capability | Ty | Ruff | Owner |
| --- | --- | --- | --- |
| completion | yes | no | Ty only |
| hover | yes | no | Ty only |
| definition | yes | no | Ty only |
| references | yes | no | Ty only |
| rename | yes | no | Ty only |
| semantic tokens | yes | no | Ty only |
| code action | yes | yes | shared; Ruff remains the lint/fix companion |

Pyright is excluded from the attached-client capability matrix because its
required runtime state is disabled and unattached.

## Semantic-token provenance

The existing Ty probe remains client-ID-bound and fail-closed:

```text
direct textDocument/semanticTokens/full request to Ty
  -> decode with Ty's negotiated legend
  -> variable + definition

Neovim semantic-token subsystem
  -> same Ty client ID
  -> same decoded token
  -> @lsp.type.variable.python
  -> DxVariable foreground
```

Ruff must not advertise semantic tokens, and the complete producer set must be
exactly `ty`. Any Pyright attachment, Pyright enable call, second semantic
producer, or loss of Ty's primary capabilities fails the runtime contract.

## Preserved contracts

```text
DX roles                         23 / unchanged
semantic rendering sentinels     42 / unchanged
M2A evidence                     28/28 + 15/15 / preserved
M2B-A evidence                   7/7 / preserved
M2B-B behavior evidence          13/13 / preserved

M2B-B graph                      225
M2B-B graph SHA-256              a2db03bf6a138c0784d74277adf6f7ee706a5398336305385ced7d3725c0dedf

M1 historical graph              221
M1 historical SHA-256            05ff81df9019ace7bee14a494db1a9e39c7d18426f3b78bae1ef3012a068a276

Catppuccin / visual profile      Mocha / C3.1 / unchanged
DxModuleBinding                  DEFERRED
C4                               NOT STARTED
```

The frozen M2C-A evidence record remains the pre-correction provenance and
decision snapshot. This document records the separate production behavior
change that makes declared ownership and runtime topology agree.
