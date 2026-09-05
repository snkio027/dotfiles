# DX-COLOR-003 M3-C — Explicit C4 Opt-In Selector

<!-- markdownlint-disable MD013 -->

- **Milestone:** M3-C / runtime profile selection
- **Base:** `433a2b164fe4a6f4810fbf7c3c7f09b34bdb7c60`
- **Default profile:** `c3_1`, unchanged
- **Opt-in profile:** `c4`
- **Palette / semantic / authority / provider delta:** none

## Selection contract

The explicit production override is the single Neovim global:

```lua
vim.g.dx_color_profile = "c4"
```

The global is otherwise left unset. `theme.default_profile` is the sole owner
of the managed default and remains `c3_1` in M3-C.

The theme entry point accepts exactly:

```text
c3_1
c4
```

An unset selector resolves to `c3_1`. An unknown, empty, or non-string value
fails with an error naming the accepted profiles; it never silently selects a
different profile.

The selector is evaluated when Catppuccin composes `custom_highlights` during
startup. It is intentionally not a live theme-switching framework.

## Opt-in and rollback

A controlled C4 trial may preselect the profile before startup:

```bash
nvim --cmd "let g:dx_color_profile='c4'"
```

The explicit compatibility selection is:

```bash
nvim --cmd "let g:dx_color_profile='c3_1'"
```

Because `options.lua` does not assign the selector, both explicit forms are
preserved verbatim and validated by the theme entry point. Without an override,
`theme.default_profile` resolves production to C3.1.

Changing the managed default is not part of M3-C. M5 owns any default switch.

## Runtime evidence

Three separate production Neovim processes prove:

```text
unset/default selector       -> c3_1
explicit c4 opt-in           -> c4
explicit c3_1 opt-out        -> c3_1
```

They distinguish the requested state from the resolved state:

```text
default    raw override = nil    resolved profile = c3_1
opt-in     raw override = c4     resolved profile = c4
opt-out    raw override = c3_1   resolved profile = c3_1
```

A fourth production process supplies the invalid non-string override `false`
and must exit nonzero with an error naming `c3_1` and `c4` as the accepted
profiles.

Each process verifies all 23 resolved `Dx*` roles and representative
Tree-sitter/LSP links against the selected visual profile.

The C4 process additionally obtains the actual resolved `Normal.bg` from the
active Catppuccin colorscheme and evaluates the frozen C4 visual contract using
that runtime background. This closes the M3-B composition proof without
assuming that the planned Mocha Base value is the active background.

The Locked Cold Start and Dev Container Lifecycle lanes run all three successful
modes and the expected-failure `false` control.
The lifecycle contract requires distinct completion markers for default,
opt-in, opt-out, invalid-selector rejection, and actual-background C4 contrast
validation.

## Unit evidence

The selector unit contract proves:

- unset selection resolves to the frozen C3.1 graph;
- explicit `c3_1` resolves to the same graph;
- explicit `c4` resolves to the frozen C4.0 graph;
- empty, case-mismatched, unknown, numeric, `false`, and `true` values fail
  closed.

The resolved graph oracles remain:

```text
C3.1 count       225
C3.1 SHA-256     a2db03bf6a138c0784d74277adf6f7ee706a5398336305385ced7d3725c0dedf

C4.0 count       225
C4.0 SHA-256     311ac3566f816d0fc03ad4ec92c74477d4ac82bf8cc2ab5cd82f95a12688c043
```

The historical M1 oracle remains `221 / 05ff81df...`; no group, link,
authority, adapter, provider, or style topology changed.

## Preserved boundaries

```text
C4 palette and visual profile     frozen from M3-B
C3.1 runtime default              unchanged
DX roles                          23 / unchanged
semantic sentinels                42 / unchanged
M2 evidence and corrections       preserved
Python provider ownership         Ty + Ruff / unchanged
DxModuleBinding                   DEFERRED / FROZEN
plugin and tool versions          unchanged
```

M3-C makes C4.0 selectable; it does not approve its visual comfort. M4 owns the
human A/B verdict, and M5 owns any default switch or C3.1 retirement.
