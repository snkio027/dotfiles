#!/usr/bin/env bash

set -euo pipefail

PROFILE="${1:?profile is required}"

fail() {
    echo "$1" >&2
    exit 1
}

exercise() {
    local command_name="${1:?command is required}"
    shift
    command -v "$command_name" >/dev/null || fail "$PROFILE profile command is unavailable: $command_name"
    "$command_name" "$@" >/dev/null 2>&1 || fail "$PROFILE profile command is unusable: $command_name"
}

exercise_llvm() {
    local llvm_bin
    llvm_bin="$(brew --prefix llvm)/bin/${1:?LLVM command is required}"
    [[ -x "$llvm_bin" ]] || fail "$PROFILE profile LLVM command is unavailable: $llvm_bin"
    "$llvm_bin" --version >/dev/null 2>&1 || fail "$PROFILE profile LLVM command is unusable: $llvm_bin"
}

case "$PROFILE" in
    core)
        exercise age --version
        exercise ccache --version
        exercise chezmoi --version
        exercise cmake --version
        exercise gh --version
        exercise git --version
        exercise go version
        exercise helm version --short
        exercise kubectl version --client=true
        exercise_llvm clang
        exercise_llvm clangd
        exercise nvim --version
        exercise ninja --version
        exercise node --version
        exercise pkgconf --version
        exercise python3 --version
        exercise cargo --version
        exercise rustc --version
        exercise rust-analyzer --version
        exercise sops --version
        exercise tree-sitter --version
        exercise uv --version
        exercise zig version
        ;;
    quality)
        exercise actionlint --version
        exercise atuin --version
        exercise chezmoi --version
        exercise cmake --version
        exercise devcontainer --version
        exercise eza --version
        exercise fd --version
        exercise fzf --version
        exercise gitleaks version
        exercise hadolint --version
        exercise lazygit --version
        exercise_llvm clangd
        exercise nvim --version
        exercise ninja --version
        exercise python3 --version
        exercise rg --version
        exercise rust-analyzer --version
        exercise shellcheck --version
        exercise shfmt --version
        exercise starship --version
        exercise stylua --version
        exercise taplo --version
        exercise tree-sitter --version
        exercise uv --version
        exercise wget --version
        exercise yazi --version
        exercise zellij --version
        exercise zizmor --version
        exercise zsh --version
        [[ -f "$(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ]] ||
            fail "quality profile zsh-autosuggestions plugin is unavailable"
        [[ -f "$(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]] ||
            fail "quality profile zsh-syntax-highlighting plugin is unavailable"
        ;;
    *)
        fail "unsupported Brew profile: $PROFILE"
        ;;
esac

printf 'Brew %s profile executable smoke passed\n' "$PROFILE"
