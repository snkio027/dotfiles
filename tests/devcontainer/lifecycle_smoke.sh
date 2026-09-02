#!/usr/bin/env bash

set -euo pipefail

fail() {
    echo "$1" >&2
    exit 1
}

assert_container_state() {
    local workspace_folder="${1:?container workspace folder is required}"
    local pass_name="${2:-unknown}"
    local lane="${3:-human}"
    local user_name passwd_shell source_path status_output nvim_log bootstrap_binary bootstrap_receipt
    local mason_manifest mason_data_root mason_tool unique_count
    local -a mason_tools

    user_name="$(id -un)"
    [[ "$user_name" == "vscode" ]] || fail "Dev Container user is $user_name, expected vscode"
    [[ "$(id -u)" != "0" ]] || fail "Dev Container lifecycle is running as root"

    passwd_shell="$(getent passwd "$user_name" | cut -d: -f7)"
    [[ "$passwd_shell" == "/bin/zsh" ]] || fail "passwd login shell is $passwd_shell, expected /bin/zsh"
    [[ "${SHELL:-}" == "/bin/zsh" ]] || fail "SHELL is ${SHELL:-unset}, expected /bin/zsh"
    [[ "${CHEZMOI_PROFILE:-}" == "devcontainer" ]] || fail "CHEZMOI_PROFILE is not devcontainer"

    [[ "$(command -v brew)" == "/home/linuxbrew/.linuxbrew/bin/brew" ]] || fail "brew is not from Linuxbrew"
    [[ "${HOMEBREW_PREFIX:-}" == "/home/linuxbrew/.linuxbrew" ]] || fail "HOMEBREW_PREFIX is not Linuxbrew"
    bootstrap_binary="$HOME/.local/bin/chezmoi"
    bootstrap_receipt="$HOME/.local/bin/.chezmoi-provenance"
    [[ -x "$bootstrap_binary" && -f "$bootstrap_receipt" ]] || fail "verified chezmoi bootstrap artifacts are missing"
    grep -Fqx 'version=2.72.1' "$bootstrap_receipt" || fail "chezmoi bootstrap version receipt drifted"
    grep -Eq '^platform=linux/(amd64|arm64)$' "$bootstrap_receipt" || fail "chezmoi bootstrap platform receipt is invalid"
    [[ "$("$bootstrap_binary" --version)" == "chezmoi version v2.72.1,"* ]] || fail "chezmoi bootstrap binary version drifted"

    source_path="$(chezmoi source-path)"
    [[ "$source_path" == "$workspace_folder/home" ]] || fail "chezmoi source is $source_path"
    [[ "$(chezmoi data --format=json | jq -r '.machine_profile')" == "devcontainer" ]] || fail "chezmoi profile data is wrong"

    status_output="$(chezmoi status)"
    chezmoi verify
    status_output="$(chezmoi status)"
    [[ -z "$status_output" ]] || fail "chezmoi status is not clean: $status_output"

    [[ -z "${SSH_AUTH_SOCK:-}" ]] || fail "SSH_AUTH_SOCK leaked into the Dev Container"
    [[ -z "${OP_SSH_AUTH_SOCK:-}" ]] || fail "OP_SSH_AUTH_SOCK leaked into the Dev Container"
    [[ -z "${GH_TOKEN:-}" ]] || fail "GH_TOKEN leaked into the Dev Container"
    [[ -z "${GITHUB_TOKEN:-}" ]] || fail "GITHUB_TOKEN leaked into the Dev Container"
    [[ ! -S /var/run/docker.sock ]] || fail "Docker socket is available in the Dev Container"
    if [[ -d "$HOME/.ssh" ]] && find "$HOME/.ssh" -type s -print -quit | grep -q .; then
        fail "An SSH agent socket was mounted under the container home"
    fi
    if [[ -d "$HOME/.ssh" ]] && find "$HOME/.ssh" -type f \( -name 'id_*' -o -name '*.pem' \) -print -quit | grep -q .; then
        fail "A host-style private key exists in the Dev Container"
    fi

    if [[ "$lane" == "agent" ]]; then
        [[ ! -e /etc/sudoers.d/vscode && ! -L /etc/sudoers.d/vscode ]] ||
            fail "Agent lane retained the vscode sudoers grant"
        if /usr/bin/sudo -n true 2>/dev/null; then
            fail "Agent lane retained passwordless sudo"
        fi
    fi

    env -u HOMEBREW_PREFIX -u HOMEBREW_CELLAR -u HOMEBREW_REPOSITORY \
        PATH="/usr/bin:/bin" TERM="xterm-256color" \
        /bin/zsh -d -ic '
            [[ "$HOMEBREW_PREFIX" == "/home/linuxbrew/.linuxbrew" ]] || exit 41
            [[ "$commands[brew]" == "/home/linuxbrew/.linuxbrew/bin/brew" ]] || exit 42
            (( ${+functions[_brew]} )) || exit 43
            (( ${+functions[_zsh_autosuggest_start]} )) || exit 44
            (( ${+functions[_zsh_highlight]} )) || exit 45
            [[ "${(j/:/)path}" != *"/opt/homebrew"* ]] || exit 46
            [[ "${(j/:/)fpath}" != *"/opt/homebrew"* ]] || exit 47
        '

    cmp "$HOME/.config/nvim/lazy-lock.json" "$workspace_folder/home/dot_config/nvim/lazy-lock.json"

    mason_manifest="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/mason-tools.txt"
    mason_data_root="${XDG_DATA_HOME:-$HOME/.local/share}/nvim/mason/packages"
    [[ -s "$mason_manifest" ]] || fail "Mason provisioning manifest is missing"
    mapfile -t mason_tools <"$mason_manifest"
    [[ "${#mason_tools[@]}" -eq 21 ]] || fail "Mason provisioning manifest is not 21/21"
    unique_count="$(sort -u "$mason_manifest" | wc -l | tr -d ' ')"
    [[ "$unique_count" -eq "${#mason_tools[@]}" ]] || fail "Mason provisioning manifest contains duplicates"
    for mason_tool in "${mason_tools[@]}"; do
        [[ "$mason_tool" =~ ^[a-z0-9][a-z0-9._-]*$ ]] || fail "Invalid Mason tool in manifest: $mason_tool"
        [[ -f "$mason_data_root/$mason_tool/mason-receipt.json" ]] || fail "Mason receipt is missing: $mason_tool"
    done
    printf 'Mason receipt observation %d/%d (%s)\n' "${#mason_tools[@]}" "${#mason_tools[@]}" "$pass_name"

    nvim_log="$(mktemp)"
    (
        cd "$workspace_folder"
        nvim --headless "+luafile tests/nvim/startup_policy.lua" \
            "+luafile tests/nvim/smoke.lua" +qa
    ) >"$nvim_log" 2>&1 || {
        cat "$nvim_log" >&2
        fail "Neovim warm smoke failed"
    }
    grep -Fq "Neovim toolchain smoke tests passed" "$nvim_log" || {
        cat "$nvim_log" >&2
        fail "Neovim warm smoke did not complete"
    }
    if grep -Eqi 'Package is already installing|^Installing tools:|^Updating tools:|MasonToolsUpdate' "$nvim_log"; then
        cat "$nvim_log" >&2
        fail "Neovim observation attempted a Mason install or update"
    fi

    status_output="$(chezmoi status)"
    [[ -z "$status_output" ]] || fail "Neovim changed chezmoi-managed state: $status_output"

    rm -f -- "$nvim_log"
    printf 'Dev Container state verification passed (%s)\n' "$pass_name"
}

if [[ "${1:-}" == "--inside" ]]; then
    assert_container_state "${2:?container workspace folder is required}" "${3:-unknown}" "${4:-human}"
    exit 0
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEVCONTAINER_BIN="${DEVCONTAINER_BIN:-$(command -v devcontainer || true)}"
TEST_ROOT="$(mktemp -d)"
HUMAN_WORKSPACE="$TEST_ROOT/dotfiles-human-lifecycle"
AGENT_WORKSPACE="$TEST_ROOT/dotfiles-agent-lifecycle"
HUMAN_CONFIG="$HUMAN_WORKSPACE/.devcontainer/devcontainer.json"
AGENT_CONFIG="$AGENT_WORKSPACE/.devcontainer/agent/devcontainer.json"
HUMAN_LOG="$TEST_ROOT/devcontainer-human.log"
AGENT_FAILURE_LOG="$TEST_ROOT/devcontainer-agent-failure.log"
AGENT_FIRST_LOG="$TEST_ROOT/devcontainer-agent-first.log"
AGENT_SECOND_LOG="$TEST_ROOT/devcontainer-agent-second.log"

cleanup() {
    local container_id workspace
    for workspace in "$HUMAN_WORKSPACE" "$AGENT_WORKSPACE"; do
        while IFS= read -r container_id; do
            [[ -z "$container_id" ]] || docker rm --force "$container_id" >/dev/null
        done < <(docker ps --all --quiet --filter "label=devcontainer.local_folder=$workspace" 2>/dev/null || true)
    done
    rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

[[ -n "$DEVCONTAINER_BIN" && -x "$DEVCONTAINER_BIN" ]] || fail "devcontainer CLI is unavailable"
command -v docker >/dev/null || fail "docker is unavailable"
command -v jq >/dev/null || fail "jq is unavailable"
command -v python3 >/dev/null || fail "python3 is unavailable"

python3 "$REPO_ROOT/tests/devcontainer/lane_contract_test.py"

copy_workspace() {
    local destination="${1:?destination is required}"
    mkdir -p "$destination"
    (
        cd "$REPO_ROOT"
        tar --exclude='./.git' --exclude='./.cache' --exclude='./node_modules' -cf - .
    ) | tar -xf - -C "$destination"
}

LOCK_SNAPSHOT="$TEST_ROOT/lazy-lock.snapshot.json"
copy_workspace "$HUMAN_WORKSPACE"
copy_workspace "$AGENT_WORKSPACE"
cp "$AGENT_WORKSPACE/home/dot_config/nvim/lazy-lock.json" "$LOCK_SNAPSHOT"

run_devcontainer() {
    env -u SSH_AUTH_SOCK -u OP_SSH_AUTH_SOCK -u GH_TOKEN -u GITHUB_TOKEN \
        "$DEVCONTAINER_BIN" "$@"
}

extract_result() {
    jq -Rsc '
        [split("\n")[] | try fromjson catch empty |
            select(.outcome? == "success" and .containerId?)] | last
    ' "$1"
}

log_line() {
    local log_file="${1:?log file is required}"
    local marker="${2:?log marker is required}"
    grep -nF "$marker" "$log_file" | tail -n 1 | cut -d: -f1
}

assert_no_host_credentials() {
    local inspect_json="${1:?inspect JSON is required}"
    local lane="${2:?lane name is required}"

    if printf '%s' "$inspect_json" | jq -e '.[0].Config.Env | any(test("^(SSH_AUTH_SOCK|OP_SSH_AUTH_SOCK|GH_TOKEN|GITHUB_TOKEN)="))' >/dev/null; then
        fail "$lane lane persisted a host credential environment variable"
    fi
    if printf '%s' "$inspect_json" | jq -e \
        '.[0].Mounts | any((.Source + " " + .Destination) | test("(1[Pp]assword|/\\.ssh(/|$)|ssh-auth|docker\\.sock)"))' >/dev/null; then
        fail "$lane lane mounted a host credential path or Docker socket"
    fi
}

# The default Human lane remains the explicit debugging environment. Starting
# it without post-create keeps this contract fast; the Agent lane below runs
# the same image, profile, and shared provisioner to completion exactly once.
run_devcontainer up --workspace-folder "$HUMAN_WORKSPACE" --config "$HUMAN_CONFIG" \
    --skip-post-create 2>&1 | tee "$HUMAN_LOG"
HUMAN_RESULT="$(extract_result "$HUMAN_LOG")"
HUMAN_CONTAINER_ID="$(printf '%s' "$HUMAN_RESULT" | jq -er '.containerId')"
[[ "$(printf '%s' "$HUMAN_RESULT" | jq -r '.remoteUser')" == "vscode" ]] ||
    fail "Human lane did not select remoteUser vscode"
HUMAN_INSPECT="$(docker inspect "$HUMAN_CONTAINER_ID")"
[[ "$(printf '%s' "$HUMAN_INSPECT" | jq -r '.[0].Config.User')" == "vscode" ]] ||
    fail "Human lane did not start as vscode"
printf '%s' "$HUMAN_INSPECT" | jq -e \
    '(.[0].HostConfig.CapAdd // []) | any(. == "SYS_PTRACE" or . == "CAP_SYS_PTRACE")' >/dev/null ||
    fail "Human lane lost SYS_PTRACE debugging capability"
printf '%s' "$HUMAN_INSPECT" | jq -e \
    '(.[0].HostConfig.SecurityOpt // []) | any(. == "seccomp=unconfined")' >/dev/null ||
    fail "Human lane lost its unconfined debugging seccomp policy"
assert_no_host_credentials "$HUMAN_INSPECT" "Human"

# A failed shared provisioner must still consume the temporary sudo grant and
# must not publish the Agent readiness marker. Reuse the disposable Human
# container so this negative path adds seconds, not a second full lifecycle.
set +e
docker exec --user vscode --env DOTFILES_CHEZMOI_BIN=/bin/false \
    "$HUMAN_CONTAINER_ID" /bin/bash \
    "/workspaces/dotfiles-human-lifecycle/.devcontainer/agent/post-create.sh" \
    "/workspaces/dotfiles-human-lifecycle" >"$AGENT_FAILURE_LOG" 2>&1
AGENT_FAILURE_STATUS=$?
set -e
[[ "$AGENT_FAILURE_STATUS" -eq 1 ]] ||
    fail "Agent wrapper did not preserve the shared provisioning failure status"
grep -Fq 'Dev Container chezmoi provisioning failed after 3 attempts' "$AGENT_FAILURE_LOG"
grep -Fq 'Restricted Agent shared provisioning failed with exit 1' "$AGENT_FAILURE_LOG"
if grep -Fq 'Restricted Agent lane lockdown complete' "$AGENT_FAILURE_LOG"; then
    fail "Failed Agent provisioning published a readiness marker"
fi
docker exec --user vscode "$HUMAN_CONTAINER_ID" /bin/bash -lc \
    'test ! -e /etc/sudoers.d/vscode && ! /usr/bin/sudo -n true 2>/dev/null' ||
    fail "Failed Agent provisioning retained passwordless sudo"
docker rm --force "$HUMAN_CONTAINER_ID" >/dev/null
printf 'Human debugging and Agent failure contracts passed\n'

# The Agent lane is the only full lifecycle in this job. waitFor must keep the
# CLI outcome behind shared provisioning and the final privilege lockdown.
run_devcontainer up --workspace-folder "$AGENT_WORKSPACE" --config "$AGENT_CONFIG" \
    2>&1 | tee "$AGENT_FIRST_LOG"
AGENT_START_LINE="$(log_line "$AGENT_FIRST_LOG" 'Restricted Agent post-create start')"
START_LINE="$(log_line "$AGENT_FIRST_LOG" 'Dev Container post-create start')"
ATTEMPT_LINE="$(log_line "$AGENT_FIRST_LOG" 'post-create Neovim provisioning attempt')"
TOOLS_LINE="$(log_line "$AGENT_FIRST_LOG" 'required tools complete: 21/21')"
PROVISION_LINE="$(log_line "$AGENT_FIRST_LOG" 'post-create Neovim provisioning complete')"
POST_CREATE_LINE="$(log_line "$AGENT_FIRST_LOG" 'Dev Container post-create complete')"
LOCKDOWN_LINE="$(log_line "$AGENT_FIRST_LOG" 'Restricted Agent lane lockdown complete')"
OUTCOME_LINE="$(log_line "$AGENT_FIRST_LOG" '"outcome":"success"')"
if ! ((AGENT_START_LINE < START_LINE && START_LINE < ATTEMPT_LINE && ATTEMPT_LINE < TOOLS_LINE && TOOLS_LINE < PROVISION_LINE && PROVISION_LINE < POST_CREATE_LINE && POST_CREATE_LINE < LOCKDOWN_LINE && LOCKDOWN_LINE < OUTCOME_LINE)); then
    fail "Restricted Agent provisioning and lockdown markers are out of order"
fi
if grep -Fq 'Mason receipt observation' "$AGENT_FIRST_LOG"; then
    fail "Observation ran before restricted Agent up completed"
fi
AGENT_FIRST_RESULT="$(extract_result "$AGENT_FIRST_LOG")"
AGENT_FIRST_CONTAINER_ID="$(printf '%s' "$AGENT_FIRST_RESULT" | jq -er '.containerId')"
[[ "$(printf '%s' "$AGENT_FIRST_RESULT" | jq -r '.remoteUser')" == "vscode" ]] ||
    fail "Agent lane did not select remoteUser vscode"
[[ "$(printf '%s' "$AGENT_FIRST_RESULT" | jq -r '.remoteWorkspaceFolder')" == "/workspaces/dotfiles-agent-lifecycle" ]] ||
    fail "Agent lane selected the wrong workspace"

AGENT_INSPECT="$(docker inspect "$AGENT_FIRST_CONTAINER_ID")"
[[ "$(printf '%s' "$AGENT_INSPECT" | jq -r '.[0].Config.User')" == "vscode" ]] ||
    fail "Agent lane did not start as vscode"
[[ "$(printf '%s' "$AGENT_INSPECT" | jq -r '.[0].HostConfig.Privileged')" == "false" ]] ||
    fail "Agent lane started privileged"
if printf '%s' "$AGENT_INSPECT" | jq -e \
    '(.[0].HostConfig.CapAdd // []) | any(. == "SYS_PTRACE" or . == "CAP_SYS_PTRACE")' >/dev/null; then
    fail "Agent lane added SYS_PTRACE"
fi
printf '%s' "$AGENT_INSPECT" | jq -e \
    '(.[0].HostConfig.CapDrop // []) | any(. == "SYS_PTRACE" or . == "CAP_SYS_PTRACE")' >/dev/null ||
    fail "Agent lane did not explicitly drop SYS_PTRACE"
printf '%s' "$AGENT_INSPECT" | jq -e \
    '(.[0].HostConfig.SecurityOpt // []) | any(. == "seccomp=builtin")' >/dev/null ||
    fail "Agent lane did not enable Docker builtin seccomp"
if printf '%s' "$AGENT_INSPECT" | jq -e \
    '(.[0].HostConfig.SecurityOpt // []) | any(. == "seccomp=unconfined")' >/dev/null; then
    fail "Agent lane disabled seccomp confinement"
fi
[[ "$(printf '%s' "$AGENT_INSPECT" | jq -r '.[0].HostConfig.PidMode')" != "host" ]] ||
    fail "Agent lane joined the host PID namespace"
[[ "$(printf '%s' "$AGENT_INSPECT" | jq -r '.[0].HostConfig.IpcMode')" != "host" ]] ||
    fail "Agent lane joined the host IPC namespace"
assert_no_host_credentials "$AGENT_INSPECT" "Agent"

run_devcontainer exec --workspace-folder "$AGENT_WORKSPACE" --config "$AGENT_CONFIG" \
    bash "/workspaces/dotfiles-agent-lifecycle/tests/devcontainer/lifecycle_smoke.sh" \
    --inside "/workspaces/dotfiles-agent-lifecycle" first agent

run_devcontainer up --workspace-folder "$AGENT_WORKSPACE" --config "$AGENT_CONFIG" \
    2>&1 | tee "$AGENT_SECOND_LOG"
AGENT_SECOND_RESULT="$(extract_result "$AGENT_SECOND_LOG")"
AGENT_SECOND_CONTAINER_ID="$(printf '%s' "$AGENT_SECOND_RESULT" | jq -er '.containerId')"
[[ "$AGENT_SECOND_CONTAINER_ID" == "$AGENT_FIRST_CONTAINER_ID" ]] ||
    fail "Second Agent up replaced the existing container"

run_devcontainer exec --workspace-folder "$AGENT_WORKSPACE" --config "$AGENT_CONFIG" \
    bash "/workspaces/dotfiles-agent-lifecycle/tests/devcontainer/lifecycle_smoke.sh" \
    --inside "/workspaces/dotfiles-agent-lifecycle" second agent

cmp "$AGENT_WORKSPACE/home/dot_config/nvim/lazy-lock.json" "$LOCK_SNAPSHOT"
printf 'Restricted Agent lifecycle and idempotence tests passed\n'
