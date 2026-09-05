#!/usr/bin/env bash

set -euo pipefail

fail() {
    echo "$1" >&2
    exit 1
}

assert_container_state() {
    local workspace_folder="${1:?container workspace folder is required}"
    local pass_name="${2:-unknown}"
    local user_name passwd_shell source_path status_output nvim_log invalid_profile_output bootstrap_binary bootstrap_receipt
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
    if [[ -d "$HOME/.ssh" ]] && find "$HOME/.ssh" -type s -print -quit | grep -q .; then
        fail "An SSH agent socket was mounted under the container home"
    fi
    if [[ -d "$HOME/.ssh" ]] && find "$HOME/.ssh" -type f \( -name 'id_*' -o -name '*.pem' \) -print -quit | grep -q .; then
        fail "A host-style private key exists in the Dev Container"
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
        nvim -n --headless \
            --cmd "lua vim.g.dx_color_expected_profile = 'c3_1'; vim.g.dx_color_profile_case = 'default'" \
            "+luafile tests/nvim/profile_runtime.lua" +qa
        nvim -n --headless \
            --cmd "lua vim.g.dx_color_profile = 'c4'; vim.g.dx_color_expected_profile = 'c4'; vim.g.dx_color_profile_case = 'opt-in'" \
            "+luafile tests/nvim/profile_runtime.lua" +qa
        nvim -n --headless \
            --cmd "lua vim.g.dx_color_profile = 'c3_1'; vim.g.dx_color_expected_profile = 'c3_1'; vim.g.dx_color_profile_case = 'opt-out'" \
            "+luafile tests/nvim/profile_runtime.lua" +qa
        if invalid_profile_output="$(
            nvim -n --headless \
                --cmd "lua vim.g.dx_color_profile = false; vim.g.dx_color_profile_case = 'invalid-false'" \
                "+luafile tests/nvim/profile_runtime.lua" +qa 2>&1
        )"; then
            printf '%s\n' "$invalid_profile_output"
            fail "M3-C invalid false selector unexpectedly succeeded"
        fi
        printf '%s\n' "$invalid_profile_output"
        grep -Fq "expected one of: c3_1, c4" <<<"$invalid_profile_output" ||
            fail "M3-C invalid false selector did not report the accepted profiles"
        grep -Fq "M3-C invalid false selector rejected by production runtime." <<<"$invalid_profile_output" ||
            fail "M3-C invalid false selector rejection marker is missing"
        DOTFILES_STRICT_LSP=1 nvim -n --headless "+luafile tests/nvim/color_contract.lua" +qa
        nvim -n --headless "+luafile tests/nvim/binding_evidence.lua" +qa
        nvim -u NONE -i NONE --headless "+set rtp^=$PWD/home/dot_config/nvim" \
            "+luafile tests/nvim/run_contract.lua" "tests/nvim/python_provider_ownership_contract.lua"
        DOTFILES_M2C_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}" \
            bash tests/nvim/python_provider_ownership.sh
        bash tests/nvim/color/validate_fixtures.sh
    ) >"$nvim_log" 2>&1 || {
        cat "$nvim_log" >&2
        fail "Neovim warm smoke failed"
    }
    grep -Fq "Neovim toolchain smoke tests passed" "$nvim_log" || {
        cat "$nvim_log" >&2
        fail "Neovim warm smoke did not complete"
    }
    grep -Fq "M2A binding-topology evidence passed: 28/28 cases, 15/15 comparisons." "$nvim_log" || {
        cat "$nvim_log" >&2
        fail "M2A binding-topology evidence did not complete"
    }
    grep -Fq "M2B static-data-member evidence passed: 7/7 cases; decision: RECLASSIFY STATIC DATA MEMBER TO DxMember" "$nvim_log" || {
        cat "$nvim_log" >&2
        fail "M2B static-data-member classification evidence did not complete"
    }
    grep -Fq "M2B-B static-data-member behavior correction passed: 13/13 cases; decision: RECLASSIFY STATIC DATA MEMBER TO DxMember" "$nvim_log" || {
        cat "$nvim_log" >&2
        fail "M2B-B static-data-member behavior correction did not complete"
    }
    grep -Fq "M2C-B explicit Python provider ownership passed." "$nvim_log" || {
        cat "$nvim_log" >&2
        fail "M2C-B explicit provider-ownership evidence did not complete"
    }
    grep -Fq "M2C-B topology: installed pyright+ruff+ty; enabled/attached ruff+ty; semantic producer ty." "$nvim_log" || {
        cat "$nvim_log" >&2
        fail "M2C-B provider topology did not close"
    }
    grep -Fq "M2C-B decision implemented: ADOPT TY AS INTERACTIVE SEMANTIC PROVIDER" "$nvim_log" || {
        cat "$nvim_log" >&2
        fail "M2C-B provider-ownership decision was not implemented"
    }
    grep -Fq "M3-C runtime profile selection passed: default -> c3_1." "$nvim_log" || {
        cat "$nvim_log" >&2
        fail "M3-C default C3.1 runtime selection did not complete"
    }
    grep -Fq "M3-C runtime profile selection passed: opt-in -> c4." "$nvim_log" || {
        cat "$nvim_log" >&2
        fail "M3-C explicit C4 runtime selection did not complete"
    }
    grep -Fq "M3-C runtime C4 contrast contract passed against actual Normal.bg" "$nvim_log" || {
        cat "$nvim_log" >&2
        fail "M3-C C4 runtime contrast contract did not complete"
    }
    grep -Fq "M3-C runtime profile selection passed: opt-out -> c3_1." "$nvim_log" || {
        cat "$nvim_log" >&2
        fail "M3-C explicit C3.1 runtime opt-out did not complete"
    }
    grep -Fq "M3-C invalid false selector rejected by production runtime." "$nvim_log" || {
        cat "$nvim_log" >&2
        fail "M3-C invalid false selector runtime rejection did not complete"
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
    assert_container_state "${2:?container workspace folder is required}" "${3:-unknown}"
    exit 0
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEVCONTAINER_BIN="${DEVCONTAINER_BIN:-$(command -v devcontainer || true)}"
TEST_ROOT="$(mktemp -d)"
WORKSPACE="$TEST_ROOT/dotfiles-lifecycle"
FIRST_LOG="$TEST_ROOT/devcontainer-up-first.log"
SECOND_LOG="$TEST_ROOT/devcontainer-up-second.log"

cleanup() {
    local container_id
    while IFS= read -r container_id; do
        [[ -z "$container_id" ]] || docker rm --force "$container_id" >/dev/null
    done < <(docker ps --all --quiet --filter "label=devcontainer.local_folder=$WORKSPACE" 2>/dev/null || true)
    rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

[[ -n "$DEVCONTAINER_BIN" && -x "$DEVCONTAINER_BIN" ]] || fail "devcontainer CLI is unavailable"
command -v docker >/dev/null || fail "docker is unavailable"
command -v jq >/dev/null || fail "jq is unavailable"

if jq -e '[.. | strings | select(test("SSH_AUTH_SOCK|OP_SSH_AUTH_SOCK|1[Pp]assword|(^|/)\\.ssh(/|$)"))] | length > 0' \
    "$REPO_ROOT/.devcontainer/devcontainer.json" >/dev/null; then
    fail "devcontainer.json must not wire host credentials into the container"
fi

mkdir -p "$WORKSPACE"
(
    cd "$REPO_ROOT"
    tar --exclude='./.git' --exclude='./.cache' --exclude='./node_modules' -cf - .
) | tar -xf - -C "$WORKSPACE"

LOCK_SNAPSHOT="$TEST_ROOT/lazy-lock.snapshot.json"
cp "$WORKSPACE/home/dot_config/nvim/lazy-lock.json" "$LOCK_SNAPSHOT"

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

run_devcontainer up --workspace-folder "$WORKSPACE" 2>&1 | tee "$FIRST_LOG"
START_LINE="$(log_line "$FIRST_LOG" 'Dev Container post-create start')"
ATTEMPT_LINE="$(log_line "$FIRST_LOG" 'post-create Neovim provisioning attempt')"
TOOLS_LINE="$(log_line "$FIRST_LOG" 'required tools complete: 21/21')"
PROVISION_LINE="$(log_line "$FIRST_LOG" 'post-create Neovim provisioning complete')"
POST_CREATE_LINE="$(log_line "$FIRST_LOG" 'Dev Container post-create complete')"
OUTCOME_LINE="$(log_line "$FIRST_LOG" '"outcome":"success"')"
if ! ((START_LINE < ATTEMPT_LINE && ATTEMPT_LINE < TOOLS_LINE && TOOLS_LINE < PROVISION_LINE && PROVISION_LINE < POST_CREATE_LINE && POST_CREATE_LINE < OUTCOME_LINE)); then
    fail "Dev Container provisioning ownership markers are out of order"
fi
if grep -Fq 'Mason receipt observation' "$FIRST_LOG"; then
    fail "Observation ran before devcontainer up completed"
fi
FIRST_RESULT="$(extract_result "$FIRST_LOG")"
FIRST_CONTAINER_ID="$(printf '%s' "$FIRST_RESULT" | jq -er '.containerId')"
[[ "$(printf '%s' "$FIRST_RESULT" | jq -r '.remoteUser')" == "vscode" ]] || fail "CLI did not select remoteUser vscode"
[[ "$(printf '%s' "$FIRST_RESULT" | jq -r '.remoteWorkspaceFolder')" == "/workspaces/dotfiles-lifecycle" ]] || fail "CLI selected the wrong workspace"

INSPECT="$(docker inspect "$FIRST_CONTAINER_ID")"
[[ "$(printf '%s' "$INSPECT" | jq -r '.[0].Config.User')" == "vscode" ]] || fail "Docker did not start as vscode"
if printf '%s' "$INSPECT" | jq -e '.[0].Config.Env | any(test("^(SSH_AUTH_SOCK|OP_SSH_AUTH_SOCK|GH_TOKEN|GITHUB_TOKEN)="))' >/dev/null; then
    fail "A host credential environment variable was persisted in the container"
fi
if printf '%s' "$INSPECT" | jq -e '.[0].Mounts | any((.Source + " " + .Destination) | test("(1[Pp]assword|/\\.ssh(/|$)|ssh-auth)"))' >/dev/null; then
    fail "A host credential path was mounted in the container"
fi

run_devcontainer exec --workspace-folder "$WORKSPACE" \
    bash "/workspaces/dotfiles-lifecycle/tests/devcontainer/lifecycle_smoke.sh" \
    --inside "/workspaces/dotfiles-lifecycle" first

run_devcontainer up --workspace-folder "$WORKSPACE" 2>&1 | tee "$SECOND_LOG"
SECOND_RESULT="$(extract_result "$SECOND_LOG")"
SECOND_CONTAINER_ID="$(printf '%s' "$SECOND_RESULT" | jq -er '.containerId')"
[[ "$SECOND_CONTAINER_ID" == "$FIRST_CONTAINER_ID" ]] || fail "Second up replaced the existing container"

run_devcontainer exec --workspace-folder "$WORKSPACE" \
    bash "/workspaces/dotfiles-lifecycle/tests/devcontainer/lifecycle_smoke.sh" \
    --inside "/workspaces/dotfiles-lifecycle" second

cmp "$WORKSPACE/home/dot_config/nvim/lazy-lock.json" "$LOCK_SNAPSHOT"
printf 'Dev Container lifecycle and idempotence tests passed\n'
