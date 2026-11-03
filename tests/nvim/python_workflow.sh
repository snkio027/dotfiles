#!/usr/bin/env bash
# The caller supplies an already provisioned, isolated Neovim HOME/XDG profile.
# Dependencies are read-only directories containing pytest and its dependencies.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
: "${DOTFILES_PYTHON_PACKAGES:?Set existing pytest dependency directories, separated by colons}"
if [ "$#" -eq 0 ]; then
    : "${XDG_CONFIG_HOME:?Use an isolated Neovim profile}"
    : "${XDG_DATA_HOME:?Use an isolated Neovim profile}"
fi
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT
args=("$TEST_ROOT")
IFS=: read -r -a directories <<<"$DOTFILES_PYTHON_PACKAGES"
for directory in "${directories[@]}"; do
    args+=(--packages "$directory")
done
TEST_ROOT="$(python3 "$REPO_ROOT/tests/nvim/python_workflow_fixtures.py" "${args[@]}")"
export DOTFILES_PYTHON_FIXTURES="$TEST_ROOT"
export PYTHONDONTWRITEBYTECODE=1
cd "$REPO_ROOT"
if [ "$#" -gt 0 ]; then
    # Optional command delegates profile isolation to an external test runner.
    "$@"
else
    nvim -n -i NONE --headless \
        "+lua vim.g.dotfiles_contract_file = 'tests/nvim/python_workflow.lua'" \
        "+luafile tests/nvim/run_contract.lua"
fi
