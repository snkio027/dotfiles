# Orange calls / violet paths / blue grammar — local trial

This supersedes the rejected Quiet Code direction, without layering any of its gray palette or UI changes onto C4.4. It is a visual candidate, not a production default or an acceptance result.

Only four palette entries change: `callable = #FFAD66`, `namespace = #C792EA`, `keyword = #6CA6FF`, `keyword_function = #6CA6FF`. Type remains cyan `#2AC3DE`, member pink `#F29BC1`, number `#F09A6C`, and background `#1A1B2A`. All other palette entries, state colors, styles, semantic roles, bindings and providers remain unchanged. Existing consumers of `code.keyword` (Markdown quote, H1 and Hint) also turn blue; no plugin mapping is changed.

From an existing terminal:

```sh
/path/to/experiments/orange-blue/nvim /path/to/project/file.cpp
```

The launcher copies daily Neovim config/lock into a temporary directory and isolates cache, state and logs; it shares installed plugins/Mason and invokes no updater or installer. It is not a filesystem sandbox: normal editing can write project files and plugins retain their capabilities. Neovim-launched subprocesses inherit the temporary XDG directories. Run directories are retained as `dotfiles-orange-blue.*` for inspection.

Use ordinary `nvim` for the original C4.4 comparison. Font, weight, Ghostty settings and 17.5 size are untouched. Compare real Rust imports/call chains and C++ blue keywords next to cyan types. Numbers intentionally stay unchanged; report a collision before changing them.

Local check, from the repository root:

```sh
./experiments/orange-blue/nvim --headless \
  '+luafile tests/nvim/run_contract.lua' experiments/orange-blue/check.lua
```

The check asserts the exact four-value palette delta, rejects a fifth mutation, checks all 226 graph definitions and their applied direct colors/links, and preserves 23 roles. This is not the full M2 token-provenance suite or human visual acceptance. The existing production numerical/pairing contracts are intentionally unchanged and are tested only with production C4.4. Its binding evidence still assumes unique foreground-to-role lookup, which is incompatible with intentionally shared keyword/function-keyword blue; production adoption would require separately reviewed evidence changes.
