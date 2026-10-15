# AI workbench trial

Opt-in experiment, not a new daily configuration or an agent platform.
Baseline: dotfiles `1c5ac283b41bb015446f56b64754d9eee3c6bf41`.

## A — One cmux workspace per task

Install `homebrew/cask/cmux` separately; retain Ghostty and do not make cmux the
default terminal. This trial does not add cmux to the workstation Brewfile.
Use a task name such as `elliott.page / Writing browser regression` and open an
editor, one agent entrypoint, and the task's actual run/test output.

In a cmux terminal, enter the task checkout and start Codex explicitly:

```sh
codex --sandbox workspace-write --ask-for-approval on-request
# Later, in the same checkout, select the intended session:
codex resume
```

Keep existing model/authentication settings. Do not use bypass flags. First try
native completion/input notifications; do not install custom hooks. cmux may
restrict its control socket to processes started inside cmux: retain that default,
use the native UI or an in-app terminal, and do not relax it for this trial.

Layout restoration is not process checkpointing. Confirm the checkout and running
services after resuming. A separate terminal Codex and Sidekick's Codex are not
automatically the same session; choose one entrypoint per task, not two writers.

## B — Sidekick CLI-only, isolated Neovim

[`sidekick.lua`](sidekick.lua) is a lazy.nvim plugin spec, deliberately outside
`home/`. It pins the tested upstream revision and adds only:

| Key | Action |
| --- | --- |
| `<Space>aa` | Open/focus Codex |
| `<Space>as` | Draft current file position, or actual selected text in Visual mode |
| `<Space>ad` | Draft current file diagnostics; ask for explanation without edits |

Both send actions use `submit = false`: inspect the draft, add your goal, then
submit yourself. File context requires an existing, named file. Selected edits
need not be saved; ordinary position context is a reference, not an unsaved-buffer
snapshot. No Tab mapping, NES, Copilot LSP, ACP or tmux/zellij integration is added.
Do not enable LazyVim's broader Sidekick extra alongside this spec.

Prepare a new directory with the same XDG separation as `devup`, but **do not run
`devup` or `Lazy update`** for this experiment: they would change the comparison
baseline. Copy source Neovim/neocmakelsp/markdownlint-cli2 configuration into its
`config/`, and copy the existing `lazy`, `mason`, and `site` directories into its
`data/nvim/`. Use real copies, not symlinks or hard links; exclude Git fsmonitor
sockets when copying plugin checkouts. Save the original lock separately.

Copy this spec to the candidate's `config/nvim/lua/plugins/sidekick-trial.lua`,
clone `folke/sidekick.nvim` into its `data/nvim/lazy/sidekick.nvim`, and check out
the full commit in the spec. Start it with:

```sh
# Set candidate to the newly prepared directory, then cd to the task checkout.
env XDG_CONFIG_HOME="$candidate/config" XDG_DATA_HOME="$candidate/data" \
  XDG_STATE_HOME="$candidate/state" XDG_CACHE_HOME="$candidate/cache" \
  NVIM_APPNAME=nvim NVIM_LOG_FILE="$candidate/state/nvim.log" nvim -n -i NONE
```

This isolates Neovim state, not the filesystem or global tools. Copied Mason
packages can retain absolute interpreter paths; the candidate is local and
temporary, not a relocatable distribution. Normal `nvim` remains unchanged.
Quit the candidate to stop using it. No chezmoi apply or initialization script is
needed; adoption remains a separate decision.

From the dotfiles checkout, use the same environment to run:

```sh
nvim --headless \
  '+lua vim.g.dotfiles_contract_file="experiments/ai-workbench/contract.lua"' \
  '+luafile tests/nvim/run_contract.lua'
```

The contract uses real Sidekick rendering, terminal creation and bracketed paste
with a local Python PTY recorder. It checks file position, unsaved selected text,
current-file-only diagnostics, unchanged Tab and no automatic submission. It does
not send an AI request, prove model quality or replace human interaction testing.
Also run the existing completion contract in the candidate and compare all
pre-existing lock entries against the baseline. This optional contract is not
installed or automatically exercised by production CI.

## C — Real feedback, then compare

The first task is Writing browser regression in `elliott.page`: desktop 1440px
and mobile 390px, list → published detail → list, overflow and browser errors,
failure screenshots/diagnostics, repeatable execution and `pnpm quality`.
Frozen content, URLs and visual design remain unchanged. This task is initially
executed by the existing Codex desktop session; do not describe it as evidence of
CLI task completion or cmux notification/resume quality before those are tried.

Record only context transfers, interruptions, review burden and rework during
real use. Leave them unmeasured until observed. No ACP, orchestration, Skill
library, new model, browser MCP or hosted agent platform is part of this trial.

## Sources

- [Codex CLI reference](https://learn.chatgpt.com/docs/cli/reference)
- [cmux with Codex](https://cmux.com/agents/codex)
- [cmux notifications](https://cmux.com/docs/notifications)
- [Sidekick pinned source](https://github.com/folke/sidekick.nvim/tree/3d80a47e6375f6d647c9695d3afea6fa1b3275df)
