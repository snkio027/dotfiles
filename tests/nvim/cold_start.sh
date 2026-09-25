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
export DOTFILES_TREESITTER_TIMEOUT_MS="${DOTFILES_TREESITTER_TIMEOUT_MS:-300000}"

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

run_nvim_expected_failure() {
    local label="$1"
    shift
    local status=0
    printf '\n==> %s (expected failure)\n' "$label"
    nvim --headless "$@" >"$LOG_DIR/$label.log" 2>&1 || status=$?
    if [ "$status" -ne 1 ]; then
        cat "$LOG_DIR/$label.log" >&2
        echo "Expected contract exit 1, got $status: $label" >&2
        return 1
    fi
    printf 'failed as expected with status %d (log: %s)\n' "$status" "$LOG_DIR/$label.log"
}

cd "$REPO_ROOT"
run_nvim lsp-shutdown "-u" "NONE" "-n" "-i" "NONE" \
    "+luafile tests/nvim/run_contract.lua" "tests/nvim/lsp_shutdown_contract.lua"
run_nvim lazy-restore "+luafile tests/nvim/restore_lock.lua" "+Lazy! restore" \
    "+luafile tests/nvim/provision.lua" +qa
grep -Fq "Tree-sitter evidence parser provisioning 5/5: c,cpp,python,rust,zig" \
    "$LOG_DIR/lazy-restore.log" || {
    cat "$LOG_DIR/lazy-restore.log" >&2
    echo "Tree-sitter evidence parser provisioning did not complete" >&2
    exit 1
}
run_nvim startup-policy "+luafile tests/nvim/startup_policy.lua" +qa
run_nvim completion-contract "-n" "+luafile tests/nvim/run_contract.lua" "tests/nvim/completion_contract.lua"
grep -Fq "Completion interaction contract passed: LazyVim defaults, LuaSnip expansion, replacement plugin topology." \
    "$LOG_DIR/completion-contract.log" || {
    cat "$LOG_DIR/completion-contract.log" >&2
    echo "Completion interaction contract did not complete" >&2
    exit 1
}
run_nvim_expected_failure completion-contract-negative "-n" \
    "+lua vim.g.dotfiles_completion_contract_negative = true" \
    "+luafile tests/nvim/run_contract.lua" "tests/nvim/completion_contract.lua"
grep -Fq "COMPLETION_CONTRACT_NEGATIVE_CONTROL" "$LOG_DIR/completion-contract-negative.log" || {
    cat "$LOG_DIR/completion-contract-negative.log" >&2
    echo "Completion contract negative control did not reach the injected assertion" >&2
    exit 1
}
run_nvim clangd-completion "-u" "NONE" "-n" "-i" "NONE" \
    "+luafile tests/nvim/run_contract.lua" "tests/nvim/clangd_completion.lua"
grep -Fq "Clangd completion contract passed:" "$LOG_DIR/clangd-completion.log" || {
    cat "$LOG_DIR/clangd-completion.log" >&2
    echo "Clangd completion contract did not complete" >&2
    exit 1
}
# Independent cold-cache control: remove one LSP-only receipt from this test's
# isolated data, not from the user's installation. A 21-tool-only check misses it.
receipt="$XDG_DATA_HOME/nvim/mason/packages/lua-language-server/mason-receipt.json"
mv "$receipt" "$receipt.negative"
run_nvim_expected_failure clangd-completion-missing-receipt "-u" "NONE" "-n" "-i" "NONE" \
    "+luafile tests/nvim/run_contract.lua" "tests/nvim/clangd_completion.lua"
mv "$receipt.negative" "$receipt"
grep -Fq 'WARM_UI_MASON_NOT_READY: lua-language-server' "$LOG_DIR/clangd-completion-missing-receipt.log" || {
    cat "$LOG_DIR/clangd-completion-missing-receipt.log" >&2
    echo "Missing LSP receipt did not fail the warm UI readiness check" >&2
    exit 1
}
if ! python3 tests/nvim/comment_keys.py >"$LOG_DIR/comment-keys.log" 2>&1; then
    cat "$LOG_DIR/comment-keys.log" >&2
    exit 1
fi
grep -Fq "Native comment key contract passed:" "$LOG_DIR/comment-keys.log"
run_nvim color-unit "-n" "+set rtp^=$PWD/home/dot_config/nvim" "+luafile tests/nvim/run_contract.lua" "tests/nvim/color_unit_contract.lua"
run_nvim production-visual "-n" "+luafile tests/nvim/production_visual_runtime.lua" +qa
run_nvim python-provider-unit "-n" "+set rtp^=$PWD/home/dot_config/nvim" \
    "+luafile tests/nvim/run_contract.lua" "tests/nvim/python_provider_ownership_contract.lua"
run_nvim smoke "-n" "+lua vim.g.dotfiles_contract_file = 'tests/nvim/smoke.lua'" "+luafile tests/nvim/run_contract.lua"
grep -Fq "Neovim toolchain smoke tests passed" "$LOG_DIR/smoke.log"
run_nvim_expected_failure smoke-config-negative "-n" \
    "+lua vim.g.dotfiles_smoke_config_negative = true" \
    "+lua vim.g.dotfiles_contract_file = 'tests/nvim/smoke.lua'" "+luafile tests/nvim/run_contract.lua"
grep -Fq "SMOKE_CONFIG_NEGATIVE_CONTROL" "$LOG_DIR/smoke-config-negative.log"
grep -Fq "SMOKE_NEOTEST_SETUP_FAILED" "$LOG_DIR/smoke-config-negative.log"
if grep -Fq "Neovim toolchain smoke tests passed" "$LOG_DIR/smoke-config-negative.log"; then
    echo "Failed Neotest setup produced a successful smoke marker" >&2
    exit 1
fi
run_nvim rust-ownership "-n" "+luafile tests/nvim/run_contract.lua" "tests/nvim/rust_toolchain.lua"
grep -Fq "Rust ownership runtime passed:" "$LOG_DIR/rust-ownership.log"
run_nvim color-contract "-n" "+luafile tests/nvim/color_contract.lua" +qa
grep -Fq "Tier-2 Runtime Integration Contract passed cleanly." "$LOG_DIR/color-contract.log"
run_nvim binding-evidence "-n" "+luafile tests/nvim/binding_evidence.lua" +qa
DOTFILES_M2C_CONFIG_HOME="$CONFIG_HOME" DOTFILES_M2C_LOG_DIR="$LOG_DIR" \
    bash tests/nvim/python_provider_ownership.sh

if grep -ERni 'Package is already installing|Neovim is exiting while packages are still installing|MasonToolsStartingInstall|MasonToolsUpdateCompleted|^Installing tools:|^Updating tools:' \
    "$LOG_DIR/lazy-restore.log" "$LOG_DIR/startup-policy.log" "$LOG_DIR/completion-contract.log" \
    "$LOG_DIR/completion-contract-negative.log" "$LOG_DIR/clangd-completion.log" "$LOG_DIR/smoke.log" \
    "$LOG_DIR/color-unit.log" "$LOG_DIR/production-visual.log" \
    "$LOG_DIR/python-provider-unit.log" "$LOG_DIR/color-contract.log" "$LOG_DIR/rust-ownership.log" \
    "$LOG_DIR/binding-evidence.log" "$LOG_DIR/python-provider-production.log"; then
    echo "Unexpected Mason background installation or update detected" >&2
    exit 1
fi

cmp "$CONFIG_HOME/nvim/lazy-lock.json" "$LOCK_SNAPSHOT"
git diff --exit-code -- home/dot_config/nvim/lazy-lock.json
printf '\nNeovim locked cold-start tests passed\nLogs: %s\n' "$LOG_DIR"
