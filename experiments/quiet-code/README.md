# Quiet Code — local visual candidate

Cold-gray reading body, cyan types, gold calls, violet grammar, and muted green strings. The 19 source roles retain their semantic identities while using 13 foreground colors. Values follow the approved trial proposal; `ui.focus` explicitly uses the same warm-gold family, independently of `code.member`.

This is an isolated experiment, **not a replacement for production C4.4 or a human-acceptance result**. Nothing under `home/` or the frozen visual contracts is changed. Normal Neovim keeps the production profile.

From an existing terminal, open the same real project file with:

```sh
/path/to/experiments/quiet-code/nvim /path/to/project/file.cpp
```

The launcher copies the daily Neovim config and its lock into a fresh temporary config directory. Compiled colors, logs, state, and cache are isolated; installed plugins and Mason tools are shared. It does not invoke an updater or install additional plugins. It is not a filesystem sandbox: normal editor operations can still write project files, and configured plugins retain their usual capabilities. Temporary run directories are retained under `dotfiles-quiet-code.*` for inspection.

Exit the preview and use ordinary `nvim` to return to C4.4. Font, font weight, Ghostty settings, and the 17.5 font size are untouched. The terminal title identifies the preview.

Local checks (replace the repository path as appropriate):

```sh
./experiments/quiet-code/nvim --headless \
  '+luafile tests/nvim/run_contract.lua' experiments/quiet-code/check.lua
```

This check validates resolved colors/background, source contrast, all 23 roles and 226 group names, unchanged semantic/authority definitions and styles, preserved state colors, and the focus/selection/debugging treatment. It does not measure display rendering, comfort, fatigue, or final selection compositing. Check those visually on real C++/Rust code, member-heavy expressions, types, comments, diagnostics, and Visual selection. The existing C4.4 numerical visual contract is intentionally not applied to this different candidate, and is neither edited nor relaxed.

The existing `binding_evidence.lua` was also attempted, but stops at `zig.binding.top_level_const`: its foreground-to-role reverse lookup expects a unique role, while this candidate intentionally assigns the same foreground to `DxVariable` and `DxParameter`. This is **not a full M2 PASS**. The preview check separately verifies their distinct resolved highlight links and compares all semantic/authority definitions against the unchanged baseline. Replacing the color-uniqueness assumption with identity-plus-foreground evidence belongs to a separately reviewed production-adoption change, not this preview.
