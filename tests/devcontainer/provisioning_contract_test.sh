#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_ROOT="$(mktemp -d)"
TEST_HOME="$TEST_ROOT/home"
FAKE_BIN="$TEST_ROOT/bin"
ATTEMPT_FILE="$TEST_ROOT/attempts"
LOG_FILE="$TEST_ROOT/provisioning.log"
CHEZMOI_ARGV_LOG="$TEST_ROOT/chezmoi.argv"
CHEZMOI_MARKER="$TEST_ROOT/fake-chezmoi.executed"

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
set -euo pipefail
{
    printf 'call'
    printf ' %q' "$@"
    printf '\n'
} >>"${DOTFILES_TEST_CHEZMOI_ARGV_LOG:?}"
printf 'fake-chezmoi\n' >"${DOTFILES_TEST_CHEZMOI_MARKER:?}"
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

ROOT_TEST_ENV=()
if [[ "$(id -un)" == "root" ]]; then
    REAL_ID="$(command -v id)"
    cat >"$FAKE_BIN/id" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$#" -eq 1 && "$1" == "-un" ]]; then
    printf 'vscode\n'
    exit 0
fi
exec "${DOTFILES_TEST_REAL_ID:?}" "$@"
EOF
    chmod +x "$FAKE_BIN/id"
    ROOT_TEST_ENV=(DOTFILES_TEST_REAL_ID="$REAL_ID")
fi

grep -Fq 'if "$CHEZMOI_BIN" init --apply --source="$WORKSPACE_FOLDER"; then' \
    "$REPO_ROOT/.devcontainer/post-create.sh" ||
    fail "post-create does not invoke the resolved chezmoi path"
if grep -Eq '^[[:space:]]*(if[[:space:]]+)?chezmoi[[:space:]]' "$REPO_ROOT/.devcontainer/post-create.sh"; then
    fail "post-create contains a bare chezmoi invocation"
fi
RESOLVE_LINE="$(grep -nF 'CHEZMOI_BIN="$(command -v chezmoi || true)"' "$REPO_ROOT/.devcontainer/post-create.sh" | cut -d: -f1)"
PATH_LINE="$(grep -nF 'export PATH=' "$REPO_ROOT/.devcontainer/post-create.sh" | cut -d: -f1)"
[[ -n "$RESOLVE_LINE" && -n "$PATH_LINE" && "$RESOLVE_LINE" -lt "$PATH_LINE" ]] ||
    fail "post-create must resolve chezmoi before modifying PATH"

assert_invalid_chezmoi_override() {
    local override="${1:?override is required}"
    local label="${2:?label is required}"
    local invalid_log="$TEST_ROOT/$label.log"

    rm -f -- "$ATTEMPT_FILE" "$CHEZMOI_ARGV_LOG" "$CHEZMOI_MARKER" "$invalid_log"
    if env "${ROOT_TEST_ENV[@]}" \
        HOME="$TEST_HOME" PATH="$FAKE_BIN:$PATH" \
        XDG_STATE_HOME="$TEST_HOME/.local/state" \
        DOTFILES_CHEZMOI_BIN="$override" \
        DOTFILES_NVIM_BIN="$FAKE_BIN/nvim" \
        DOTFILES_TEST_ATTEMPT_FILE="$ATTEMPT_FILE" \
        "$REPO_ROOT/.devcontainer/post-create.sh" "$REPO_ROOT" >"$invalid_log" 2>&1; then
        fail "$label chezmoi override was accepted"
    fi
    grep -Fq 'chezmoi binary must be an executable absolute path' "$invalid_log"
    [[ ! -e "$ATTEMPT_FILE" ]] || fail "$label override reached Neovim provisioning"
    [[ ! -e "$CHEZMOI_MARKER" ]] || fail "$label override executed the fake chezmoi binary"
}

NONEXECUTABLE_CHEZMOI="$TEST_ROOT/nonexecutable-chezmoi"
printf '#!/usr/bin/env bash\nexit 0\n' >"$NONEXECUTABLE_CHEZMOI"
chmod 0644 "$NONEXECUTABLE_CHEZMOI"
assert_invalid_chezmoi_override "chezmoi" "relative"
assert_invalid_chezmoi_override "$NONEXECUTABLE_CHEZMOI" "nonexecutable"

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
if env "${ROOT_TEST_ENV[@]}" \
    HOME="$TEST_HOME" PATH="$FAKE_BIN:$PATH" \
    XDG_STATE_HOME="$TEST_HOME/.local/state" \
    DOTFILES_CHEZMOI_BIN="$FAKE_BIN/chezmoi" \
    DOTFILES_NVIM_BIN="$FAKE_BIN/nvim" \
    DOTFILES_NVIM_PROVISION_ATTEMPTS=3 \
    DOTFILES_NVIM_PROVISION_RETRY_DELAY_SECONDS=0 \
    DOTFILES_MASON_TIMEOUT_MS=1 \
    DOTFILES_TEST_CHEZMOI_ARGV_LOG="$CHEZMOI_ARGV_LOG" \
    DOTFILES_TEST_CHEZMOI_MARKER="$CHEZMOI_MARKER" \
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
[[ -f "$CHEZMOI_MARKER" ]] || fail "post-create did not execute the fake chezmoi binary"
mapfile -t chezmoi_calls <"$CHEZMOI_ARGV_LOG"
[[ "${#chezmoi_calls[@]}" -eq 1 ]] || fail "fake chezmoi was called ${#chezmoi_calls[@]} times, expected once"
printf -v expected_chezmoi_call 'call %q %q %q' init --apply "--source=$REPO_ROOT"
[[ "${chezmoi_calls[0]}" == "$expected_chezmoi_call" ]] ||
    fail "unexpected fake chezmoi argv: ${chezmoi_calls[0]}"
printf 'Fake chezmoi argv: %s\n' "${chezmoi_calls[0]}"
if grep -Eqi 'brew[[:space:]]+bundle|cxx-init|Homebrew Bundle' "$LOG_FILE"; then
    fail "isolated provisioning test attempted a real package installation"
fi

observer="$(sed -n '/^assert_container_state()/,/^}/p' "$REPO_ROOT/tests/devcontainer/lifecycle_smoke.sh")"
if grep -Eqi 'nvim.*MasonTools(Install|Update)|chezmoi[[:space:]]+apply|brew[[:space:]]+(install|bundle)|go[[:space:]]+install' <<<"$observer"; then
    fail "Dev Container state validation contains a repair command"
fi

printf 'Dev Container provisioning ownership and exhaustion tests passed\n'
