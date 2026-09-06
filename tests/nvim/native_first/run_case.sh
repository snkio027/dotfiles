#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CASE="${1:-}"
MODE="${2:---headless}"
TARGET="${3:-$REPO_ROOT/tests/nvim/color/cpp/src/main.cpp}"

case "$CASE" in
    m5 | native-mocha | native-macchiato | native-frappe) ;;
    *)
        echo "usage: $0 {m5|native-mocha|native-macchiato|native-frappe} [--headless|--preview] [file]" >&2
        exit 2
        ;;
esac

case "$MODE" in
    --headless | --preview) ;;
    *)
        echo "unsupported mode: $MODE" >&2
        exit 2
        ;;
esac

RUN_ROOT="${DOTFILES_NATIVE_FIRST_RUN_ROOT:-$(mktemp -d)}"
KEEP_ROOT="${DOTFILES_NATIVE_FIRST_KEEP_ROOT:-0}"
if [ -z "${DOTFILES_NATIVE_FIRST_RUN_ROOT:-}" ] && [ "$KEEP_ROOT" != "1" ]; then
    trap 'rm -rf -- "$RUN_ROOT"' EXIT
fi

CONFIG_PARENT="$RUN_ROOT/config"
DATA_PARENT="$RUN_ROOT/data"
STATE_PARENT="$RUN_ROOT/state"
CACHE_PARENT="$RUN_ROOT/cache"
CONFIG_ROOT="$CONFIG_PARENT/nvim"
DATA_ROOT="$DATA_PARENT/nvim"
SEED_DATA="${DOTFILES_NATIVE_FIRST_SEED_DATA:-${XDG_DATA_HOME:-$HOME/.local/share}/nvim}"

mkdir -p "$CONFIG_ROOT" "$DATA_ROOT" "$STATE_PARENT/nvim" "$CACHE_PARENT"
cp -R "$REPO_ROOT/home/dot_config/nvim/." "$CONFIG_ROOT/"

for component in lazy mason site; do
    if [ ! -e "$SEED_DATA/$component" ]; then
        echo "validated Neovim data seed is missing: $SEED_DATA/$component" >&2
        exit 1
    fi
    ln -s "$SEED_DATA/$component" "$DATA_ROOT/$component"
done

if [ "$CASE" != "m5" ]; then
    cp "$REPO_ROOT/tests/nvim/native_first/override.lua" \
        "$CONFIG_ROOT/lua/plugins/zz_native_first_e1.lua"
fi

export XDG_CONFIG_HOME="$CONFIG_PARENT"
export XDG_DATA_HOME="$DATA_PARENT"
export XDG_STATE_HOME="$STATE_PARENT"
export XDG_CACHE_HOME="$CACHE_PARENT"
export DOTFILES_NATIVE_FIRST_CASE="$CASE"
export DOTFILES_NATIVE_FIRST_ROOT="$RUN_ROOT"
export DOTFILES_NATIVE_FIRST_SEED_DATA="$SEED_DATA"
export NVIM_LOG_FILE="$STATE_PARENT/nvim/log"
export NVIM_APPNAME="nvim"

cd "$REPO_ROOT"
if [ "$MODE" = "--preview" ]; then
    nvim -n "$TARGET"
else
    : "${DOTFILES_NATIVE_FIRST_OUTPUT:=$RUN_ROOT/$CASE.json}"
    export DOTFILES_NATIVE_FIRST_OUTPUT
    nvim -n --headless "+luafile tests/nvim/native_first/observe.lua" +qa
fi
