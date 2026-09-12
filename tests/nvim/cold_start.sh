#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_ROOT="${DOTFILES_COLD_START_ROOT:-$(mktemp -d)}"
LOG_DIR="$TEST_ROOT/logs"
CONFIG_HOME="$TEST_ROOT/config"
LOCK_SNAPSHOT="$TEST_ROOT/lazy-lock.committed.json"

if [ -z "${DOTFILES_COLD_START_ROOT:-}" ]; then
    trap 'rm -rf -- "$TEST_ROOT"' EXIT
fi

mkdir -p "$LOG_DIR" "$CONFIG_HOME" "$TEST_ROOT/data" "$TEST_ROOT/state" "$TEST_ROOT/cache"
cp -R "$REPO_ROOT/home/dot_config/." "$CONFIG_HOME/"
cp "$REPO_ROOT/home/dot_config/nvim/lazy-lock.json" "$LOCK_SNAPSHOT"

export XDG_CONFIG_HOME="$CONFIG_HOME"
export XDG_DATA_HOME="$TEST_ROOT/data"
export XDG_STATE_HOME="$TEST_ROOT/state"
export XDG_CACHE_HOME="$TEST_ROOT/cache"
export DOTFILES_LAZY_LOCK_SNAPSHOT="$LOCK_SNAPSHOT"
export DOTFILES_MASON_TIMEOUT_MS="${DOTFILES_MASON_TIMEOUT_MS:-900000}"

run_nvim() {
    local label="$1"
    shift
    printf '\n==> %s\n' "$label"
    if ! nvim --headless "$@" >"$LOG_DIR/$label.log" 2>&1; then
        tail -n 200 "$LOG_DIR/$label.log" >&2
        return 1
    fi
    printf 'completed (log: %s)\n' "$LOG_DIR/$label.log"
}

cd "$REPO_ROOT"
run_nvim lazy-restore "+luafile tests/nvim/restore_lock.lua" "+Lazy! restore" \
    "+luafile tests/nvim/provision.lua" +qa
run_nvim startup-policy "+luafile tests/nvim/startup_policy.lua" +qa
run_nvim color-unit "-n" "+set rtp^=$PWD/home/dot_config/nvim" "+luafile tests/nvim/run_contract.lua" "tests/nvim/color_unit_contract.lua"
run_nvim python-provider-unit "-n" "+set rtp^=$PWD/home/dot_config/nvim" \
    "+luafile tests/nvim/run_contract.lua" "tests/nvim/python_provider_ownership_contract.lua"
run_nvim smoke "+luafile tests/nvim/smoke.lua" +qa
run_nvim color-contract "-n" "+luafile tests/nvim/color_contract.lua" +qa
run_nvim binding-evidence "-n" "+luafile tests/nvim/binding_evidence.lua" +qa
DOTFILES_M2C_CONFIG_HOME="$CONFIG_HOME" DOTFILES_M2C_LOG_DIR="$LOG_DIR" \
    bash tests/nvim/python_provider_ownership.sh

if grep -ERni 'Package is already installing|MasonToolsStartingInstall|MasonToolsUpdateCompleted|^Installing tools:|^Updating tools:' \
    "$LOG_DIR/lazy-restore.log" "$LOG_DIR/startup-policy.log" "$LOG_DIR/smoke.log" \
    "$LOG_DIR/color-unit.log" "$LOG_DIR/python-provider-unit.log" "$LOG_DIR/color-contract.log" \
    "$LOG_DIR/binding-evidence.log" "$LOG_DIR/python-provider-production.log"; then
    echo "Unexpected Mason background installation or update detected" >&2
    exit 1
fi

cmp "$CONFIG_HOME/nvim/lazy-lock.json" "$LOCK_SNAPSHOT"
git diff --exit-code -- home/dot_config/nvim/lazy-lock.json
printf '\nNeovim locked cold-start tests passed\nLogs: %s\n' "$LOG_DIR"
