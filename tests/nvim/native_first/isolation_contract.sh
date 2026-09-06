#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

SEED="$TEST_ROOT/seed"
RUN_ROOT="$TEST_ROOT/run"
FAKE_BIN="$TEST_ROOT/bin"
mkdir -p "$SEED"/{lazy,mason,site/queries/cpp} "$FAKE_BIN"
printf 'lazy-seed\n' >"$SEED/lazy/marker"
printf 'mason-seed\n' >"$SEED/mason/marker"
printf 'query-seed\n' >"$SEED/site/queries/cpp/highlights.scm"
ln -s "$SEED/lazy/marker" "$SEED/site/queries/cpp/seed-link"

printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'mkdir -p "$XDG_DATA_HOME/nvim/site"' \
    'printf "child-write\\n" >"$XDG_DATA_HOME/nvim/site/child-write"' \
    'count_file="$DOTFILES_NATIVE_FIRST_ROOT/fake-nvim-count"' \
    'count=0' \
    'if [ -f "$count_file" ]; then read -r count <"$count_file"; fi' \
    'printf "%d\\n" "$((count + 1))" >"$count_file"' \
    'if [ -n "${DOTFILES_NATIVE_FIRST_OUTPUT:-}" ]; then printf "{}\\n" >"$DOTFILES_NATIVE_FIRST_OUTPUT"; fi' \
    >"$FAKE_BIN/nvim"
chmod +x "$FAKE_BIN/nvim"

seed_manifest() {
    find "$SEED" -type f -exec cksum {} \; | sort
}

before="$(seed_manifest)"
PATH="$FAKE_BIN:$PATH" \
    DOTFILES_NATIVE_FIRST_SEED_DATA="$SEED" \
    DOTFILES_NATIVE_FIRST_RUN_ROOT="$RUN_ROOT" \
    DOTFILES_NATIVE_FIRST_KEEP_ROOT=1 \
    bash "$REPO_ROOT/tests/nvim/native_first/run_case.sh" native-mocha --headless

test -f "$RUN_ROOT/data/nvim/site/child-write"
test ! -e "$SEED/site/child-write"
for component in lazy mason site; do
    test -d "$RUN_ROOT/data/nvim/$component"
    test ! -L "$RUN_ROOT/data/nvim/$component"
done
resolved_link="$(python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).resolve())' \
    "$RUN_ROOT/data/nvim/site/queries/cpp/seed-link")"
resolved_run_root="$(python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).resolve())' "$RUN_ROOT")"
case "$resolved_link" in
    "$resolved_run_root"/*) ;;
    *)
        echo "rewritten data link escaped private run root: $resolved_link" >&2
        exit 1
        ;;
esac

if PATH="$FAKE_BIN:$PATH" \
    DOTFILES_NATIVE_FIRST_SEED_DATA="$SEED" \
    DOTFILES_NATIVE_FIRST_RUN_ROOT="$RUN_ROOT" \
    DOTFILES_NATIVE_FIRST_KEEP_ROOT=1 \
    bash "$REPO_ROOT/tests/nvim/native_first/run_case.sh" native-mocha --headless \
    >"$TEST_ROOT/reused.log" 2>&1; then
    echo "reused native-first run root unexpectedly succeeded" >&2
    exit 1
fi
grep -Fq "run root is not empty" "$TEST_ROOT/reused.log"
test "$(seed_manifest)" = "$before"

PREVIEW_ROOT="$TEST_ROOT/preview"
PATH="$FAKE_BIN:$PATH" \
    DOTFILES_NATIVE_FIRST_SEED_DATA="$SEED" \
    DOTFILES_NATIVE_FIRST_RUN_ROOT="$PREVIEW_ROOT" \
    DOTFILES_NATIVE_FIRST_KEEP_ROOT=1 \
    bash "$REPO_ROOT/tests/nvim/native_first/run_case.sh" native-frappe --preview
test "$(cat "$PREVIEW_ROOT/fake-nvim-count")" = "2"
test -s "$PREVIEW_ROOT/preview-preflight.json"
test ! -e "$SEED/site/child-write"
test "$(seed_manifest)" = "$before"

printf 'Native-first data-isolation contract passed\n'
