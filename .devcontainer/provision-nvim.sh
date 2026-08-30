#!/usr/bin/env bash

set -euo pipefail

WORKSPACE_FOLDER="${1:?workspace folder is required}"
NVIM_BIN="${DOTFILES_NVIM_BIN:-nvim}"
MAX_ATTEMPTS="${DOTFILES_NVIM_PROVISION_ATTEMPTS:-3}"
TIMEOUT_MS="${DOTFILES_MASON_TIMEOUT_MS:-300000}"
RETRY_DELAY_SECONDS="${DOTFILES_NVIM_PROVISION_RETRY_DELAY_SECONDS:-2}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
MANIFEST="$STATE_HOME/dotfiles/mason-tools.txt"
LOCK_SNAPSHOT="$WORKSPACE_FOLDER/home/dot_config/nvim/lazy-lock.json"
LOG_ROOT="$(mktemp -d)"
export DOTFILES_LAZY_LOCK_SNAPSHOT="$LOCK_SNAPSHOT"

cleanup() {
    rm -rf -- "$LOG_ROOT"
}
trap cleanup EXIT

fail() {
    echo "$1" >&2
    exit 1
}

[[ -x "$(command -v "$NVIM_BIN" 2>/dev/null || true)" ]] || fail "Neovim executable is unavailable: $NVIM_BIN"
[[ -f "$LOCK_SNAPSHOT" ]] || fail "Committed Neovim lock snapshot is unavailable: $LOCK_SNAPSHOT"
[[ "$MAX_ATTEMPTS" =~ ^[1-9][0-9]*$ ]] || fail "Invalid Neovim provisioning attempt count: $MAX_ATTEMPTS"
[[ "$TIMEOUT_MS" =~ ^[1-9][0-9]*$ ]] || fail "Invalid Mason timeout: $TIMEOUT_MS"
[[ "$RETRY_DELAY_SECONDS" =~ ^[0-9]+$ ]] || fail "Invalid Neovim provisioning retry delay: $RETRY_DELAY_SECONDS"

for ((attempt = 1; attempt <= MAX_ATTEMPTS; attempt++)); do
    log_file="$LOG_ROOT/attempt-$attempt.log"
    printf 'post-create Neovim provisioning attempt %d/%d\n' "$attempt" "$MAX_ATTEMPTS"

    if DOTFILES_MASON_TIMEOUT_MS="$TIMEOUT_MS" "$NVIM_BIN" --headless \
        "+luafile $WORKSPACE_FOLDER/tests/nvim/restore_lock.lua" \
        "+Lazy! restore" \
        "+luafile $WORKSPACE_FOLDER/tests/nvim/provision.lua" +qa \
        >"$log_file" 2>&1; then
        completion="$(grep -E '^Mason missing-tool provisioning [0-9]+/[0-9]+$' "$log_file" | tail -n 1 || true)"
        required="$(grep -E '^Mason required tools: [a-z0-9._,-]+$' "$log_file" | tail -n 1 || true)"
        if [[ -n "$completion" && -n "$required" ]] && ! grep -Eqi 'Error in command line|Timed out waiting for Mason tools' "$log_file"; then
            tool_csv="${required#Mason required tools: }"
            counts="${completion##* }"
            installed_count="${counts%/*}"
            expected_count="${counts#*/}"
            tr ',' '\n' <<<"$tool_csv" | sort -u >"$LOG_ROOT/mason-tools.txt"
            manifest_count="$(wc -l <"$LOG_ROOT/mason-tools.txt" | tr -d ' ')"
            if [[ "$installed_count" -eq "$expected_count" && "$manifest_count" -eq "$expected_count" ]]; then
                cmp "$HOME/.config/nvim/lazy-lock.json" "$LOCK_SNAPSHOT"
                mkdir -p "$(dirname "$MANIFEST")"
                mv "$LOG_ROOT/mason-tools.txt" "$MANIFEST"
                printf 'required tools complete: %s\n' "${completion##* }"
                printf 'post-create Neovim provisioning complete\n'
                exit 0
            fi
            echo "Mason completion marker and required-tool manifest disagree" >>"$log_file"
        fi
    fi

    cat "$log_file" >&2
    if [[ "$attempt" -eq "$MAX_ATTEMPTS" ]]; then
        fail "Dev Container Neovim provisioning failed after $MAX_ATTEMPTS attempts"
    fi
    printf 'post-create Neovim provisioning retry %d/%d after a transient failure\n' \
        "$attempt" "$MAX_ATTEMPTS" >&2
    sleep "$RETRY_DELAY_SECONDS"
done
