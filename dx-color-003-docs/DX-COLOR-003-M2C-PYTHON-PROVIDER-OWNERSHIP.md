# DX-COLOR-003 — M2C-A Python Provider Ownership

<!-- markdownlint-disable MD013 -->

- **Milestone:** M2C-A / evidence and ownership classification only
- **Base:** `21ba070d713d4f2275f44222c177de5c3a88b4ac`
- **Language:** Python
- **Production behavior delta:** none
- **Decision:** `ADOPT TY AS INTERACTIVE SEMANTIC PROVIDER`

## Repository intent

The repository currently declares:

```text
Pyright = interactive LSP
Ruff    = lint/code-action companion
Ty      = CLI-only, invoked on demand by <leader>cT -> ty check
```

`options.lua` selects Pyright and Ruff for LazyVim's Python extra.
`python.lua` configures Pyright but contains no Ty server entry. `toolchain.lua`
installs Ty through Mason and documents it as an on-demand whole-project check.

The observed runtime does not implement that intent.

## Activation provenance

The complete activation path is:

```text
toolchain.lua
  Mason ensure_installed contains ty exactly once
        |
        v
Mason registry
  package ty is installed and has a valid receipt/executable
        |
        v
mason-lspconfig mapping table
  Mason package ty -> nvim-lspconfig server ty
        |
        v
LazyVim nvim-lspconfig setup
  explicit servers: Pyright enabled, Ruff enabled, Ty absent
  constructs mason-lspconfig automatic_enable.exclude
        |
        v
mason-lspconfig automatic_enable
  Ty is installed and is not excluded
        |
        v
vim.lsp.enable("ty")
  caller: mason-lspconfig/features/automatic_enable.lua
        |
        v
native enabled config: ty = true
        |
        v
Python FileType
  Pyright + Ruff + Ty attach
```

The locked implementation under observation is:

| Component | Commit |
| --- | --- |
| LazyVim | `c10948c50b18fae7f256433afdef09e432410480` |
| mason-lspconfig.nvim | `40276c4df7e6bdce6801d6c035c6227f9115a855` |
| nvim-lspconfig | `16286347bdba1333c7d124d9de9fe6630731b2b2` |

The pre-init test trace wraps the native `vim.lsp.enable()` API before the
production init runs. It records Ty's call site inside mason-lspconfig's
automatic-enable feature rather than inferring activation from attachment.

## State model

The evidence keeps each lifecycle state distinct:

| State | Production observation |
| --- | --- |
| Installed | Mason package and executable present |
| Configured | Ty absent from explicit LazyVim `servers`; nvim-lspconfig supplies the mapped config |
| Enabled | `vim.lsp.is_enabled("ty") == true` |
| Attached | Ty attached to the Python fixture |
| Semantic-token producer | Ty is the only attached client advertising semantic tokens |
| Foreground authority | Generic `@lsp.type.variable.python -> DxVariable`, not Ty-specific policy |

Pyright and Ruff attach as explicitly selected clients. Neither advertises
semantic tokens in the observed configuration. Ty's direct
`textDocument/semanticTokens/full` response for the module-binding sentinel is
decoded against Ty's negotiated legend, attributed to Ty's client ID, and
required to match Neovim's applied token exactly.

## Interactive capability evidence

The current negotiated capabilities are:

| Provider | Completion | Hover | Definition | References | Rename | Code action | Semantic tokens |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Pyright | yes | yes | yes | yes | yes | yes | no |
| Ruff | no | no | no | no | no | yes | no |
| Ty | yes | yes | yes | yes | yes | yes | yes |

Ty therefore exposes the core interactive capabilities presently expected
from Pyright and is already the only semantic-token producer. This is runtime
capability evidence, not a claim that every behavior is feature-identical.

## Test-only exclusion experiment

The negative control copies the production Neovim configuration to a temporary
`XDG_CONFIG_HOME` and adds exactly one test-only LazyVim override:

```lua
servers = {
  ty = { enabled = false },
}
```

No repository-managed production config is changed. The result is:

```text
Production                 Ty-excluded control

Pyright enabled/attached   Pyright enabled/attached
Ruff enabled/attached      Ruff enabled/attached
Ty enabled/attached        Ty disabled/not attached
Ty semantic producer       no semantic-token producer
```

The shell contract compares both process reports. The effective
`automatic_enable.exclude` set may differ only by `ty`; Pyright and Ruff's
enabled state and capability topology must remain identical. The observation
does not install, update, or remove Mason packages.

This proves the strong hypothesis: Ty's unexpected attachment is caused by
the installed-package automatic-enable path. It is not required by Pyright,
Ruff, the fixture, or a hidden production Ty server configuration.

## Governance result

The proposition:

> Installation does not imply activation.

is false as a description of the current stack. Under the locked
mason-lspconfig behavior, installing an LSP package implies activation unless
it is excluded.

The supported governance invariant is:

> **Interactive LSP ownership must be explicit.**

Installation and activation are separate policy decisions even when a plugin
offers convenient automatic enablement.

## Decision

```text
ADOPT TY AS INTERACTIVE SEMANTIC PROVIDER
```

The decision combines three facts:

1. the user prefers Ty for the interactive Python experience;
2. Ty already exposes the required interactive capability surface;
3. Ty already owns all observed Python semantic-token production.

M2C-A does not implement the decision. A separate M2C-B must explicitly define
the production topology, prevent duplicate primary-LSP ownership, and preserve
Ruff as the lint/code-action companion. The expected candidate is Ty as the
primary interactive provider, Ruff as companion, and Pyright disabled; that
behavior requires its own runtime and regression review.

## Preserved contracts

```text
DX roles                         23 / unchanged
semantic rendering sentinels     42 / unchanged
M2A evidence                     28/28 + 15/15 / preserved
M2B evidence and correction      preserved
M2B-B graph                      225 / a2db03bf... / unchanged
M1 historical graph              221 / 05ff81df... / reconstructable
Catppuccin / visual profile      Mocha / C3.1 / unchanged
DxModuleBinding                  DEFERRED
C4                               NOT STARTED
plugin/tool versions             unchanged
```

## Reproduction

```bash
nvim -u NONE -i NONE --headless \
  "+set rtp^=$PWD/home/dot_config/nvim" \
  "+luafile tests/nvim/python_provider_ownership_contract.lua" +qa

bash tests/nvim/python_provider_ownership.sh

bash tests/nvim/cold_start.sh
```

The Dev Container lifecycle runs the same production and test-only exclusion
experiment after provisioning and requires both completion markers.
