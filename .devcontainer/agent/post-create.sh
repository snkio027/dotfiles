#!/usr/bin/env bash

set -euo pipefail

fail() {
    echo "$1" >&2
    exit 1
}

WORKSPACE_FOLDER="${1:?workspace folder is required}"
SHARED_POST_CREATE="$WORKSPACE_FOLDER/.devcontainer/post-create.sh"
SUDOERS_RULE="/etc/sudoers.d/vscode"

[[ "$(/usr/bin/id -un)" == "vscode" && "$(/usr/bin/id -u)" != "0" ]] ||
    fail "Restricted Agent provisioning must run as the non-root vscode user"
[[ -f "$SHARED_POST_CREATE" ]] || fail "Shared post-create entry point is unavailable"

revoke_passwordless_sudo() {
    local rule_metadata

    if [[ -e "$SUDOERS_RULE" || -L "$SUDOERS_RULE" ]]; then
        [[ -f "$SUDOERS_RULE" && ! -L "$SUDOERS_RULE" ]] ||
            fail "Unexpected vscode sudoers rule type"
        rule_metadata="$(/usr/bin/stat -c '%U:%G:%a' "$SUDOERS_RULE")"
        [[ "$rule_metadata" == "root:root:440" ]] ||
            fail "Unexpected vscode sudoers rule ownership or mode: $rule_metadata"
        /usr/bin/sudo -n /bin/rm -f -- "$SUDOERS_RULE"
    fi

    /usr/bin/sudo -k
    [[ ! -e "$SUDOERS_RULE" && ! -L "$SUDOERS_RULE" ]] ||
        fail "vscode sudoers rule still exists after lockdown"
    if /usr/bin/sudo -n true 2>/dev/null; then
        fail "Passwordless sudo is still available after Agent lane lockdown"
    fi
}

printf 'Restricted Agent post-create start\n'

# The shared provisioner remains the sole owner of chezmoi, Linuxbrew, Lazy,
# and Mason setup. Capture its status so privilege removal still happens when
# provisioning fails; a failed container must not retain the bootstrap grant.
set +e
/bin/bash "$SHARED_POST_CREATE" "$WORKSPACE_FOLDER"
provision_status=$?
set -e

revoke_passwordless_sudo

if ((provision_status != 0)); then
    echo "Restricted Agent shared provisioning failed with exit $provision_status" >&2
    exit "$provision_status"
fi

printf 'Restricted Agent lane lockdown complete\n'
