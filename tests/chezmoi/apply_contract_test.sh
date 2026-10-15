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
BREW_TEST_PREFIX="$TEST_ROOT/linuxbrew"
LINUX_WORKSTATION_DATA='{"is_mac":false,"is_linux":true,"is_arm64":false,"machine_profile":"workstation"}'
LINUX_DEVCONTAINER_DATA='{"is_mac":false,"is_linux":true,"is_arm64":false,"machine_profile":"devcontainer"}'

chezmoi execute-template --source="$REPO_ROOT" \
    --override-data "$LINUX_WORKSTATION_DATA" \
    <"$BREW_TEMPLATE" >"$BREW_SCRIPT"
chezmoi execute-template --source="$REPO_ROOT" \
    --override-data "$LINUX_DEVCONTAINER_DATA" \
    <"$BREW_TEMPLATE" >"$DEVCONTAINER_BREW_SCRIPT"
sed -i.bak "s#/home/linuxbrew/.linuxbrew#$BREW_TEST_PREFIX#g" \
    "$BREW_SCRIPT" "$DEVCONTAINER_BREW_SCRIPT"
rm -f "$BREW_SCRIPT.bak" "$DEVCONTAINER_BREW_SCRIPT.bak"

grep -q 'BREW_PROFILE="workstation"' "$BREW_SCRIPT"
grep -q 'BREW_PROFILE="devcontainer"' "$DEVCONTAINER_BREW_SCRIPT"
grep -q 'brew/profiles/${BREW_PROFILE}.Brewfile' "$BREW_SCRIPT" "$DEVCONTAINER_BREW_SCRIPT"

# `chezmoi apply` must not update metadata or request a bulk upgrade.
if grep -Eq '(^|[[:space:]])brew[[:space:]]+update([[:space:]]|$)' "$BREW_SCRIPT"; then
    echo "brew apply contract violation: implicit brew update" >&2
    exit 1
fi
grep -q 'HOMEBREW_NO_AUTO_UPDATE=1 "$BREW_BIN" bundle install --no-upgrade' "$BREW_SCRIPT"

mkdir -p "$BREW_TEST_PREFIX/bin"
cat >"$BREW_TEST_PREFIX/bin/brew" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf 'auto_update=%s command=%s\n' "${HOMEBREW_NO_AUTO_UPDATE:-unset}" "$*" >>"$BREW_TEST_LOG"
case "${1:-}" in
--version)
    printf 'Homebrew test\n'
    ;;
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
chmod +x "$BREW_TEST_PREFIX/bin/brew"

BREW_TEST_LOG="$BREW_LOG" PATH="/usr/bin:/bin" bash "$BREW_SCRIPT" >/dev/null
BREW_TEST_LOG="$BREW_LOG" PATH="/usr/bin:/bin" bash "$DEVCONTAINER_BREW_SCRIPT" >/dev/null
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

# Independent PATH fixtures: a located but broken executable is not healthy.
# No real package manager, toolchain, credentials or chezmoi state is touched.
mkdir -p "$TEST_ROOT/version-bin"
cat >"$TEST_ROOT/version-bin/tool" <<'EOF'
#!/bin/bash
set -euo pipefail
tool="${0##*/}"
printf '%s %s\n' "$tool" "$*" >>"$DOCTOR_TEST_COMMAND_LOG"
if [[ "$tool $*" == 'brew --prefix' ]]; then
    printf '%s\n' "$DOCTOR_TEST_PREFIX"
elif [[ "$tool $*" == 'chezmoi status' ]]; then
    printf '%s' "${DOCTOR_TEST_STATUS:-}"
    exit 0
elif [[ "$tool" == "${DOCTOR_TEST_TOOL:-}" ]]; then
    case "$DOCTOR_TEST_MODE" in
        failure)
            printf 'misleading version text\n'
            printf 'VERSION_STDERR_SENTINEL\n' >&2
            exit 47
            ;;
        empty) printf '   \n' ;;
        multiline)
            printf '%s test version 1.2.3\n' "$tool"
            for ((i = 0; i < 10000; i++)); do printf 'additional version detail\n'; done
            ;;
    esac
else
    printf '%s test version 1.2.3\n' "$tool"
fi
EOF
chmod +x "$TEST_ROOT/version-bin/tool"
for tool in brew chezmoi age gitleaks uv python3 node go zig clang cmake ninja ccache cxx terraform kubectl helm; do
    ln -s tool "$TEST_ROOT/version-bin/$tool"
done
doctor_versions() {
    : >"$TEST_ROOT/version-commands.log"
    env -u VCPKG_ROOT DOCTOR_TEST_PREFIX="$TEST_ROOT/no-rustup" \
        PATH="$TEST_ROOT/version-bin:/usr/bin:/bin" \
        DOCTOR_TEST_COMMAND_LOG="$TEST_ROOT/version-commands.log" \
        DOCTOR_TEST_STATUS="${DOCTOR_TEST_STATUS:-}" \
        DOCTOR_TEST_TOOL="${1:-}" DOCTOR_TEST_MODE="${2:-}" \
        bash "$DOCTOR_SCRIPT" >"$DOCTOR_OUTPUT" 2>&1
}
doctor_versions
grep -Eq 'C\+\+ Project Initializer.*✓.*cxx test version 1.2.3' "$DOCTOR_OUTPUT"

# File drift and script execution are different observations. Never apply or
# change script receipts to make a health report green.
for status_case in clean files scripts mixed; do
    DOCTOR_TEST_STATUS=''
    expected_files=0 expected_scripts=0
    case "$status_case" in
        files | mixed)
            DOCTOR_TEST_STATUS=$' M .config/file with spaces\nM  .config/local-edit\n A .config/Added\n D .config/R is not a script\n'
            expected_files=4
            ;;
    esac
    case "$status_case" in
        scripts | mixed)
            DOCTOR_TEST_STATUS+=$' R .chezmoiscripts/20_brew_bundle.sh\n R .chezmoiscripts/script with spaces.sh\n'
            expected_scripts=2
            ;;
    esac
    doctor_versions
    grep -Eq "chezmoi Files.*$expected_files file differences" "$DOCTOR_OUTPUT"
    grep -Eq "chezmoi Scripts.*$expected_scripts pending scripts" "$DOCTOR_OUTPUT"
    if [[ "$expected_files" -eq 0 ]]; then
        grep -Eq 'chezmoi Files.*✓.*Synced / Clean' "$DOCTOR_OUTPUT"
    else
        grep -Eq 'chezmoi Files.*⚠' "$DOCTOR_OUTPUT"
    fi
    if [[ "$expected_scripts" -gt 0 ]]; then
        grep -Eq 'chezmoi Scripts.*⚠.*not executed' "$DOCTOR_OUTPUT"
    else
        grep -Eq 'chezmoi Scripts.*✓' "$DOCTOR_OUTPUT"
    fi
    [[ "$(grep '^chezmoi ' "$TEST_ROOT/version-commands.log")" == $'chezmoi --version\nchezmoi status' ]]
done
unset DOCTOR_TEST_STATUS
# Alternate/project runtimes are identified, never silently rewritten.
grep -Fq "python3=$TEST_ROOT/version-bin/python3" "$DOCTOR_OUTPUT"
grep -Fq "clang=$TEST_ROOT/version-bin/clang" "$DOCTOR_OUTPUT"
grep -Fq "kubectl=$TEST_ROOT/version-bin/kubectl" "$DOCTOR_OUTPUT"
printf 'devdoctor state: clean, file-only, script-only and mixed observations verified without apply\n'

for tool in cxx cmake clang uv brew chezmoi; do
    for mode in failure empty; do
        status=0
        doctor_versions "$tool" "$mode" || status=$?
        [[ "$status" -eq 1 ]] || {
            echo "devdoctor accepted $tool $mode (exit $status)" >&2
            exit 1
        }
        if [[ "$mode" == failure ]]; then
            grep -q 'version command failed, exit 47' "$DOCTOR_OUTPUT"
            grep -q 'VERSION_STDERR_SENTINEL' "$DOCTOR_OUTPUT"
        else
            grep -q 'empty version response' "$DOCTOR_OUTPUT"
        fi
        if grep -Eq '100% Healthy|Good with minor warnings' "$DOCTOR_OUTPUT"; then
            echo "devdoctor falsely reported health after $tool $mode" >&2
            exit 1
        fi
    done
done
# Long successful output must not fail through head/SIGPIPE under pipefail.
doctor_versions cxx multiline
grep -Eq 'C\+\+ Project Initializer.*✓.*cxx test version 1.2.3' "$DOCTOR_OUTPUT"
mv "$TEST_ROOT/version-bin/cxx" "$TEST_ROOT/version-bin/cxx.absent"
doctor_versions
grep -Eq 'C\+\+ Project Initializer.*⚠.*cxx missing in PATH' "$DOCTOR_OUTPUT"
printf 'devdoctor versions: failures, stderr, empty output, multiline output and missing tools verified\n'
printf 'Chezmoi apply and observation side-effect tests passed\n'
