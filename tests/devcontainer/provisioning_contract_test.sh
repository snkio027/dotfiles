#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_ROOT="$(mktemp -d)"
TEST_HOME="$TEST_ROOT/home"
FAKE_BIN="$TEST_ROOT/bin"
ATTEMPT_FILE="$TEST_ROOT/attempts"
LOG_FILE="$TEST_ROOT/provisioning.log"

cleanup() {
    rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

fail() {
    echo "$1" >&2
    exit 1
}

mkdir -p "$TEST_HOME/.config/nvim" "$FAKE_BIN"
cp "$REPO_ROOT/home/dot_config/nvim/lazy-lock.json" "$TEST_HOME/.config/nvim/lazy-lock.json"

cat >"$FAKE_BIN/chezmoi" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat >"$FAKE_BIN/nvim" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
attempts="${DOTFILES_TEST_ATTEMPT_FILE:?}"
attempt=0
[[ ! -f "$attempts" ]] || attempt="$(<"$attempts")"
attempt=$((attempt + 1))
printf '%d\n' "$attempt" >"$attempts"

if [[ "${DOTFILES_TEST_NVIM_MODE:-fail}" == "recover" && "$attempt" -eq 2 ]]; then
    printf 'Mason missing-tool provisioning 21/21\n'
    printf 'Mason required tools: codelldb,debugpy,delve,gersemi,gofumpt,goimports,golangci-lint,gopls,hadolint,js-debug-adapter,markdown-toc,markdownlint-cli2,pyright,ruff,shellcheck,shfmt,sqlfluff,stylua,tflint,ty,zls\n'
    exit 0
fi

echo 'injected Neovim provisioning failure' >&2
exit 1
EOF
chmod +x "$FAKE_BIN/chezmoi" "$FAKE_BIN/nvim"

# A transient failure is repaired only by the post-create provisioner, and
# completion produces a durable observation manifest.
if ! HOME="$TEST_HOME" PATH="$FAKE_BIN:$PATH" \
    XDG_STATE_HOME="$TEST_HOME/.local/state" \
    DOTFILES_NVIM_BIN="$FAKE_BIN/nvim" \
    DOTFILES_NVIM_PROVISION_ATTEMPTS=3 \
    DOTFILES_NVIM_PROVISION_RETRY_DELAY_SECONDS=0 \
    DOTFILES_MASON_TIMEOUT_MS=1 \
    DOTFILES_TEST_ATTEMPT_FILE="$ATTEMPT_FILE" \
    DOTFILES_TEST_NVIM_MODE=recover \
    "$REPO_ROOT/.devcontainer/provision-nvim.sh" "$REPO_ROOT" >"$LOG_FILE" 2>&1; then
    cat "$LOG_FILE" >&2
    fail "Transient provisioning did not recover"
fi

[[ "$(<"$ATTEMPT_FILE")" -eq 2 ]] || fail "Transient provisioning did not stop after the successful retry"
grep -Fq 'post-create Neovim provisioning retry 1/3' "$LOG_FILE"
grep -Fq 'required tools complete: 21/21' "$LOG_FILE"
grep -Fq 'post-create Neovim provisioning complete' "$LOG_FILE"
[[ "$(wc -l <"$TEST_HOME/.local/state/dotfiles/mason-tools.txt" | tr -d ' ')" -eq 21 ]] ||
    fail "Successful provisioning did not persist the complete manifest"

# Exhaustion must propagate through the actual post-create entry point. The
# fake chezmoi succeeds, so the only failure owner is Neovim provisioning.
rm -f -- "$ATTEMPT_FILE" "$LOG_FILE" "$TEST_HOME/.local/state/dotfiles/mason-tools.txt"
if HOME="$TEST_HOME" PATH="$FAKE_BIN:$PATH" \
    XDG_STATE_HOME="$TEST_HOME/.local/state" \
    DOTFILES_NVIM_BIN="$FAKE_BIN/nvim" \
    DOTFILES_NVIM_PROVISION_ATTEMPTS=3 \
    DOTFILES_NVIM_PROVISION_RETRY_DELAY_SECONDS=0 \
    DOTFILES_MASON_TIMEOUT_MS=1 \
    DOTFILES_TEST_ATTEMPT_FILE="$ATTEMPT_FILE" \
    DOTFILES_TEST_NVIM_MODE=fail \
    "$REPO_ROOT/.devcontainer/post-create.sh" "$REPO_ROOT" >"$LOG_FILE" 2>&1; then
    fail "post-create succeeded after injected provisioning exhaustion"
fi

[[ "$(<"$ATTEMPT_FILE")" -eq 3 ]] || fail "Provisioning exhaustion did not use exactly three attempts"
grep -Fq 'Dev Container post-create start' "$LOG_FILE"
grep -Fq 'post-create Neovim provisioning retry 1/3' "$LOG_FILE"
grep -Fq 'post-create Neovim provisioning retry 2/3' "$LOG_FILE"
grep -Fq 'Dev Container Neovim provisioning failed after 3 attempts' "$LOG_FILE"
if grep -Fq 'Dev Container post-create complete' "$LOG_FILE"; then
    fail "post-create reported completion after provisioning exhaustion"
fi

observer="$(sed -n '/^assert_container_state()/,/^}/p' "$REPO_ROOT/tests/devcontainer/lifecycle_smoke.sh")"
if grep -Eqi 'nvim.*MasonTools(Install|Update)|chezmoi[[:space:]]+apply|brew[[:space:]]+(install|bundle)|go[[:space:]]+install' <<<"$observer"; then
    fail "Dev Container state validation contains a repair command"
fi

printf 'Dev Container provisioning ownership and exhaustion tests passed\n'
