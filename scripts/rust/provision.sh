#!/usr/bin/env bash
# Shared by chezmoi and CI. Install missing default-toolchain components only.
set -euo pipefail

BREW_PREFIX="${1:?absolute Homebrew prefix is required}"
[[ "$BREW_PREFIX" == /* ]] || {
    echo 'Homebrew prefix must be absolute' >&2
    exit 1
}
RUSTUP_BIN="$BREW_PREFIX/opt/rustup/bin/rustup"
[[ -x "$RUSTUP_BIN" ]] || {
    echo "Brew rustup is missing or not executable: $RUSTUP_BIN" >&2
    exit 1
}
export PATH="$BREW_PREFIX/opt/rustup/bin:$PATH"
export RUSTUP_AUTO_INSTALL=0

# `default` ignores project overrides. Homebrew supplies a stable fallback on
# fresh machines; an existing user default (including a pinned version) wins.
# Never run `rustup default stable`, `update`, or a second rustup installer.
default_output="$("$RUSTUP_BIN" default)"
toolchain="${default_output%% *}"
[[ -n "$toolchain" && "$toolchain" != -* ]] || {
    echo 'Invalid rustup default' >&2
    exit 1
}
installed="$("$RUSTUP_BIN" toolchain list)"
present=false
while IFS= read -r line; do
    name="${line%% *}"
    if [[ "$name" == "$toolchain" || "$name" == "$toolchain"-* ]]; then
        present=true
    fi
done <<<"$installed"
if [[ "$present" == false ]]; then
    "$RUSTUP_BIN" toolchain install "$toolchain" --profile minimal --no-self-update
fi

components="$("$RUSTUP_BIN" component list --installed --toolchain "$toolchain")"
for component in rustfmt clippy rust-src; do
    if ! grep -Eq "^${component}(-[^[:space:]]+)?([[:space:]]|$)" <<<"$components"; then
        "$RUSTUP_BIN" component add --toolchain "$toolchain" "$component"
    fi
done

# Successful installation messages alone are not a readiness receipt.
for tool in rustc cargo rustfmt clippy-driver; do
    "$RUSTUP_BIN" run "$toolchain" "$tool" --version
done
sysroot="$("$RUSTUP_BIN" run "$toolchain" rustc --print sysroot)"
[[ -f "$sysroot/lib/rustlib/src/rust/library/core/src/lib.rs" ]] || {
    echo "rust-src is missing from $sysroot" >&2
    exit 1
}
printf 'Rust default toolchain ready: %s (missing-only provisioning)\n' "$toolchain"
