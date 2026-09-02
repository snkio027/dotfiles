#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

BREW_TEMPLATE="$REPO_ROOT/home/.chezmoiscripts/run_onchange_after_20_brew_bundle.sh.tmpl"
DEFAULTS_TEMPLATE="$REPO_ROOT/home/.chezmoiscripts/run_onchange_after_90_macos_defaults.sh.tmpl"
DOCTOR_TEMPLATE="$REPO_ROOT/home/dot_config/zsh/scripts/executable_doctor.sh.tmpl"
BREW_SCRIPT="$TEST_ROOT/brew_bundle.sh"
DEVCONTAINER_BREW_SCRIPT="$TEST_ROOT/devcontainer_brew_bundle.sh"
DOCTOR_SCRIPT="$TEST_ROOT/doctor.sh"
BREW_LOG="$TEST_ROOT/brew.log"

chezmoi execute-template --source="$REPO_ROOT" \
    --override-data '{"machine_profile":"workstation"}' \
    <"$BREW_TEMPLATE" >"$BREW_SCRIPT"
chezmoi execute-template --source="$REPO_ROOT" \
    --override-data '{"machine_profile":"devcontainer"}' \
    <"$BREW_TEMPLATE" >"$DEVCONTAINER_BREW_SCRIPT"

grep -q 'BREW_PROFILE="workstation"' "$BREW_SCRIPT"
grep -q 'BREW_PROFILE="devcontainer"' "$DEVCONTAINER_BREW_SCRIPT"
grep -q 'brew/profiles/${BREW_PROFILE}.Brewfile' "$BREW_SCRIPT" "$DEVCONTAINER_BREW_SCRIPT"

# `chezmoi apply` must not update metadata or request a bulk upgrade.
if grep -Eq '(^|[[:space:]])brew[[:space:]]+update([[:space:]]|$)' "$BREW_SCRIPT"; then
    echo "brew apply contract violation: implicit brew update" >&2
    exit 1
fi
grep -q 'HOMEBREW_NO_AUTO_UPDATE=1 brew bundle install --no-upgrade' "$BREW_SCRIPT"

mkdir -p "$TEST_ROOT/bin"
cat >"$TEST_ROOT/bin/brew" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf 'auto_update=%s command=%s\n' "${HOMEBREW_NO_AUTO_UPDATE:-unset}" "$*" >>"$BREW_TEST_LOG"
case "${1:-}" in
commands)
    printf 'trust\n'
    ;;
trust)
    ;;
bundle)
    [ "${HOMEBREW_NO_AUTO_UPDATE:-}" = "1" ]
    [ "${2:-}" = "install" ]
    printf '%s\n' "$@" | grep -qx -- '--no-upgrade'
    ;;
*)
    echo "unexpected brew command: $*" >&2
    exit 64
    ;;
esac
EOF
chmod +x "$TEST_ROOT/bin/brew"

BREW_TEST_LOG="$BREW_LOG" PATH="$TEST_ROOT/bin:$PATH" bash "$BREW_SCRIPT" >/dev/null
BREW_TEST_LOG="$BREW_LOG" PATH="$TEST_ROOT/bin:$PATH" bash "$DEVCONTAINER_BREW_SCRIPT" >/dev/null
grep -q 'auto_update=1 command=bundle install --no-upgrade' "$BREW_LOG"
if grep -Eq 'command=update([[:space:]]|$)' "$BREW_LOG"; then
    echo "brew apply contract violation: runtime update invocation" >&2
    exit 1
fi

# Ghostty appearance changes must not retrigger macOS defaults or Finder/Dock restarts.
if grep -Eqi 'ghostty|dot_config/ghostty/config' "$DEFAULTS_TEMPLATE"; then
    echo "macOS defaults contract violation: Ghostty hash dependency" >&2
    exit 1
fi

# A failed status observation must never be reported as a clean chezmoi state.
chezmoi execute-template --source="$REPO_ROOT" \
    --override-data '{"machine_profile":"devcontainer","features":{"use_1password":false}}' \
    <"$DOCTOR_TEMPLATE" >"$DOCTOR_SCRIPT"

mkdir -p "$TEST_ROOT/doctor-bin"
cat >"$TEST_ROOT/doctor-bin/chezmoi" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >>"$CHEZMOI_DOCTOR_TEST_LOG"
case "${1:-}" in
--version)
    printf 'chezmoi version v2.72.1, commit test\n'
    ;;
status)
    printf 'CHEZMOI_STATUS_SENTINEL: source state is unavailable\n' >&2
    exit 73
    ;;
*)
    printf 'unexpected chezmoi command: %s\n' "$*" >&2
    exit 64
    ;;
esac
EOF
chmod +x "$TEST_ROOT/doctor-bin/chezmoi"

DOCTOR_LOG="$TEST_ROOT/doctor-commands.log"
DOCTOR_OUTPUT="$TEST_ROOT/doctor-output.log"
if CHEZMOI_DOCTOR_TEST_LOG="$DOCTOR_LOG" PATH="$TEST_ROOT/doctor-bin:$PATH" \
    bash "$DOCTOR_SCRIPT" >"$DOCTOR_OUTPUT" 2>&1; then
    echo "devdoctor contract violation: failed chezmoi status reported success" >&2
    exit 1
fi
grep -q 'status failed, exit 73' "$DOCTOR_OUTPUT"
grep -q 'CHEZMOI_STATUS_SENTINEL: source state is unavailable' "$DOCTOR_OUTPUT"
if grep -q 'Synced / Clean' "$DOCTOR_OUTPUT"; then
    echo "devdoctor contract violation: failed status reported a clean state" >&2
    exit 1
fi
[ "$(grep -cx 'status' "$DOCTOR_LOG")" -eq 1 ]

printf 'devdoctor status failure: stderr sentinel visible, exit 73 propagated\n'
printf 'Chezmoi apply and observation side-effect tests passed\n'
