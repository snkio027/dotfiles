#!/usr/bin/env bash

set -euo pipefail

fail() {
    echo "$1" >&2
    exit 1
}

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE="$REPO_ROOT/scripts/supply-chain/check-brew-vulnerabilities.sh"
TEST_ROOT="$(mktemp -d)"
FAKE_BIN="$TEST_ROOT/fake-bin"
BREWFILE="$TEST_ROOT/fixture.Brewfile"
mkdir -p "$FAKE_BIN"
trap 'rm -rf -- "$TEST_ROOT"' EXIT
printf 'brew "fixture"\n' >"$BREWFILE"

cat >"$FAKE_BIN/brew" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
count=0
[[ ! -f "$FAKE_BREW_COUNT" ]] || count="$(cat "$FAKE_BREW_COUNT")"
count=$((count + 1))
printf '%d\n' "$count" >"$FAKE_BREW_COUNT"
case "$FAKE_BREW_MODE" in
pass)
    printf '{"findings": [], "skipped_formulae": ["fixture"]}\n'
    ;;
vulnerable)
    printf '{"findings": [{"formula": "fixture"}], "skipped_formulae": []}\n'
    ;;
unavailable)
    echo "OSV unavailable" >&2
    exit 1
    ;;
malformed)
    printf 'not-json\n'
    ;;
transient)
    if ((count < 3)); then
        echo "temporary network failure" >&2
        exit 1
    fi
    printf '{"findings": [], "skipped_formulae": []}\n'
    ;;
*)
    exit 99
    ;;
esac
EOF
chmod +x "$FAKE_BIN/brew"

run_case() {
    local mode="${1:?mode is required}"
    local expected_status="${2:?status is required}"
    local expected_exit="${3:?exit code is required}"
    local expected_attempts="${4:?attempt count is required}"
    local count_file="$TEST_ROOT/$mode.count"
    local log="$TEST_ROOT/$mode.log"
    local actual_exit

    set +e
    FAKE_BREW_MODE="$mode" FAKE_BREW_COUNT="$count_file" \
        BREW_VULNS_BREW_BIN="$FAKE_BIN/brew" BREW_VULNS_MAX_ATTEMPTS=3 \
        BREW_VULNS_RETRY_DELAY_SECONDS=0 "$GATE" "$BREWFILE" >"$log" 2>&1
    actual_exit=$?
    set -e

    [[ "$actual_exit" -eq "$expected_exit" ]] || fail "$mode returned $actual_exit"
    grep -Fq "BREW_VULNS_STATUS=$expected_status" "$log" || fail "$mode status is wrong"
    [[ "$(cat "$count_file")" -eq "$expected_attempts" ]] || fail "$mode retry count is wrong"
    if [[ "$expected_status" != PASS ]]; then
        ! grep -Fq 'BREW_VULNS_STATUS=PASS' "$log" || fail "$mode was falsely recorded as PASS"
    fi
}

run_case pass PASS 0 1
run_case vulnerable VULNERABLE 2 1
run_case unavailable UNAVAILABLE 3 3
run_case malformed UNAVAILABLE 3 3
run_case transient PASS 0 3

echo "Brew vulnerability state contract passed (PASS/VULNERABLE/UNAVAILABLE)"
