#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
OUTPUT_ROOT="${1:-$(mktemp -d)}"
LOG_DIR="$OUTPUT_ROOT/logs"
RESULT_DIR="$OUTPUT_ROOT/results"

mkdir -p "$LOG_DIR" "$RESULT_DIR"

for case_name in m5 native-mocha native-macchiato native-frappe; do
    case_root="$OUTPUT_ROOT/runs/$case_name"
    output="$RESULT_DIR/$case_name.json"
    printf '\n==> native-first E1: %s\n' "$case_name"
    if ! DOTFILES_NATIVE_FIRST_RUN_ROOT="$case_root" \
        DOTFILES_NATIVE_FIRST_OUTPUT="$output" \
        bash "$REPO_ROOT/tests/nvim/native_first/run_case.sh" "$case_name" --headless \
        >"$LOG_DIR/$case_name.log" 2>&1; then
        tail -n 200 "$LOG_DIR/$case_name.log" >&2
        exit 1
    fi
    test -s "$output"
    printf 'completed (evidence: %s)\n' "$output"
done

python3 "$REPO_ROOT/tests/nvim/native_first/summarize.py" \
    "$RESULT_DIR/m5.json" \
    "$RESULT_DIR/native-mocha.json" \
    "$RESULT_DIR/native-macchiato.json" \
    "$RESULT_DIR/native-frappe.json" \
    >"$OUTPUT_ROOT/summary.md"

printf '\nCatppuccin native-first E1 harness passed\nEvidence: %s\n' "$OUTPUT_ROOT"
