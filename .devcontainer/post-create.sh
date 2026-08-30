#!/usr/bin/env bash

set -euo pipefail

WORKSPACE_FOLDER="${1:?workspace folder is required}"
LINUXBREW_PREFIX="/home/linuxbrew/.linuxbrew"

if [[ "$(id -un)" == "root" ]]; then
    echo "Dev Container provisioning must run as the configured non-root user" >&2
    exit 1
fi
if [[ ! -f "$WORKSPACE_FOLDER/.chezmoiroot" ]]; then
    echo "Dotfiles source is unavailable: $WORKSPACE_FOLDER" >&2
    exit 1
fi

# Keep the fixed Linuxbrew location visible before the first apply. The
# bootstrap script may create this prefix, and every later chezmoi script then
# discovers the newly installed brew binary in the same parent environment.
export HOMEBREW_PREFIX="$LINUXBREW_PREFIX"
export HOMEBREW_CELLAR="$LINUXBREW_PREFIX/Cellar"
export HOMEBREW_REPOSITORY="$LINUXBREW_PREFIX"
export PATH="$LINUXBREW_PREFIX/opt/llvm/bin:$LINUXBREW_PREFIX/bin:$LINUXBREW_PREFIX/sbin:$HOME/.local/bin:$PATH"

export CHEZMOI_PROFILE="devcontainer"
export GIT_AUTHOR_NAME="${GIT_AUTHOR_NAME:-Dev Container}"
export GIT_AUTHOR_EMAIL="${GIT_AUTHOR_EMAIL:-devcontainer@localhost}"

for attempt in 1 2 3; do
    if chezmoi init --apply --source="$WORKSPACE_FOLDER"; then
        break
    fi
    if [[ "$attempt" -eq 3 ]]; then
        echo "Dev Container chezmoi provisioning failed after 3 attempts" >&2
        exit 1
    fi
    echo "Dev Container provisioning retry $attempt/3 after a transient failure" >&2
    sleep "$((attempt * 2))"
done

# Restore the committed plugin graph and provision only missing Mason tools.
# Updates remain explicit through devup and rolling-latest CI.
export DOTFILES_LAZY_LOCK_SNAPSHOT="$WORKSPACE_FOLDER/home/dot_config/nvim/lazy-lock.json"
nvim --headless \
    "+luafile $WORKSPACE_FOLDER/tests/nvim/restore_lock.lua" \
    "+Lazy! restore" \
    "+MasonToolsInstallSync" +qa
cmp "$HOME/.config/nvim/lazy-lock.json" "$DOTFILES_LAZY_LOCK_SNAPSHOT"
