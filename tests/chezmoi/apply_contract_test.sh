#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

BREW_TEMPLATE="$REPO_ROOT/home/.chezmoiscripts/run_onchange_after_20_brew_bundle.sh.tmpl"
DEFAULTS_TEMPLATE="$REPO_ROOT/home/.chezmoiscripts/run_onchange_after_90_macos_defaults.sh.tmpl"
BREW_SCRIPT="$TEST_ROOT/brew_bundle.sh"
DEVCONTAINER_BREW_SCRIPT="$TEST_ROOT/devcontainer_brew_bundle.sh"
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

printf 'Chezmoi apply side-effect tests passed\n'
