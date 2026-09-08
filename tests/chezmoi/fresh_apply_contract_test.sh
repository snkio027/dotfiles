#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'chmod -R u+rwX "$TEST_ROOT" 2>/dev/null || true; rm -rf -- "$TEST_ROOT"' EXIT

CONFIG_TEMPLATE="$REPO_ROOT/home/.chezmoi.toml.tmpl"
INSTALL_TEMPLATE="$REPO_ROOT/home/.chezmoiscripts/run_once_before_10_install_brew.sh.tmpl"
BUNDLE_TEMPLATE="$REPO_ROOT/home/.chezmoiscripts/run_onchange_after_20_brew_bundle.sh.tmpl"
UV_TEMPLATE="$REPO_ROOT/home/.chezmoiscripts/run_onchange_after_30_uv_tools.sh.tmpl"
LINUX_DATA='{"is_mac":false,"is_linux":true,"is_arm64":false,"machine_profile":"workstation"}'
MACOS_ARM_DATA='{"is_mac":true,"is_linux":false,"is_arm64":true,"machine_profile":"workstation"}'
MACOS_INTEL_DATA='{"is_mac":true,"is_linux":false,"is_arm64":false,"machine_profile":"workstation"}'

INSTALL_SCRIPT="$TEST_ROOT/install-brew.sh"
BUNDLE_SCRIPT="$TEST_ROOT/brew-bundle.sh"
UV_SCRIPT="$TEST_ROOT/uv-tools.sh"
MISSING_BUNDLE_SCRIPT="$TEST_ROOT/missing-brewfile.sh"
BREW_TEST_PREFIX="$TEST_ROOT/linuxbrew"
UV_TOOL_BIN_DIR="$TEST_ROOT/uv-tools/bin"
FIXTURE_BIN="$TEST_ROOT/fixture-bin"
FRESH_APPLY_LOG="$TEST_ROOT/fresh-apply.log"
SANITIZED_PATH="$FIXTURE_BIN:/usr/bin:/bin"

render_linux_script() {
    local template="$1" output="$2"
    chezmoi execute-template --source="$REPO_ROOT" --override-data "$LINUX_DATA" \
        <"$template" >"$output"
    sed -i.bak "s#/home/linuxbrew/.linuxbrew#$BREW_TEST_PREFIX#g" "$output"
    rm -f "$output.bak"
    bash -n "$output"
}

assert_platform_paths() {
    local name="$1" data="$2" prefix="$3"
    local install="$TEST_ROOT/$name-install.sh"
    local bundle="$TEST_ROOT/$name-bundle.sh"
    local uv="$TEST_ROOT/$name-uv.sh"

    chezmoi execute-template --source="$REPO_ROOT" --override-data "$data" \
        <"$INSTALL_TEMPLATE" >"$install"
    chezmoi execute-template --source="$REPO_ROOT" --override-data "$data" \
        <"$BUNDLE_TEMPLATE" >"$bundle"
    chezmoi execute-template --source="$REPO_ROOT" --override-data "$data" \
        <"$UV_TEMPLATE" >"$uv"

    grep -Fq "BREW_PREFIX=\"$prefix\"" "$install"
    grep -Fq "BREW_BIN=\"$prefix/bin/brew\"" "$bundle"
    grep -Fq "UV_BIN=\"$prefix/bin/uv\"" "$uv"
}

render_config() {
    local profile="$1" output="$2"
    GIT_AUTHOR_NAME='Fresh Apply Test' \
        GIT_AUTHOR_EMAIL='fresh-apply@example.com' \
        CHEZMOI_PROFILE="$profile" \
        chezmoi execute-template --init --source="$REPO_ROOT" \
        <"$CONFIG_TEMPLATE" >"$output"
}

# An absent profile keeps the documented workstation default. Every explicit
# value is an exact enum: whitespace, case drift, and unknown values fail.
env -u CHEZMOI_PROFILE \
    GIT_AUTHOR_NAME='Fresh Apply Test' \
    GIT_AUTHOR_EMAIL='fresh-apply@example.com' \
    chezmoi execute-template --init --source="$REPO_ROOT" \
    <"$CONFIG_TEMPLATE" >"$TEST_ROOT/default-config.toml"
grep -q 'machine_profile = "workstation"' "$TEST_ROOT/default-config.toml"

for profile in workstation devcontainer; do
    render_config "$profile" "$TEST_ROOT/$profile.toml"
    grep -q "machine_profile = \"$profile\"" "$TEST_ROOT/$profile.toml"
done

for profile in Workstation DEVCONTAINER unknown ' workstation' 'workstation ' ' '; do
    if render_config "$profile" "$TEST_ROOT/invalid.toml" 2>"$TEST_ROOT/invalid-profile.log"; then
        echo "invalid CHEZMOI_PROFILE unexpectedly rendered: [$profile]" >&2
        exit 1
    fi
    grep -q 'CHEZMOI_PROFILE must be exactly workstation or devcontainer' \
        "$TEST_ROOT/invalid-profile.log"
done

if chezmoi execute-template --source="$REPO_ROOT" \
    --override-data '{"is_mac":false,"is_linux":true,"is_arm64":false,"machine_profile":"Workstation"}' \
    <"$BUNDLE_TEMPLATE" >"$TEST_ROOT/invalid-bundle.sh" \
    2>"$TEST_ROOT/invalid-bundle.log"; then
    echo "invalid machine_profile unexpectedly rendered a Brew bundle script" >&2
    exit 1
fi
grep -q 'expected workstation or devcontainer' "$TEST_ROOT/invalid-bundle.log"

assert_platform_paths macos-arm "$MACOS_ARM_DATA" /opt/homebrew
assert_platform_paths macos-intel "$MACOS_INTEL_DATA" /usr/local
assert_platform_paths linux "$LINUX_DATA" /home/linuxbrew/.linuxbrew

render_linux_script "$INSTALL_TEMPLATE" "$INSTALL_SCRIPT"
render_linux_script "$BUNDLE_TEMPLATE" "$BUNDLE_SCRIPT"
render_linux_script "$UV_TEMPLATE" "$UV_SCRIPT"

grep -Fq "BREW_PREFIX=\"$BREW_TEST_PREFIX\"" "$INSTALL_SCRIPT"
grep -Fq 'BREW_BIN="${BREW_PREFIX}/bin/brew"' "$INSTALL_SCRIPT"
grep -Fq "BREW_BIN=\"$BREW_TEST_PREFIX/bin/brew\"" "$BUNDLE_SCRIPT"
grep -Fq "UV_BIN=\"$BREW_TEST_PREFIX/bin/uv\"" "$UV_SCRIPT"
grep -Fq 'if [ ! -r "$BREWFILE" ]; then' "$BUNDLE_SCRIPT"

mkdir -p "$FIXTURE_BIN"
cat >"$FIXTURE_BIN/gcc" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$FIXTURE_BIN/gcc"

cat >"$FIXTURE_BIN/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf 'curl:%s\n' "$*" >>"$FRESH_APPLY_LOG"
cat <<'INSTALLER'
set -euo pipefail
mkdir -p "$BREW_TEST_PREFIX/bin"
cat >"$BREW_TEST_PREFIX/bin/brew" <<'BREW'
#!/usr/bin/env bash
set -euo pipefail

printf 'brew:auto_update=%s:%s\n' "${HOMEBREW_NO_AUTO_UPDATE:-unset}" "$*" >>"$FRESH_APPLY_LOG"
case "${1:-}" in
--version)
    printf 'Homebrew fresh-apply-test\n'
    ;;
commands)
    printf 'bundle\ntrust\n'
    ;;
trust)
    [ "$*" = 'trust --formula hashicorp/tap/terraform' ]
    ;;
bundle)
    [ "${HOMEBREW_NO_AUTO_UPDATE:-}" = "1" ]
    [ "${2:-}" = "install" ]
    printf '%s\n' "$@" | grep -qx -- '--no-upgrade'
    printf '%s\n' "$@" | grep -Eq '^--file=.+/brew/profiles/workstation\.Brewfile$'
    mkdir -p "$BREW_TEST_PREFIX/bin"
    cat >"$BREW_TEST_PREFIX/bin/uv" <<'UV'
#!/usr/bin/env bash
set -euo pipefail

printf 'uv:%s\n' "$*" >>"$FRESH_APPLY_LOG"
case "${1:-}" in
--version)
    printf 'uv fresh-apply-test\n'
    ;;
tool)
    case "${2:-}" in
    install)
        [ "$*" = 'tool install --upgrade --no-config cxx-init' ]
        mkdir -p "$UV_TOOL_BIN_DIR"
        cat >"$UV_TOOL_BIN_DIR/cxx" <<'CXX'
#!/usr/bin/env bash
set -euo pipefail
printf 'cxx:%s\n' "$*" >>"$FRESH_APPLY_LOG"
if [ -n "${CXX_TEST_EXIT:-}" ]; then
    exit "$CXX_TEST_EXIT"
fi
printf 'cxx-init fresh-apply-test\n'
CXX
        chmod +x "$UV_TOOL_BIN_DIR/cxx"
        ;;
    dir)
        [ "$*" = 'tool dir --bin' ]
        printf '%s\n' "$UV_TOOL_BIN_DIR"
        ;;
    *)
        echo "unexpected uv tool command: $*" >&2
        exit 64
        ;;
    esac
    ;;
*)
    echo "unexpected uv command: $*" >&2
    exit 64
    ;;
esac
UV
    chmod +x "$BREW_TEST_PREFIX/bin/uv"
    ;;
install)
    [ "${2:-}" = "gcc" ]
    ;;
*)
    echo "unexpected brew command: $*" >&2
    exit 64
    ;;
esac
BREW
chmod +x "$BREW_TEST_PREFIX/bin/brew"
INSTALLER
EOF
chmod +x "$FIXTURE_BIN/curl"

if PATH="$SANITIZED_PATH" command -v brew >/dev/null 2>&1; then
    echo "fresh parent unexpectedly exposes brew through PATH" >&2
    exit 1
fi
if PATH="$SANITIZED_PATH" command -v uv >/dev/null 2>&1; then
    echo "fresh parent unexpectedly exposes uv through PATH" >&2
    exit 1
fi

# A consumer must not silently succeed before the bootstrap establishes Brew.
if PATH="$SANITIZED_PATH" /bin/bash "$BUNDLE_SCRIPT" \
    >"$TEST_ROOT/preinstall-bundle.log" 2>&1; then
    echo "Brew bundle unexpectedly succeeded without the fixed Brew entry" >&2
    exit 1
fi
grep -q 'Homebrew 入口缺失或不可执行' "$TEST_ROOT/preinstall-bundle.log"

export BREW_TEST_PREFIX FRESH_APPLY_LOG UV_TOOL_BIN_DIR
PATH="$SANITIZED_PATH" /bin/bash "$INSTALL_SCRIPT" >"$TEST_ROOT/install.log"

# The installer cannot mutate its parent's PATH; later scripts must still work.
if PATH="$SANITIZED_PATH" command -v brew >/dev/null 2>&1; then
    echo "Homebrew leaked into the parent PATH" >&2
    exit 1
fi
[ -x "$BREW_TEST_PREFIX/bin/brew" ]

sed "s#^BREWFILE=.*#BREWFILE=\"$TEST_ROOT/missing.Brewfile\"#" \
    "$BUNDLE_SCRIPT" >"$MISSING_BUNDLE_SCRIPT"
if PATH="$SANITIZED_PATH" /bin/bash "$MISSING_BUNDLE_SCRIPT" \
    >"$TEST_ROOT/missing-brewfile.log" 2>&1; then
    echo "Brew bundle unexpectedly succeeded without a readable Brewfile" >&2
    exit 1
fi
grep -q 'Brew profile 缺失或不可读' "$TEST_ROOT/missing-brewfile.log"

PATH="$SANITIZED_PATH" /bin/bash "$BUNDLE_SCRIPT" >"$TEST_ROOT/bundle.log"
[ -x "$BREW_TEST_PREFIX/bin/uv" ]
if PATH="$SANITIZED_PATH" command -v uv >/dev/null 2>&1; then
    echo "uv leaked into the parent PATH" >&2
    exit 1
fi

UV_SUCCESS_MARKER="$TEST_ROOT/uv-success.marker"
negative_status=0
if CXX_TEST_EXIT=47 PATH="$SANITIZED_PATH" /bin/bash "$UV_SCRIPT" \
    >"$TEST_ROOT/uv-negative.log" 2>&1; then
    touch "$UV_SUCCESS_MARKER"
else
    negative_status=$?
fi
if [ "$negative_status" -ne 47 ]; then
    echo "cxx --version failure returned $negative_status instead of 47" >&2
    exit 1
fi
if grep -q 'cxx-init 已就绪' "$TEST_ROOT/uv-negative.log"; then
    echo "failed cxx --version produced a success message" >&2
    exit 1
fi
grep -q 'cxx-init 入口无法正常执行' "$TEST_ROOT/uv-negative.log"
if [ -e "$UV_SUCCESS_MARKER" ]; then
    echo "failed cxx --version produced a success receipt" >&2
    exit 1
fi

PATH="$SANITIZED_PATH" /bin/bash "$UV_SCRIPT" >"$TEST_ROOT/uv.log"
[ -x "$UV_TOOL_BIN_DIR/cxx" ]

grep -q '^curl:-fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh$' \
    "$FRESH_APPLY_LOG"
grep -q '^brew:auto_update=1:bundle install --no-upgrade --file=' "$FRESH_APPLY_LOG"
grep -q '^uv:tool install --upgrade --no-config cxx-init$' "$FRESH_APPLY_LOG"
grep -q '^cxx:--version$' "$FRESH_APPLY_LOG"

install_line="$(grep -n -m 1 '^curl:' "$FRESH_APPLY_LOG" | cut -d: -f1)"
bundle_line="$(grep -n -m 1 '^brew:auto_update=1:bundle ' "$FRESH_APPLY_LOG" | cut -d: -f1)"
uv_line="$(grep -n -m 1 '^uv:tool install ' "$FRESH_APPLY_LOG" | cut -d: -f1)"
if ! [ "$install_line" -lt "$bundle_line" ] || ! [ "$bundle_line" -lt "$uv_line" ]; then
    echo "fresh apply ownership sequence is out of order" >&2
    exit 1
fi

printf 'Fresh apply deterministic restore contract passed\n'
