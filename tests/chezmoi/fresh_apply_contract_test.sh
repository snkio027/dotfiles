#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'chmod -R u+rwX "$TEST_ROOT" 2>/dev/null || true; rm -rf -- "$TEST_ROOT"' EXIT

CONFIG_TEMPLATE="$REPO_ROOT/home/.chezmoi.toml.tmpl"
INSTALL_TEMPLATE="$REPO_ROOT/home/.chezmoiscripts/run_once_before_10_install_brew.sh.tmpl"
BUNDLE_TEMPLATE="$REPO_ROOT/home/.chezmoiscripts/run_onchange_after_20_brew_bundle.sh.tmpl"
UV_TEMPLATE="$REPO_ROOT/home/.chezmoiscripts/run_onchange_after_30_uv_tools.sh.tmpl"
IDENTITY_TEMPLATE="$REPO_ROOT/home/.chezmoiscripts/run_once_after_20_git_identity.sh.tmpl"
HOOK_TEMPLATE="$REPO_ROOT/home/.chezmoiscripts/run_onchange_after_50_install_git_hooks.sh.tmpl"
LINUX_DATA='{"is_mac":false,"is_linux":true,"is_arm64":false,"machine_profile":"workstation","email":"fresh-apply@example.com","features":{"use_1password":false}}'
MACOS_ARM_DATA='{"is_mac":true,"is_linux":false,"is_arm64":true,"machine_profile":"workstation","email":"fresh-apply@example.com","features":{"use_1password":false}}'
MACOS_INTEL_DATA='{"is_mac":true,"is_linux":false,"is_arm64":false,"machine_profile":"workstation","email":"fresh-apply@example.com","features":{"use_1password":false}}'

INSTALL_SCRIPT="$TEST_ROOT/install-brew.sh"
BUNDLE_SCRIPT="$TEST_ROOT/brew-bundle.sh"
UV_SCRIPT="$TEST_ROOT/uv-tools.sh"
IDENTITY_SCRIPT="$TEST_ROOT/git-identity.sh"
HOOK_SCRIPT="$TEST_ROOT/install-git-hooks.sh"
MISSING_BUNDLE_SCRIPT="$TEST_ROOT/missing-brewfile.sh"
BREW_TEST_PREFIX="$TEST_ROOT/linuxbrew"
UV_TOOL_BIN_DIR="$TEST_ROOT/uv-tools/bin"
FIXTURE_BIN="$TEST_ROOT/fixture-bin"
FRESH_APPLY_LOG="$TEST_ROOT/fresh-apply.log"
GH_TEST_LOG="$TEST_ROOT/gh.log"
GITLEAKS_TEST_LOG="$TEST_ROOT/gitleaks.log"
PARENT_PATH_POISON_LOG="$TEST_ROOT/parent-path-poison.log"
CONSUMER_HOME="$TEST_ROOT/home"
CONSUMER_WORKTREE="$TEST_ROOT/working-tree"
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
    local identity="$TEST_ROOT/$name-identity.sh"
    local hook="$TEST_ROOT/$name-hook.sh"

    chezmoi execute-template --source="$REPO_ROOT" --override-data "$data" \
        <"$INSTALL_TEMPLATE" >"$install"
    chezmoi execute-template --source="$REPO_ROOT" --override-data "$data" \
        <"$BUNDLE_TEMPLATE" >"$bundle"
    chezmoi execute-template --source="$REPO_ROOT" --override-data "$data" \
        <"$UV_TEMPLATE" >"$uv"
    chezmoi execute-template --source="$REPO_ROOT" --override-data "$data" \
        <"$IDENTITY_TEMPLATE" >"$identity"
    chezmoi execute-template --source="$REPO_ROOT" --override-data "$data" \
        <"$HOOK_TEMPLATE" >"$hook"

    grep -Fq "BREW_PREFIX=\"$prefix\"" "$install"
    grep -Fq "BREW_BIN=\"$prefix/bin/brew\"" "$bundle"
    grep -Fq "UV_BIN=\"$prefix/bin/uv\"" "$uv"
    grep -Fq "GH_BIN=\"$prefix/bin/gh\"" "$identity"
    grep -Fq "GITLEAKS_BIN=\"$prefix/bin/gitleaks\"" "$hook"
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
render_linux_script "$IDENTITY_TEMPLATE" "$IDENTITY_SCRIPT"
render_linux_script "$HOOK_TEMPLATE" "$HOOK_SCRIPT"
sed -i.bak "s#$REPO_ROOT#$CONSUMER_WORKTREE#g" "$HOOK_SCRIPT"
rm -f "$HOOK_SCRIPT.bak"
bash -n "$HOOK_SCRIPT"

grep -Fq "BREW_PREFIX=\"$BREW_TEST_PREFIX\"" "$INSTALL_SCRIPT"
grep -Fq 'BREW_BIN="${BREW_PREFIX}/bin/brew"' "$INSTALL_SCRIPT"
grep -Fq "BREW_BIN=\"$BREW_TEST_PREFIX/bin/brew\"" "$BUNDLE_SCRIPT"
grep -Fq "UV_BIN=\"$BREW_TEST_PREFIX/bin/uv\"" "$UV_SCRIPT"
grep -Fq "GH_BIN=\"$BREW_TEST_PREFIX/bin/gh\"" "$IDENTITY_SCRIPT"
grep -Fq "GITLEAKS_BIN=\"$BREW_TEST_PREFIX/bin/gitleaks\"" "$HOOK_SCRIPT"
grep -Fq 'if [ ! -r "$BREWFILE" ]; then' "$BUNDLE_SCRIPT"
if grep -q 'command -v gh' "$IDENTITY_SCRIPT"; then
    echo "Git identity consumer still depends on the parent PATH" >&2
    exit 1
fi
if grep -q 'command -v gitleaks' "$HOOK_SCRIPT"; then
    echo "hook installer still depends on the parent PATH" >&2
    exit 1
fi

mkdir -p "$FIXTURE_BIN"
cat >"$FIXTURE_BIN/gcc" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$FIXTURE_BIN/gcc"

for poisoned_tool in gh gitleaks; do
    cat >"$FIXTURE_BIN/$poisoned_tool" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf 'poison:%s:%s\n' "$(basename "$0")" "$*" >>"$PARENT_PATH_POISON_LOG"
exit 97
EOF
    chmod +x "$FIXTURE_BIN/$poisoned_tool"
done
: >"$PARENT_PATH_POISON_LOG"

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

    cat >"$BREW_TEST_PREFIX/bin/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail

printf 'gh:host=%s:%s\n' "${GH_HOST:-unset}" "$*" >>"$GH_TEST_LOG"
case "${1:-}" in
--version)
    if [ -n "${GH_TEST_VERSION_EXIT:-}" ]; then
        exit "$GH_TEST_VERSION_EXIT"
    fi
    printf 'gh version fresh-apply-test\n'
    ;;
auth)
    [ "$*" = 'auth status --active --hostname github.com' ]
    exit "${GH_TEST_AUTH_STATUS:-0}"
    ;;
api)
    printf '%s\n' "$@" | grep -qx -- '--hostname'
    printf '%s\n' "$@" | grep -qx -- 'github.com'
    if [ -n "${GH_TEST_API_EXIT:-}" ]; then
        exit "$GH_TEST_API_EXIT"
    fi
    case "$*" in
    *user/ssh_signing_keys*)
        if [ -n "${GH_TEST_SIGN_API_EXIT:-}" ]; then
            exit "$GH_TEST_SIGN_API_EXIT"
        fi
        if [ -n "${GH_TEST_SIGN_REMOTE_KEY:-}" ]; then
            printf '%s\n' "$GH_TEST_SIGN_REMOTE_KEY"
        fi
        ;;
    *user/keys*)
        if [ -n "${GH_TEST_AUTH_API_EXIT:-}" ]; then
            exit "$GH_TEST_AUTH_API_EXIT"
        fi
        if [ -n "${GH_TEST_AUTH_REMOTE_KEY:-}" ]; then
            printf '%s\n' "$GH_TEST_AUTH_REMOTE_KEY"
        fi
        ;;
    *)
        echo "unexpected gh api endpoint: $*" >&2
        exit 64
        ;;
    esac
    ;;
ssh-key)
    [ "${2:-}" = "add" ]
    case " $* " in
    *' --type signing '*) exit "${GH_TEST_SIGN_UPLOAD_EXIT:-0}" ;;
    *) exit "${GH_TEST_AUTH_UPLOAD_EXIT:-0}" ;;
    esac
    ;;
*)
    echo "unexpected gh command: $*" >&2
    exit 64
    ;;
esac
GH
    chmod +x "$BREW_TEST_PREFIX/bin/gh"

    cat >"$BREW_TEST_PREFIX/bin/gitleaks" <<'GITLEAKS'
#!/usr/bin/env bash
set -euo pipefail

printf 'gitleaks:%s\n' "$*" >>"$GITLEAKS_TEST_LOG"
case "${1:-}" in
version)
    if [ -n "${GITLEAKS_TEST_VERSION_EXIT:-}" ]; then
        exit "$GITLEAKS_TEST_VERSION_EXIT"
    fi
    printf 'gitleaks fresh-apply-test\n'
    ;;
git)
    [ "$*" = 'git --pre-commit --staged --redact --verbose .' ]
    exit "${GITLEAKS_TEST_SCAN_EXIT:-0}"
    ;;
*)
    echo "unexpected gitleaks command: $*" >&2
    exit 64
    ;;
esac
GITLEAKS
    chmod +x "$BREW_TEST_PREFIX/bin/gitleaks"
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
[ "$(PATH="$SANITIZED_PATH" command -v gh)" = "$FIXTURE_BIN/gh" ]
[ "$(PATH="$SANITIZED_PATH" command -v gitleaks)" = "$FIXTURE_BIN/gitleaks" ]

# A consumer must not silently succeed before the bootstrap establishes Brew.
if PATH="$SANITIZED_PATH" /bin/bash "$BUNDLE_SCRIPT" \
    >"$TEST_ROOT/preinstall-bundle.log" 2>&1; then
    echo "Brew bundle unexpectedly succeeded without the fixed Brew entry" >&2
    exit 1
fi
grep -q 'Homebrew 入口缺失或不可执行' "$TEST_ROOT/preinstall-bundle.log"

export BREW_TEST_PREFIX FRESH_APPLY_LOG GH_TEST_LOG GITLEAKS_TEST_LOG
export PARENT_PATH_POISON_LOG UV_TOOL_BIN_DIR
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
[ -x "$BREW_TEST_PREFIX/bin/gh" ]
[ -x "$BREW_TEST_PREFIX/bin/gitleaks" ]
if PATH="$SANITIZED_PATH" command -v uv >/dev/null 2>&1; then
    echo "uv leaked into the parent PATH" >&2
    exit 1
fi
[ "$(PATH="$SANITIZED_PATH" command -v gh)" = "$FIXTURE_BIN/gh" ]
[ "$(PATH="$SANITIZED_PATH" command -v gitleaks)" = "$FIXTURE_BIN/gitleaks" ]

# The identity consumer runs after Brew bundle but cannot inherit its PATH.
mkdir -p "$CONSUMER_HOME/.ssh/keys"
AUTH_KEY_MATERIAL='ssh-ed25519 AAAAC3NzaFreshApplyAuth'
SIGN_KEY_MATERIAL='ssh-ed25519 AAAAC3NzaFreshApplySigning'
printf 'fixture private key\n' >"$CONSUMER_HOME/.ssh/keys/github_auth"
printf 'fixture private key\n' >"$CONSUMER_HOME/.ssh/keys/git_signing"
printf '%s auth\n' "$AUTH_KEY_MATERIAL" \
    >"$CONSUMER_HOME/.ssh/keys/github_auth.pub"
printf '%s signing\n' "$SIGN_KEY_MATERIAL" \
    >"$CONSUMER_HOME/.ssh/keys/git_signing.pub"
chmod 600 "$CONSUMER_HOME/.ssh/keys/github_auth" \
    "$CONSUMER_HOME/.ssh/keys/git_signing"
chmod 644 "$CONSUMER_HOME/.ssh/keys/github_auth.pub" \
    "$CONSUMER_HOME/.ssh/keys/git_signing.pub"

mv "$BREW_TEST_PREFIX/bin/gh" "$BREW_TEST_PREFIX/bin/gh.fixture"
if HOME="$CONSUMER_HOME" PATH="$SANITIZED_PATH" /bin/bash "$IDENTITY_SCRIPT" \
    >"$TEST_ROOT/identity-missing-gh.log" 2>&1; then
    echo "Git identity unexpectedly succeeded without the fixed gh entry" >&2
    exit 1
fi
grep -q 'Brew 管理的 gh 入口缺失或不可执行' \
    "$TEST_ROOT/identity-missing-gh.log"
if grep -q '开发者信任链身份配置完成' "$TEST_ROOT/identity-missing-gh.log"; then
    echo "missing gh entry produced an identity success marker" >&2
    exit 1
fi
mv "$BREW_TEST_PREFIX/bin/gh.fixture" "$BREW_TEST_PREFIX/bin/gh"

chmod 644 "$BREW_TEST_PREFIX/bin/gh"
if HOME="$CONSUMER_HOME" PATH="$SANITIZED_PATH" /bin/bash "$IDENTITY_SCRIPT" \
    >"$TEST_ROOT/identity-nonexec-gh.log" 2>&1; then
    echo "Git identity unexpectedly succeeded with a non-executable gh entry" >&2
    exit 1
fi
grep -q 'Brew 管理的 gh 入口缺失或不可执行' \
    "$TEST_ROOT/identity-nonexec-gh.log"
chmod +x "$BREW_TEST_PREFIX/bin/gh"

gh_version_status=0
: >"$GH_TEST_LOG"
if GH_HOST=enterprise.invalid GH_TEST_VERSION_EXIT=71 HOME="$CONSUMER_HOME" \
    PATH="$SANITIZED_PATH" \
    /bin/bash "$IDENTITY_SCRIPT" >"$TEST_ROOT/identity-broken-gh.log" 2>&1; then
    echo "Git identity unexpectedly succeeded with a broken gh entry" >&2
    exit 1
else
    gh_version_status=$?
fi
if [ "$gh_version_status" -ne 71 ]; then
    echo "broken gh entry returned $gh_version_status instead of 71" >&2
    exit 1
fi
grep -q 'Brew 管理的 gh 入口无法正常执行' \
    "$TEST_ROOT/identity-broken-gh.log"
grep -qx 'gh:host=github.com:--version' "$GH_TEST_LOG"

: >"$GH_TEST_LOG"
GH_HOST=enterprise.invalid GH_TEST_AUTH_STATUS=4 HOME="$CONSUMER_HOME" \
    PATH="$SANITIZED_PATH" \
    /bin/bash "$IDENTITY_SCRIPT" >"$TEST_ROOT/identity-unauthenticated.log"
grep -q 'github.com 当前未认证；本次未同步远端公钥' \
    "$TEST_ROOT/identity-unauthenticated.log"
grep -q '该 run_once 脚本不会在后续 apply 中自动重试' \
    "$TEST_ROOT/identity-unauthenticated.log"
grep -Fq "GH_HOST=github.com $BREW_TEST_PREFIX/bin/gh auth login --hostname github.com --scopes admin:public_key,admin:ssh_signing_key --skip-ssh-key" \
    "$TEST_ROOT/identity-unauthenticated.log"
grep -Fq "GH_HOST=github.com $BREW_TEST_PREFIX/bin/gh ssh-key add $CONSUMER_HOME/.ssh/keys/github_auth.pub" \
    "$TEST_ROOT/identity-unauthenticated.log"
grep -Fq "GH_HOST=github.com $BREW_TEST_PREFIX/bin/gh ssh-key add $CONSUMER_HOME/.ssh/keys/git_signing.pub --type signing" \
    "$TEST_ROOT/identity-unauthenticated.log"
grep -qx 'gh:host=github.com:--version' "$GH_TEST_LOG"
grep -qx 'gh:host=github.com:auth status --active --hostname github.com' "$GH_TEST_LOG"
if grep -Eq '^gh:host=github.com:(api|ssh-key)' "$GH_TEST_LOG"; then
    echo "unauthenticated gh attempted a remote key side effect" >&2
    exit 1
fi
if grep -q 'enterprise.invalid' "$GH_TEST_LOG"; then
    echo "inherited GH_HOST escaped the github.com ownership boundary" >&2
    exit 1
fi

identity_status=0
: >"$GH_TEST_LOG"
if GH_TEST_AUTH_STATUS=0 GH_TEST_API_EXIT=81 HOME="$CONSUMER_HOME" \
    PATH="$SANITIZED_PATH" /bin/bash "$IDENTITY_SCRIPT" \
    >"$TEST_ROOT/identity-api-failure.log" 2>&1; then
    echo "Git identity swallowed a GitHub API query failure" >&2
    exit 1
else
    identity_status=$?
fi
[ "$identity_status" -eq 81 ]
grep -q '无法查询 github.com 认证公钥' \
    "$TEST_ROOT/identity-api-failure.log"
if grep -q '开发者信任链身份配置完成' "$TEST_ROOT/identity-api-failure.log"; then
    echo "GitHub API query failure produced an identity success marker" >&2
    exit 1
fi
if grep -q '^gh:host=github.com:ssh-key ' "$GH_TEST_LOG"; then
    echo "GitHub API query failure was misclassified as a missing key" >&2
    exit 1
fi

identity_status=0
: >"$GH_TEST_LOG"
if GH_TEST_AUTH_STATUS=0 GH_TEST_AUTH_REMOTE_KEY="$AUTH_KEY_MATERIAL" \
    GH_TEST_SIGN_API_EXIT=84 HOME="$CONSUMER_HOME" PATH="$SANITIZED_PATH" \
    /bin/bash "$IDENTITY_SCRIPT" \
    >"$TEST_ROOT/identity-sign-api-failure.log" 2>&1; then
    echo "Git identity swallowed a signing-key API query failure" >&2
    exit 1
else
    identity_status=$?
fi
[ "$identity_status" -eq 84 ]
grep -q '无法查询 github.com 签名公钥' \
    "$TEST_ROOT/identity-sign-api-failure.log"
if grep -q '开发者信任链身份配置完成' \
    "$TEST_ROOT/identity-sign-api-failure.log"; then
    echo "signing-key API query failure produced an identity success marker" >&2
    exit 1
fi
if grep -q '^gh:host=github.com:ssh-key ' "$GH_TEST_LOG"; then
    echo "signing-key API failure triggered an upload" >&2
    exit 1
fi

identity_status=0
: >"$GH_TEST_LOG"
if GH_TEST_AUTH_STATUS=0 GH_TEST_AUTH_UPLOAD_EXIT=82 HOME="$CONSUMER_HOME" \
    PATH="$SANITIZED_PATH" /bin/bash "$IDENTITY_SCRIPT" \
    >"$TEST_ROOT/identity-auth-upload-failure.log" 2>&1; then
    echo "Git identity swallowed an authentication-key upload failure" >&2
    exit 1
else
    identity_status=$?
fi
[ "$identity_status" -eq 82 ]
grep -q '认证公钥上传失败' "$TEST_ROOT/identity-auth-upload-failure.log"
if grep -q '开发者信任链身份配置完成' \
    "$TEST_ROOT/identity-auth-upload-failure.log"; then
    echo "authentication-key upload failure produced an identity success marker" >&2
    exit 1
fi
[ "$(grep -c '^gh:host=github.com:ssh-key add ' "$GH_TEST_LOG")" -eq 1 ]

identity_status=0
: >"$GH_TEST_LOG"
if GH_TEST_AUTH_STATUS=0 GH_TEST_AUTH_REMOTE_KEY="$AUTH_KEY_MATERIAL" \
    GH_TEST_SIGN_UPLOAD_EXIT=83 HOME="$CONSUMER_HOME" PATH="$SANITIZED_PATH" \
    /bin/bash "$IDENTITY_SCRIPT" \
    >"$TEST_ROOT/identity-sign-upload-failure.log" 2>&1; then
    echo "Git identity swallowed a signing-key upload failure" >&2
    exit 1
else
    identity_status=$?
fi
[ "$identity_status" -eq 83 ]
grep -q '签名公钥上传失败' "$TEST_ROOT/identity-sign-upload-failure.log"
if grep -q '开发者信任链身份配置完成' \
    "$TEST_ROOT/identity-sign-upload-failure.log"; then
    echo "signing-key upload failure produced an identity success marker" >&2
    exit 1
fi
[ "$(grep -c '^gh:host=github.com:ssh-key add ' "$GH_TEST_LOG")" -eq 1 ]
grep -q -- '--type signing' "$GH_TEST_LOG"

: >"$GH_TEST_LOG"
GH_TEST_AUTH_STATUS=0 GH_TEST_AUTH_REMOTE_KEY="$AUTH_KEY_MATERIAL" \
    GH_TEST_SIGN_REMOTE_KEY="$SIGN_KEY_MATERIAL" HOME="$CONSUMER_HOME" \
    PATH="$SANITIZED_PATH" /bin/bash "$IDENTITY_SCRIPT" \
    >"$TEST_ROOT/identity-keys-exist.log"
grep -q '认证秘钥已在 GitHub 注册' "$TEST_ROOT/identity-keys-exist.log"
grep -q '签名秘钥已在 GitHub 注册' "$TEST_ROOT/identity-keys-exist.log"
grep -q '开发者信任链身份配置完成' "$TEST_ROOT/identity-keys-exist.log"
if grep -q '^gh:host=github.com:ssh-key ' "$GH_TEST_LOG"; then
    echo "an existing GitHub key was uploaded again" >&2
    exit 1
fi

: >"$GH_TEST_LOG"
GH_HOST=enterprise.invalid GH_TEST_AUTH_STATUS=0 HOME="$CONSUMER_HOME" \
    PATH="$SANITIZED_PATH" \
    /bin/bash "$IDENTITY_SCRIPT" >"$TEST_ROOT/identity-authenticated.log"
grep -q '开发者信任链身份配置完成' \
    "$TEST_ROOT/identity-authenticated.log"
[ "$(grep -c '^gh:host=github.com:api ' "$GH_TEST_LOG")" -eq 2 ]
[ "$(grep -c '^gh:host=github.com:ssh-key add ' "$GH_TEST_LOG")" -eq 2 ]
grep -Fq "gh:host=github.com:ssh-key add $CONSUMER_HOME/.ssh/keys/github_auth.pub" \
    "$GH_TEST_LOG"
grep -Fq "gh:host=github.com:ssh-key add $CONSUMER_HOME/.ssh/keys/git_signing.pub --type signing" \
    "$GH_TEST_LOG"
if grep -q 'enterprise.invalid' "$GH_TEST_LOG"; then
    echo "authenticated gh command inherited a non-github.com host" >&2
    exit 1
fi
[ "$(grep -c '^fresh-apply@example.com ssh-ed25519 ' \
    "$CONSUMER_HOME/.ssh/allowed_signers")" -eq 1 ]

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

# The hook installer and the generated hook both use the Brew-owned scanner
# without relying on the fresh parent process PATH.
mkdir -p "$CONSUMER_WORKTREE/.git/hooks"
HOOK_FILE="$CONSUMER_WORKTREE/.git/hooks/pre-commit"

mv "$BREW_TEST_PREFIX/bin/gitleaks" "$BREW_TEST_PREFIX/bin/gitleaks.fixture"
if PATH="$SANITIZED_PATH" /bin/bash "$HOOK_SCRIPT" \
    >"$TEST_ROOT/hook-missing-gitleaks.log" 2>&1; then
    echo "hook installer unexpectedly succeeded without the fixed gitleaks entry" >&2
    exit 1
fi
grep -q 'Brew 管理的 gitleaks 入口缺失或不可执行' \
    "$TEST_ROOT/hook-missing-gitleaks.log"
[ ! -e "$HOOK_FILE" ]
mv "$BREW_TEST_PREFIX/bin/gitleaks.fixture" "$BREW_TEST_PREFIX/bin/gitleaks"

chmod 644 "$BREW_TEST_PREFIX/bin/gitleaks"
if PATH="$SANITIZED_PATH" /bin/bash "$HOOK_SCRIPT" \
    >"$TEST_ROOT/hook-nonexec-gitleaks.log" 2>&1; then
    echo "hook installer unexpectedly succeeded with a non-executable gitleaks entry" >&2
    exit 1
fi
grep -q 'Brew 管理的 gitleaks 入口缺失或不可执行' \
    "$TEST_ROOT/hook-nonexec-gitleaks.log"
[ ! -e "$HOOK_FILE" ]
chmod +x "$BREW_TEST_PREFIX/bin/gitleaks"

gitleaks_version_status=0
if GITLEAKS_TEST_VERSION_EXIT=73 PATH="$SANITIZED_PATH" \
    /bin/bash "$HOOK_SCRIPT" >"$TEST_ROOT/hook-broken-gitleaks.log" 2>&1; then
    echo "hook installer unexpectedly succeeded with a broken gitleaks entry" >&2
    exit 1
else
    gitleaks_version_status=$?
fi
if [ "$gitleaks_version_status" -ne 73 ]; then
    echo "broken gitleaks entry returned $gitleaks_version_status instead of 73" >&2
    exit 1
fi
grep -q 'Brew 管理的 gitleaks 入口无法正常执行' \
    "$TEST_ROOT/hook-broken-gitleaks.log"
[ ! -e "$HOOK_FILE" ]

mv "$CONSUMER_WORKTREE/.git" "$CONSUMER_WORKTREE/.git.fixture"
if PATH="$SANITIZED_PATH" /bin/bash "$HOOK_SCRIPT" \
    >"$TEST_ROOT/hook-missing-repository.log" 2>&1; then
    echo "hook installer unexpectedly succeeded outside a Git working tree" >&2
    exit 1
fi
grep -q 'dotfiles 工作树不是可管理的 Git 仓库' \
    "$TEST_ROOT/hook-missing-repository.log"
mv "$CONSUMER_WORKTREE/.git.fixture" "$CONSUMER_WORKTREE/.git"

# Symlinks and non-regular filesystem objects are never opened or replaced.
EXTERNAL_HOOK="$TEST_ROOT/external-pre-commit"
printf 'external hook target\n' >"$EXTERNAL_HOOK"
cp "$EXTERNAL_HOOK" "$TEST_ROOT/external-pre-commit.before"
ln -s "$EXTERNAL_HOOK" "$HOOK_FILE"
PATH="$SANITIZED_PATH" /bin/bash "$HOOK_SCRIPT" \
    >"$TEST_ROOT/hook-valid-symlink.log"
grep -q '符号链接或非普通文件，原样保留' \
    "$TEST_ROOT/hook-valid-symlink.log"
[ -L "$HOOK_FILE" ]
[ "$(readlink "$HOOK_FILE")" = "$EXTERNAL_HOOK" ]
cmp "$TEST_ROOT/external-pre-commit.before" "$EXTERNAL_HOOK"
rm "$HOOK_FILE"

DANGLING_TARGET="$TEST_ROOT/dangling-pre-commit-target"
ln -s "$DANGLING_TARGET" "$HOOK_FILE"
PATH="$SANITIZED_PATH" /bin/bash "$HOOK_SCRIPT" \
    >"$TEST_ROOT/hook-dangling-symlink.log"
grep -q '符号链接或非普通文件，原样保留' \
    "$TEST_ROOT/hook-dangling-symlink.log"
[ -L "$HOOK_FILE" ]
[ "$(readlink "$HOOK_FILE")" = "$DANGLING_TARGET" ]
[ ! -e "$DANGLING_TARGET" ]
rm "$HOOK_FILE"

mkfifo "$HOOK_FILE"
PATH="$SANITIZED_PATH" /bin/bash "$HOOK_SCRIPT" >"$TEST_ROOT/hook-fifo.log"
grep -q '符号链接或非普通文件，原样保留' \
    "$TEST_ROOT/hook-fifo.log"
[ -p "$HOOK_FILE" ]
rm "$HOOK_FILE"

printf '#!/usr/bin/env bash\n# Managed by chezmoi (approximate)\necho unmanaged\n' \
    >"$HOOK_FILE"
chmod +x "$HOOK_FILE"
cp "$HOOK_FILE" "$TEST_ROOT/approximate-marker-pre-commit"
PATH="$SANITIZED_PATH" /bin/bash "$HOOK_SCRIPT" \
    >"$TEST_ROOT/hook-approximate-marker.log"
grep -q '已存在非 Chezmoi 管理的 pre-commit hook' \
    "$TEST_ROOT/hook-approximate-marker.log"
cmp "$TEST_ROOT/approximate-marker-pre-commit" "$HOOK_FILE"
rm "$HOOK_FILE"

printf '#!/usr/bin/env bash\necho unmanaged\n' >"$HOOK_FILE"
chmod +x "$HOOK_FILE"
cp "$HOOK_FILE" "$TEST_ROOT/unmanaged-pre-commit"
PATH="$SANITIZED_PATH" /bin/bash "$HOOK_SCRIPT" \
    >"$TEST_ROOT/hook-unmanaged.log"
grep -q '已存在非 Chezmoi 管理的 pre-commit hook' \
    "$TEST_ROOT/hook-unmanaged.log"
cmp "$TEST_ROOT/unmanaged-pre-commit" "$HOOK_FILE"

# The exact historical line-2 marker remains a valid ownership proof and is
# atomically upgraded to the current fail-closed hook.
cat >"$HOOK_FILE" <<'EOF'
#!/usr/bin/env bash
# Managed by chezmoi
if command -v gitleaks &>/dev/null; then
    gitleaks git --pre-commit --staged --redact --verbose .
fi
EOF
chmod +x "$HOOK_FILE"
PATH="$SANITIZED_PATH" /bin/bash "$HOOK_SCRIPT" \
    >"$TEST_ROOT/hook-legacy-managed.log"
[ -x "$HOOK_FILE" ]
grep -q '^# Managed by chezmoi$' "$HOOK_FILE"
if grep -q 'command -v gitleaks' "$HOOK_FILE"; then
    echo "legacy managed hook was not upgraded" >&2
    exit 1
fi
if find "$CONSUMER_WORKTREE/.git/hooks" -name '.pre-commit.*' -print -quit | grep -q .; then
    echo "atomic hook installation left a temporary file behind" >&2
    exit 1
fi

rm "$HOOK_FILE"
rmdir "$CONSUMER_WORKTREE/.git/hooks"
: >"$GITLEAKS_TEST_LOG"
PATH="$SANITIZED_PATH" /bin/bash "$HOOK_SCRIPT" >"$TEST_ROOT/hook-install.log"
[ -d "$CONSUMER_WORKTREE/.git/hooks" ]
[ -x "$HOOK_FILE" ]
grep -q '# Managed by chezmoi' "$HOOK_FILE"
grep -Fq "GITLEAKS_BIN=\"$BREW_TEST_PREFIX/bin/gitleaks\"" "$HOOK_FILE"
if grep -q 'command -v gitleaks' "$HOOK_FILE"; then
    echo "managed hook still depends on the parent PATH" >&2
    exit 1
fi

: >"$GITLEAKS_TEST_LOG"
(
    cd "$CONSUMER_WORKTREE"
    PATH="$SANITIZED_PATH" "$HOOK_FILE"
)
grep -qx 'gitleaks:git --pre-commit --staged --redact --verbose .' \
    "$GITLEAKS_TEST_LOG"

gitleaks_scan_status=0
if (
    cd "$CONSUMER_WORKTREE"
    GITLEAKS_TEST_SCAN_EXIT=79 PATH="$SANITIZED_PATH" "$HOOK_FILE"
); then
    echo "managed hook swallowed a gitleaks scan failure" >&2
    exit 1
else
    gitleaks_scan_status=$?
fi
if [ "$gitleaks_scan_status" -ne 79 ]; then
    echo "gitleaks scan failure returned $gitleaks_scan_status instead of 79" >&2
    exit 1
fi

mv "$BREW_TEST_PREFIX/bin/gitleaks" "$BREW_TEST_PREFIX/bin/gitleaks.fixture"
if PATH="$SANITIZED_PATH" "$HOOK_FILE" >"$TEST_ROOT/hook-runtime-missing.log" 2>&1; then
    echo "managed hook silently skipped its missing gitleaks runtime" >&2
    exit 1
fi
grep -q 'Brew 管理的 gitleaks 入口缺失或不可执行' \
    "$TEST_ROOT/hook-runtime-missing.log"
mv "$BREW_TEST_PREFIX/bin/gitleaks.fixture" "$BREW_TEST_PREFIX/bin/gitleaks"

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
if [ -s "$PARENT_PATH_POISON_LOG" ]; then
    echo "a post-bundle consumer invoked a poisoned parent-PATH tool" >&2
    cat "$PARENT_PATH_POISON_LOG" >&2
    exit 1
fi

printf 'Fresh apply deterministic restore contract passed\n'
