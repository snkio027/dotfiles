#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

LINUX_DATA='{"is_mac":false,"is_linux":true,"is_arm64":false,"machine_profile":"workstation"}'
MACOS_DATA='{"is_mac":true,"is_linux":false,"is_arm64":true,"machine_profile":"workstation"}'
DEVCONTAINER_DATA='{"is_mac":false,"is_linux":true,"is_arm64":false,"machine_profile":"devcontainer"}'
LINUX_PREFIX="/home/linuxbrew/.linuxbrew"

render() {
    local data="$1" template="$2" output="$3"
    chezmoi execute-template --source="$REPO_ROOT" --override-data "$data" \
        <"$REPO_ROOT/$template" >"$output"
}

render_profile() {
    local name="$1" data="$2" profile_dir output
    profile_dir="$TEST_ROOT/render-$name"
    mkdir -p "$profile_dir"
    for template in \
        home/dot_zshenv.tmpl \
        home/dot_zprofile.tmpl \
        home/dot_zshrc.tmpl \
        home/dot_config/zsh/homebrew.zsh.tmpl \
        home/dot_config/zsh/exports.zsh.tmpl; do
        output="$profile_dir/$(basename "${template%.tmpl}")"
        render "$data" "$template" "$output"
        zsh -n "$output"
    done
}

render_profile linux "$LINUX_DATA"
render_profile macos "$MACOS_DATA"
render_profile devcontainer "$DEVCONTAINER_DATA"

LINUX_RENDER="$TEST_ROOT/render-linux"
LINUX_HOMEBREW="$LINUX_RENDER/homebrew.zsh"
LINUX_ZPROFILE="$LINUX_RENDER/dot_zprofile"
LINUX_ZSHRC="$LINUX_RENDER/dot_zshrc"
LINUX_EXPORTS="$LINUX_RENDER/exports.zsh"

grep -q "HOMEBREW_PREFIX=\"$LINUX_PREFIX\"" "$LINUX_HOMEBREW"
grep -q 'homebrew.zsh' "$LINUX_ZPROFILE"
grep -q 'homebrew.zsh' "$LINUX_ZSHRC"
if grep -Eq 'brew (shellenv|--prefix)' "$LINUX_HOMEBREW" "$LINUX_ZPROFILE" "$LINUX_ZSHRC"; then
    echo "Linux Zsh startup must not execute brew subprocesses" >&2
    exit 1
fi
if grep -Eq '/opt/homebrew|/usr/local/(bin|sbin)' \
    "$LINUX_ZPROFILE" "$LINUX_ZSHRC" "$LINUX_EXPORTS"; then
    echo "Linux Zsh rendering is polluted by a macOS Homebrew prefix" >&2
    exit 1
fi
if grep -Fq '/home/linuxbrew/.linuxbrew' "$LINUX_EXPORTS"; then
    echo "exports.zsh must not duplicate the managed PATH owner" >&2
    exit 1
fi
grep -Eq '^brew "zsh" if OS\.linux\?' "$REPO_ROOT/brew/profiles/workstation.Brewfile"
grep -Eq '^brew "zsh"([[:space:]]|$)' "$REPO_ROOT/brew/profiles/devcontainer.Brewfile"
if grep -R -Eq '(^|[^[:alnum:]_])chsh([[:space:]]|$)' \
    "$REPO_ROOT/home/.chezmoiscripts" "$REPO_ROOT/home/dot_zshenv.tmpl" \
    "$REPO_ROOT/home/dot_zprofile.tmpl" "$REPO_ROOT/home/dot_zshrc.tmpl" \
    "$REPO_ROOT/home/dot_config/zsh"; then
    echo "Zsh installation must not change the login shell" >&2
    exit 1
fi

RUNTIME_PREFIX="$LINUX_PREFIX"
if [[ "$(uname -s)" != "Linux" ]]; then
    # Local macOS validation executes the exact rendered logic against an
    # isolated prefix mirror; CI exercises the canonical Linuxbrew path.
    RUNTIME_PREFIX="$TEST_ROOT/linuxbrew"
    mkdir -p "$RUNTIME_PREFIX/bin" "$RUNTIME_PREFIX/share/zsh"
    ln -s "$(command -v brew)" "$RUNTIME_PREFIX/bin/brew"
    ln -s "$(command -v zsh)" "$RUNTIME_PREFIX/bin/zsh"
    ln -s "$(brew --prefix)/share/zsh/site-functions" \
        "$RUNTIME_PREFIX/share/zsh/site-functions"
    ln -s "$(brew --prefix zsh-autosuggestions)/share/zsh-autosuggestions" \
        "$RUNTIME_PREFIX/share/zsh-autosuggestions"
    ln -s "$(brew --prefix zsh-syntax-highlighting)/share/zsh-syntax-highlighting" \
        "$RUNTIME_PREFIX/share/zsh-syntax-highlighting"
fi
RUNTIME_ZSH="$RUNTIME_PREFIX/bin/zsh"

RUNTIME_ROOT="$TEST_ROOT/runtime"
RUNTIME_HOME="$RUNTIME_ROOT/home"
RUNTIME_CONFIG="$RUNTIME_HOME/.config/zsh"
mkdir -p "$RUNTIME_CONFIG"

cp "$TEST_ROOT/render-linux/dot_zshenv" "$RUNTIME_HOME/.zshenv"
cp "$TEST_ROOT/render-linux/dot_zprofile" "$RUNTIME_HOME/.zprofile"
cp "$TEST_ROOT/render-linux/dot_zshrc" "$RUNTIME_HOME/.zshrc"
cp "$LINUX_HOMEBREW" "$RUNTIME_CONFIG/homebrew.zsh"
cp "$LINUX_EXPORTS" "$RUNTIME_CONFIG/exports.zsh"
ln -s "$REPO_ROOT/home/dot_config/zsh/aliases.zsh" "$RUNTIME_CONFIG/aliases.zsh"
ln -s "$REPO_ROOT/home/dot_config/zsh/plugins.zsh" "$RUNTIME_CONFIG/plugins.zsh"

if [[ "$RUNTIME_PREFIX" != "$LINUX_PREFIX" ]]; then
    sed -i.bak "s#$LINUX_PREFIX#$RUNTIME_PREFIX#g" \
        "$RUNTIME_CONFIG/homebrew.zsh" "$RUNTIME_CONFIG/exports.zsh"
    rm -f "$RUNTIME_CONFIG/homebrew.zsh.bak" "$RUNTIME_CONFIG/exports.zsh.bak"
fi

# A non-login `zsh -ic` must not read .zprofile. Appending this sentinel turns
# accidental login behavior into a hard failure without changing the real file.
printf '\nprint -u2 -- ".zprofile unexpectedly executed"\nreturn 97\n' >>"$RUNTIME_HOME/.zprofile"

RUNTIME_ASSERTIONS="$TEST_ROOT/runtime_assertions.zsh"
cat >"$RUNTIME_ASSERTIONS" <<'EOF'
fail() {
    print -u2 -- "$1"
    exit 1
}

[[ "$HOMEBREW_PREFIX" == "$EXPECTED_HOMEBREW_PREFIX" ]] || fail "wrong HOMEBREW_PREFIX: $HOMEBREW_PREFIX"
[[ "$commands[brew]" == "$EXPECTED_HOMEBREW_PREFIX/bin/brew" ]] || fail "brew resolved outside Linuxbrew: $commands[brew]"
# Context hooks such as Carapace may prepend a command shim directory. Keep the
# managed Linuxbrew group present, contiguous, and internally ordered.
llvm_path_index="${path[(I)${EXPECTED_HOMEBREW_PREFIX}/opt/llvm/bin]}"
brew_bin_index="${path[(I)${EXPECTED_HOMEBREW_PREFIX}/bin]}"
brew_sbin_index="${path[(I)${EXPECTED_HOMEBREW_PREFIX}/sbin]}"
(( llvm_path_index > 0 &&
    brew_bin_index == llvm_path_index + 1 &&
    brew_sbin_index == brew_bin_index + 1 )) || fail "Linuxbrew PATH group is missing, split, or out of order: ${(j/:/)path}"
[[ "$fpath[(I)$EXPECTED_HOMEBREW_PREFIX/share/zsh/site-functions]" -gt 0 ]] || fail "Linuxbrew completion path missing"
(( ${+functions[_brew]} )) || fail "Homebrew completion was not registered"
(( ${+functions[_zsh_autosuggest_start]} )) || fail "zsh-autosuggestions was not loaded"
(( ${+functions[_zsh_highlight]} )) || fail "zsh-syntax-highlighting was not loaded"
[[ "$functions_source[_zsh_autosuggest_start]" == "$EXPECTED_HOMEBREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ]] || fail "autosuggestions came from the wrong prefix"
[[ "$functions_source[_zsh_highlight]" == "$EXPECTED_HOMEBREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]] || fail "syntax-highlighting came from the wrong prefix"

source "$XDG_CONFIG_HOME/zsh/homebrew.zsh" || fail "first repeated source failed"
source "$XDG_CONFIG_HOME/zsh/homebrew.zsh" || fail "second repeated source failed"

count_entry() {
    local expected="$1"
    shift
    local entry count=0
    for entry in "$@"; do
        [[ "$entry" == "$expected" ]] && (( count += 1 ))
    done
    print -r -- "$count"
}

[[ "$(count_entry "$EXPECTED_HOMEBREW_PREFIX/bin" "${path[@]}")" == 1 ]] || fail "Linuxbrew bin is duplicated"
[[ "$(count_entry "$EXPECTED_HOMEBREW_PREFIX/sbin" "${path[@]}")" == 1 ]] || fail "Linuxbrew sbin is duplicated"
[[ "$(count_entry "$EXPECTED_HOMEBREW_PREFIX/share/zsh/site-functions" "${fpath[@]}")" == 1 ]] || fail "Linuxbrew FPATH is duplicated"

assert_unique_entries() {
    local label="$1" entry
    shift
    typeset -A seen
    for entry in "$@"; do
        (( ${+seen[$entry]} )) && fail "$label contains duplicate entry: $entry"
        seen[$entry]=1
    done
}

assert_unique_entries PATH "${path[@]}"
assert_unique_entries FPATH "${fpath[@]}"
[[ "${(j/:/)path}" != *'/opt/homebrew'* ]] || fail "macOS Homebrew polluted PATH"
[[ "${(j/:/)fpath}" != *'/opt/homebrew'* ]] || fail "macOS Homebrew polluted FPATH"
EOF

if ! env -u HOMEBREW_PREFIX -u HOMEBREW_CELLAR -u HOMEBREW_REPOSITORY \
    HOME="$RUNTIME_HOME" \
    ZDOTDIR="$RUNTIME_HOME" \
    XDG_CONFIG_HOME="$RUNTIME_HOME/.config" \
    XDG_DATA_HOME="$RUNTIME_HOME/.local/share" \
    XDG_STATE_HOME="$RUNTIME_HOME/.local/state" \
    XDG_CACHE_HOME="$RUNTIME_HOME/.cache" \
    TERM="xterm-256color" \
    EXPECTED_HOMEBREW_PREFIX="$RUNTIME_PREFIX" \
    PATH="/usr/bin:/bin" \
    "$RUNTIME_ZSH" -d -ic "source '$RUNTIME_ASSERTIONS'" \
    >"$TEST_ROOT/non-login.stdout" 2>"$TEST_ROOT/non-login.stderr"; then
    cat "$TEST_ROOT/non-login.stderr" >&2
    exit 1
fi

BOOTSTRAP="$TEST_ROOT/linux-bootstrap.sh"
BOOTSTRAP_BIN="$TEST_ROOT/bootstrap-bin"
BOOTSTRAP_LOG="$TEST_ROOT/bootstrap.log"
render "$LINUX_DATA" home/.chezmoiscripts/run_once_before_10_install_brew.sh.tmpl "$BOOTSTRAP"
bash -n "$BOOTSTRAP"
if grep -Fq 'brew install gcc || true' "$BOOTSTRAP"; then
    echo "Linux bootstrap still ignores gcc installation failures" >&2
    exit 1
fi
mkdir -p "$BOOTSTRAP_BIN"
cat >"$BOOTSTRAP_BIN/brew" <<'EOF'
#!/bin/sh
echo "simulated brew failure" >&2
exit 42
EOF
chmod +x "$BOOTSTRAP_BIN/brew"
if PATH="$BOOTSTRAP_BIN" /bin/bash "$BOOTSTRAP" >"$BOOTSTRAP_LOG" 2>&1; then
    echo "Linux bootstrap succeeded after a simulated gcc installation failure" >&2
    exit 1
fi
grep -q 'Linuxbrew 无法安装 gcc；初始化已停止' "$BOOTSTRAP_LOG"
grep -q 'build-essential procps curl file git' "$BOOTSTRAP_LOG"
grep -q '/home/linuxbrew/.linuxbrew/bin/brew install gcc' "$BOOTSTRAP_LOG"

printf 'Linux non-login Zsh and bootstrap failure tests passed\n'
