#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT
export PROBE_STATE="$TEST_ROOT/state" PROBE_LOG="$TEST_ROOT/rustup.log"
export PROBE_CHAIN=stable-test-host PROBE_FAIL=none
PREFIX="$TEST_ROOT/brew"
mkdir -p "$PREFIX/opt/rustup/bin" "$PREFIX/bin" "$TEST_ROOT/poison" "$PROBE_STATE"

cat >"$PREFIX/opt/rustup/bin/rustup" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$PROBE_LOG"
case "$1 ${2:-}" in
    'toolchain install')
        [[ "$PROBE_FAIL" != install ]] || exit 32
        [[ "$3" == "$PROBE_CHAIN" && "$4 $5 $6" == '--profile minimal --no-self-update' ]]
        touch "$PROBE_STATE/installed"
        ;;
    'toolchain list')
        [[ "$PROBE_FAIL" != list ]] || exit 34
        if [[ -f "$PROBE_STATE/installed" ]]; then printf '%s (default)\n' "$PROBE_CHAIN"; fi
        ;;
    'component list')
        [[ "$3 $4 $5" == "--installed --toolchain $PROBE_CHAIN" ]]
        for item in rustfmt clippy rust-src; do
            if [[ -f "$PROBE_STATE/$item" ]]; then printf '%s\n' "$item"; fi
        done
        ;;
    'component add')
        [[ "$PROBE_FAIL" != component ]] || exit 33
        [[ "$3 $4" == "--toolchain $PROBE_CHAIN" ]]
        touch "$PROBE_STATE/$5"
        if [[ "$5" == rust-src ]]; then
            mkdir -p "$PROBE_STATE/sysroot/lib/rustlib/src/rust/library/core/src"
            touch "$PROBE_STATE/sysroot/lib/rustlib/src/rust/library/core/src/lib.rs"
        fi
        ;;
    *)
        case "$1" in
            default)
                [[ "$#" -eq 1 ]] # No default setter allowed.
                [[ "$PROBE_FAIL" != default ]] || exit 31
                printf '%s (default)\n' "$PROBE_CHAIN"
                ;;
            run)
                [[ "$2" == "$PROBE_CHAIN" ]]
                [[ "$PROBE_FAIL" != executable ]] || exit 47
                if [[ "$3 $4" == 'rustc --print' ]]; then
                    printf '%s/sysroot\n' "$PROBE_STATE"
                else
                    printf '%s fixture-version\n' "$3"
                fi
                ;;
            *) exit 98 ;;
        esac
        ;;
esac
EOF
chmod +x "$PREFIX/opt/rustup/bin/rustup"
for tool in rustup rustc cargo; do
    printf '#!/bin/sh\nprintf "poison\\n" >>"$PROBE_LOG"\nexit 97\n' >"$TEST_ROOT/poison/$tool"
    chmod +x "$TEST_ROOT/poison/$tool"
done

run_provision() {
    PATH="$TEST_ROOT/poison:/usr/bin:/bin" bash "$REPO_ROOT/scripts/rust/provision.sh" "$PREFIX"
}
expect_failure() {
    local mode="$1" expected="$2" status=0
    PROBE_FAIL="$mode" run_provision >"$TEST_ROOT/failure.log" 2>&1 || status=$?
    [[ "$status" == "$expected" ]] || {
        cat "$TEST_ROOT/failure.log"
        exit 1
    }
    ! grep -Fq 'Rust default toolchain ready:' "$TEST_ROOT/failure.log"
}

expect_failure default 31
expect_failure list 34
expect_failure install 32
expect_failure component 33
run_provision >"$TEST_ROOT/first.log"
grep -Fq 'Rust default toolchain ready:' "$TEST_ROOT/first.log"
[[ "$(grep -c '^component add ' "$PROBE_LOG")" == 4 ]] # one injected failure + three successful additions
before="$(grep -Ec '^(component add|toolchain install)' "$PROBE_LOG")"
run_provision >"$TEST_ROOT/repeat.log"
[[ "$(grep -Ec '^(component add|toolchain install)' "$PROBE_LOG")" == "$before" ]]
expect_failure executable 47
mv "$PROBE_STATE/sysroot/lib/rustlib/src/rust/library/core/src/lib.rs" "$PROBE_STATE/lib.rs.saved"
expect_failure none 1 # Component metadata alone must not claim rust-src readiness.
mv "$PROBE_STATE/lib.rs.saved" "$PROBE_STATE/sysroot/lib/rustlib/src/rust/library/core/src/lib.rs"

# Existing pinned defaults and the caller's project override are not rewritten.
export PROBE_CHAIN=1.97.1-test-host RUSTUP_TOOLCHAIN=nightly-project
run_provision >"$TEST_ROOT/pinned.log"
grep -Fq 'Rust default toolchain ready: 1.97.1-test-host' "$TEST_ROOT/pinned.log"
[[ "$RUSTUP_TOOLCHAIN" == nightly-project ]]
[[ "$(grep -Ec '^(component add|toolchain install)' "$PROBE_LOG")" == "$before" ]]
! grep -Eq '^(poison|update|self|default .)' "$PROBE_LOG"

chmod -x "$PREFIX/opt/rustup/bin/rustup"
expect_failure none 1
chmod +x "$PREFIX/opt/rustup/bin/rustup"
mv "$PREFIX/opt/rustup/bin/rustup" "$PREFIX/opt/rustup/bin/rustup.saved"
expect_failure none 1
mv "$PREFIX/opt/rustup/bin/rustup.saved" "$PREFIX/opt/rustup/bin/rustup"

# Render every supported platform; poison legacy global Rust and preserve
# explicitly inherited project executables. No tool is installed by this test.
ZSH_BIN="$(command -v zsh)"
for platform in arm intel linux; do
    case "$platform" in
        arm)
            data='{"is_mac":true,"is_linux":false,"is_arm64":true}'
            canonical=/opt/homebrew
            ;;
        intel)
            data='{"is_mac":true,"is_linux":false,"is_arm64":false}'
            canonical=/usr/local
            ;;
        linux)
            data='{"is_mac":false,"is_linux":true,"is_arm64":false}'
            canonical=/home/linuxbrew/.linuxbrew
            ;;
    esac
    for pair in 'bootstrap home/.chezmoiscripts/run_onchange_after_25_rust_toolchain.sh.tmpl' 'shell home/dot_config/zsh/homebrew.zsh.tmpl'; do
        read -r label template <<<"$pair"
        chezmoi execute-template --source="$REPO_ROOT" --override-data "$data" \
            <"$REPO_ROOT/$template" >"$TEST_ROOT/$platform-$label"
        grep -Fq "BREW_PREFIX=\"$canonical\"" "$TEST_ROOT/$platform-$label"
        sed -i.bak "s#$canonical#$PREFIX#g" "$TEST_ROOT/$platform-$label"
    done
    bash "$TEST_ROOT/$platform-bootstrap" >"$TEST_ROOT/$platform.log"
    grep -Fq 'Rust default toolchain ready:' "$TEST_ROOT/$platform.log"
    for tool in rustc cargo; do
        ln -sf "$TEST_ROOT/poison/$tool" "$PREFIX/bin/$tool"
        ln -sf "$PREFIX/opt/rustup/bin/rustup" "$PREFIX/opt/rustup/bin/$tool"
    done
    env OWNER="$TEST_ROOT/$platform-shell" EXPECTED_PREFIX="$PREFIX" PROJECT_BIN="$TEST_ROOT/poison" \
        PATH="$PREFIX/bin:/usr/bin:/bin" "$ZSH_BIN" -dfc '
            source "$OWNER"
            [[ "$commands[rustc]" == "$EXPECTED_PREFIX/opt/rustup/bin/rustc" ]] || exit 51
            [[ "$commands[cargo]" == "$EXPECTED_PREFIX/opt/rustup/bin/cargo" ]] || exit 52
            before="$PATH"
            source "$OWNER"
            [[ "$PATH" == "$before" ]] || exit 53
            path=("$PROJECT_BIN" "$EXPECTED_PREFIX/bin" /usr/bin /bin)
            source "$OWNER"
            [[ "$commands[rustc]" == "$PROJECT_BIN/rustc" ]] || exit 54
            [[ "$RUSTUP_TOOLCHAIN" == nightly-project ]] || exit 55
        '
done
printf 'Rust missing-only bootstrap, failure propagation, and three-platform PATH contracts passed\n'
