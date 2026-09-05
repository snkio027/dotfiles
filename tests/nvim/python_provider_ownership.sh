#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE_CONFIG_ROOT="${DOTFILES_M2C_CONFIG_HOME:-$REPO_ROOT/home/dot_config}"
SOURCE_NVIM_CONFIG="$SOURCE_CONFIG_ROOT/nvim"
TEST_ROOT="$(mktemp -d)"
LOG_DIR="${DOTFILES_M2C_LOG_DIR:-$TEST_ROOT/logs}"
REPORT="$TEST_ROOT/production.json"
LOG_FILE="$LOG_DIR/python-provider-production.log"

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

mkdir -p "$LOG_DIR" "$TEST_ROOT/state" "$TEST_ROOT/cache"

(
    cd "$REPO_ROOT"
    M2C_REPORT_PATH="$REPORT" \
        XDG_CONFIG_HOME="$SOURCE_CONFIG_ROOT" XDG_STATE_HOME="$TEST_ROOT/state" XDG_CACHE_HOME="$TEST_ROOT/cache" \
        nvim -n --headless \
        --cmd "luafile $REPO_ROOT/tests/nvim/python_provider_enable_trace.lua" \
        "+luafile tests/nvim/python_provider_ownership.lua" +qa
) >"$LOG_FILE" 2>&1 || {
    cat "$LOG_FILE" >&2
    exit 1
}
cat "$LOG_FILE"

jq -e '
  .milestone == "M2C-B" and
  .mode == "production" and
  ([.packages.pyright.installed, .packages.ruff.installed, .packages.ty.installed] | all) and
  .lazy_server_state == {"pyright":"disabled", "ruff":"enabled", "ty":"enabled"} and
  .native_enabled == {"pyright":false, "ruff":true, "ty":true} and
  .attached == ["ruff", "ty"] and
  .clients.pyright == {"attached":false} and
  .capability_owners == {
    "completion":["ty"],
    "definition":["ty"],
    "hover":["ty"],
    "references":["ty"],
    "rename":["ty"]
  } and
  .semantic_producers == ["ty"] and
  .semantic_probe.producer == "ty" and
  .semantic_probe.raw_token.client_id == .semantic_probe.neovim_tokens[0].client_id and
  .semantic_probe.foregrounds == [{
    "group":"@lsp.type.variable.python",
    "priority":125,
    "role":"DxVariable"
  }] and
  ([.enable_trace[] | select(.name == "pyright")] | length) == 0 and
  .decision == "ADOPT TY AS INTERACTIVE SEMANTIC PROVIDER"
' "$REPORT" >/dev/null

if grep -Eqi 'Package is already installing|^Installing tools:|^Updating tools:|MasonToolsUpdate' "$LOG_FILE"; then
    echo "M2C-B observation attempted a Mason install or update" >&2
    exit 1
fi

echo "M2C-B topology: installed pyright+ruff+ty; enabled/attached ruff+ty; semantic producer ty."
echo "M2C-B decision implemented: ADOPT TY AS INTERACTIVE SEMANTIC PROVIDER"
