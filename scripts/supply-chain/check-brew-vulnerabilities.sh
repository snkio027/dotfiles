#!/usr/bin/env bash

set -euo pipefail

fail() {
    echo "brew vulnerability gate: $*" >&2
    exit 64
}

[[ "$#" -gt 0 ]] || fail "at least one Brewfile profile is required"

BREW_BIN="${BREW_VULNS_BREW_BIN:-brew}"
PYTHON_BIN="${BREW_VULNS_PYTHON_BIN:-python3}"
MAX_ATTEMPTS="${BREW_VULNS_MAX_ATTEMPTS:-3}"
RETRY_DELAY="${BREW_VULNS_RETRY_DELAY_SECONDS:-2}"

[[ "$MAX_ATTEMPTS" =~ ^[1-9][0-9]*$ ]] || fail "attempt count must be a positive integer"
[[ "$RETRY_DELAY" =~ ^[0-9]+$ ]] || fail "retry delay must be a non-negative integer"
command -v "$BREW_BIN" >/dev/null 2>&1 || fail "brew is unavailable"
command -v "$PYTHON_BIN" >/dev/null 2>&1 || fail "python3 is unavailable"

temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/brew-vulns.XXXXXX")"
trap 'rm -rf -- "$temp_dir"' EXIT
trust_config="$temp_dir/xdg-config"

configure_ephemeral_trust() {
    local trusted_formula trust_manifest

    trust_manifest="$temp_dir/trusted-formulae"
    "$PYTHON_BIN" - "$@" >"$trust_manifest" <<'PY'
import json
import re
import sys

pattern = re.compile(
    r'^\s*tap\s+("(?:[^"\\]|\\.)*"),\s*trusted:\s*\{\s*'
    r'formulae:\s*\[(.*?)\]\s*\}'
)
trusted = set()
for brewfile in sys.argv[1:]:
    with open(brewfile, encoding="utf-8") as handle:
        for raw_line in handle:
            match = pattern.match(raw_line)
            if not match:
                continue
            tap = json.loads(match.group(1))
            formulae = json.loads(f"[{match.group(2)}]")
            for formula in formulae:
                trusted.add(formula if "/" in formula else f"{tap}/{formula}")
for formula in sorted(trusted):
    print(formula)
PY

    while IFS= read -r trusted_formula; do
        [[ -n "$trusted_formula" ]] || continue
        XDG_CONFIG_HOME="$trust_config" \
            "$BREW_BIN" trust --formula "$trusted_formula" >/dev/null
    done <"$trust_manifest"
}

check_profile() {
    local brewfile="${1:?Brewfile is required}"
    local profile attempt output error parse_result findings skipped

    [[ -r "$brewfile" ]] || fail "Brewfile is unavailable: $brewfile"
    profile="$(basename "$brewfile")"
    output="$temp_dir/$profile.json"
    error="$temp_dir/$profile.stderr"

    for ((attempt = 1; attempt <= MAX_ATTEMPTS; attempt++)); do
        : >"$output"
        : >"$error"
        if XDG_CONFIG_HOME="$trust_config" \
            "$BREW_BIN" vulns --brewfile="$brewfile" --severity high --json >"$output" 2>"$error"; then
            if parse_result="$($PYTHON_BIN -c '
import json
import sys

try:
    data = json.load(open(sys.argv[1], encoding="utf-8"))
except (OSError, json.JSONDecodeError):
    raise SystemExit(1)
findings = data.get("findings")
skipped = data.get("skipped_formulae", [])
if not isinstance(findings, list) or not isinstance(skipped, list):
    raise SystemExit(1)
print(f"{len(findings)} {len(skipped)}")
' "$output")"; then
                read -r findings skipped <<<"$parse_result"
                if ((findings > 0)); then
                    printf 'BREW_VULNS_STATUS=VULNERABLE profile=%s findings=%d skipped=%d scope=formula/osv severity=high\n' \
                        "$profile" "$findings" "$skipped"
                    "$PYTHON_BIN" -m json.tool "$output" >&2
                    return 2
                fi
                printf 'BREW_VULNS_STATUS=PASS profile=%s findings=0 skipped=%d scope=formula/osv severity=high\n' \
                    "$profile" "$skipped"
                return 0
            fi
            echo "brew vulnerability gate: invalid JSON for $profile (attempt $attempt/$MAX_ATTEMPTS)" >&2
        else
            echo "brew vulnerability gate: query failed for $profile (attempt $attempt/$MAX_ATTEMPTS)" >&2
            sed -n '1,20p' "$error" >&2
        fi

        if ((attempt < MAX_ATTEMPTS && RETRY_DELAY > 0)); then
            sleep "$RETRY_DELAY"
        fi
    done

    printf 'BREW_VULNS_STATUS=UNAVAILABLE profile=%s attempts=%d scope=formula/osv severity=high\n' \
        "$profile" "$MAX_ATTEMPTS"
    return 3
}

configure_ephemeral_trust "$@"

for brewfile in "$@"; do
    check_profile "$brewfile"
done
