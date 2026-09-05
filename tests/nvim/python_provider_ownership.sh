#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE_CONFIG_ROOT="${DOTFILES_M2C_CONFIG_HOME:-$REPO_ROOT/home/dot_config}"
SOURCE_NVIM_CONFIG="$SOURCE_CONFIG_ROOT/nvim"
TEST_ROOT="$(mktemp -d)"
LOG_DIR="${DOTFILES_M2C_LOG_DIR:-$TEST_ROOT/logs}"
PRODUCTION_REPORT="$TEST_ROOT/production.json"
EXCLUDED_REPORT="$TEST_ROOT/ty-excluded.json"
OVERLAY_CONFIG="$TEST_ROOT/overlay-config"

cleanup() {
    rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

[[ -d "$SOURCE_NVIM_CONFIG" ]] || {
    echo "Neovim config is unavailable: $SOURCE_NVIM_CONFIG" >&2
    exit 1
}
command -v nvim >/dev/null || {
    echo "nvim is unavailable" >&2
    exit 1
}
command -v jq >/dev/null || {
    echo "jq is unavailable" >&2
    exit 1
}

mkdir -p "$LOG_DIR" "$TEST_ROOT/production-state" "$TEST_ROOT/production-cache"
mkdir -p "$OVERLAY_CONFIG/nvim/lua/plugins" "$TEST_ROOT/excluded-state" "$TEST_ROOT/excluded-cache"
cp -R "$SOURCE_NVIM_CONFIG/." "$OVERLAY_CONFIG/nvim/"
cp "$REPO_ROOT/tests/nvim/fixtures/python_provider_ty_exclusion.lua" \
    "$OVERLAY_CONFIG/nvim/lua/plugins/m2c_ty_exclusion.lua"

run_probe() {
    local mode="${1:?mode is required}"
    local config_root="${2:?config root is required}"
    local state_root="${3:?state root is required}"
    local cache_root="${4:?cache root is required}"
    local report="${5:?report path is required}"
    local log_file="$LOG_DIR/python-provider-$mode.log"

    (
        cd "$REPO_ROOT"
        M2C_MODE="$mode" M2C_REPORT_PATH="$report" \
            XDG_CONFIG_HOME="$config_root" XDG_STATE_HOME="$state_root" XDG_CACHE_HOME="$cache_root" \
            nvim -n --headless \
            --cmd "luafile $REPO_ROOT/tests/nvim/python_provider_enable_trace.lua" \
            "+luafile tests/nvim/python_provider_ownership.lua" +qa
    ) >"$log_file" 2>&1 || {
        cat "$log_file" >&2
        return 1
    }
    cat "$log_file"
}

run_probe production "$SOURCE_CONFIG_ROOT" "$TEST_ROOT/production-state" \
    "$TEST_ROOT/production-cache" "$PRODUCTION_REPORT"
run_probe ty-excluded "$OVERLAY_CONFIG" "$TEST_ROOT/excluded-state" \
    "$TEST_ROOT/excluded-cache" "$EXCLUDED_REPORT"

jq -e -s '
  .[0] as $production |
  .[1] as $excluded |
  $production.mode == "production" and
  $excluded.mode == "ty-excluded" and
  $production.mason == $excluded.mason and
  $production.resolved_config == $excluded.resolved_config and
  $excluded.automatic_enable.exclude == (($production.automatic_enable.exclude + ["ty"]) | unique | sort) and
  $production.lazy_server_state.pyright == $excluded.lazy_server_state.pyright and
  $production.lazy_server_state.ruff == $excluded.lazy_server_state.ruff and
  $production.native_enabled.pyright == $excluded.native_enabled.pyright and
  $production.native_enabled.ruff == $excluded.native_enabled.ruff and
  $production.clients.pyright.capabilities == $excluded.clients.pyright.capabilities and
  $production.clients.ruff.capabilities == $excluded.clients.ruff.capabilities and
  $production.semantic_producers == ["ty"] and
  $excluded.semantic_producers == [] and
  $production.semantic_probe.producer == "ty" and
  $excluded.semantic_probe.producer == "none" and
  $production.decision == "ADOPT TY AS INTERACTIVE SEMANTIC PROVIDER" and
  $excluded.decision == $production.decision
' "$PRODUCTION_REPORT" "$EXCLUDED_REPORT" >/dev/null

if grep -ERqi 'Package is already installing|^Installing tools:|^Updating tools:|MasonToolsUpdate' \
    "$LOG_DIR/python-provider-production.log" "$LOG_DIR/python-provider-ty-excluded.log"; then
    echo "M2C-A observation attempted a Mason install or update" >&2
    exit 1
fi

echo "M2C-A Ty exclusion changed only Ty activation; Pyright and Ruff topology remained stable."
echo "M2C-A decision: ADOPT TY AS INTERACTIVE SEMANTIC PROVIDER"
