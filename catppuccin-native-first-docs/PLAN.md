# Catppuccin native-first evaluation plan

Status: E1 implementation baseline. Production remains M5/C4.4.

## Goal

Evaluate whether a complete native Catppuccin flavour is preferable to the
current full C4.4 visual projection. Keep only evidence-backed corrections if a
native candidate is later selected.

## E1 cases

- `m5`: stable C4.4 control.
- `native-mocha`: native Catppuccin Mocha plus the registered UX options.
- `native-macchiato`: native Catppuccin Macchiato plus the same UX options.
- `native-frappe`: native Catppuccin Frappé plus the same UX options.

Every case starts in a separate Neovim process with private config, state and
cache roots. The locked plugin, parser and Mason download trees may be reused as
read-only experimental inputs. Native cases remove the production
`custom_highlights` callback; they retain the same integrations, LSP styles,
provider configuration, fixtures and toolchain.

## Evidence boundary

The harness proves startup health, path isolation, flavour and `Normal`
resolution, parser/query availability, provider attachment, raw
`semanticTokens/full` decoding, client-ID-bound Neovim tokens, applied groups,
priorities and final resolved attributes across five languages.

`HARNESS PASS` is not a policy or visual verdict. Native observations are not
required to reproduce M5 `Dx*` groups or C4.4 HEX values. Human comparison owns
candidate selection.

## Non-goals

E1 does not change production theme entry, palette, bindings, adapters,
authority, providers or lockfiles. It does not implement Thin DX, add a runtime
theme selector, upgrade tools, clean user caches, apply dotfiles or authorize a
production switch.

## Workflow

Run all four headless evidence cases:

```bash
bash tests/nvim/native_first/evaluate.sh /tmp/catppuccin-native-first-e1
```

Open one isolated visual preview:

```bash
bash tests/nvim/native_first/run_case.sh native-macchiato --preview path/to/file
```

Accepted preview case names are `m5`, `native-mocha`, `native-macchiato` and
`native-frappe`.
