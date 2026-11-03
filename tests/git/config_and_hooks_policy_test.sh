#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_ROOT="$(mktemp -d)"
TEST_ROOT="$(cd "$TEST_ROOT" && pwd -P)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

# Exercise only the read-only helpers. Never render/run a chezmoi entry script,
# install a hook, run a scanner, or read the user's global/repository config.
unset GIT_DIR GIT_COMMON_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY
unset GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_CONFIG GIT_CONFIG_COUNT
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_SYSTEM=/dev/null
export GIT_CONFIG_GLOBAL="$TEST_ROOT/global-config"
: >"$GIT_CONFIG_GLOBAL"
# shellcheck source=home/.chezmoitemplates/git_config_migration.sh
source "$REPO_ROOT/home/.chezmoitemplates/git_config_migration.sh"
# shellcheck source=home/.chezmoitemplates/git_hook_policy.sh
source "$REPO_ROOT/home/.chezmoitemplates/git_hook_policy.sh"

assert_status() {
    local expected="$1" actual=0
    shift
    "$@" >"$TEST_ROOT/result" 2>"$TEST_ROOT/error" || actual=$?
    if [ "$actual" -ne "$expected" ]; then
        printf 'Expected exit %s, got %s: %s\n' "$expected" "$actual" "$*" >&2
        cat "$TEST_ROOT/error" >&2
        exit 1
    fi
}

mkdir -p "$TEST_ROOT/legacy" "$TEST_ROOT/xdg"
LEGACY_CONFIG="$TEST_ROOT/legacy/config"
XDG_CONFIG="$TEST_ROOT/xdg/config"
cat >"$LEGACY_CONFIG" <<'EOF'
[user]
    name = Fixture User
    email = fixture@example.invalid
[credential]
    helper = first
    helper = second
EOF
cat >"$XDG_CONFIG" <<'EOF'
# Formatting and comments do not affect the comparison.
[user]
name="Fixture User"
email=fixture@example.invalid
[credential]
helper=first
helper=second
EOF
assert_status 0 git_configs_match_for_migration "$LEGACY_CONFIG" "$XDG_CONFIG"

# Sorting these identical sets of records would lose both last-value wins and
# multivar order. Identical duplicate order above is allowed; reversed is not.
cat >"$XDG_CONFIG" <<'EOF'
[user]
name=Fixture User
email=fixture@example.invalid
[credential]
helper=second
helper=first
EOF
assert_status 1 git_configs_match_for_migration "$LEGACY_CONFIG" "$XDG_CONFIG"
printf '[core]\neditor = first\neditor = second\n' >"$LEGACY_CONFIG"
printf '[core]\neditor = second\neditor = first\n' >"$XDG_CONFIG"
assert_status 1 git_configs_match_for_migration "$LEGACY_CONFIG" "$XDG_CONFIG"

# Includes must be retained even when their literal paths match: a relative
# include resolves from each config's own directory, and conditions vary by repo.
for include in 'include' 'includeIf "gitdir:./work/"' 'includeIf "onbranch:main"'; do
    for include_path in child.conf "$TEST_ROOT/shared.conf"; do
        printf '[%s]\npath = "%s"\n' "$include" "$include_path" >"$LEGACY_CONFIG"
        cp "$LEGACY_CONFIG" "$XDG_CONFIG"
        assert_status 1 git_configs_match_for_migration "$LEGACY_CONFIG" "$XDG_CONFIG"
    done
done

# A newline in a value can masquerade as another record in line-based output.
printf '[example]\nvalue = "alpha\\nexample.other=omega"\n' >"$LEGACY_CONFIG"
printf '[example]\nvalue = alpha\nother = omega\n' >"$XDG_CONFIG"
assert_status 1 git_configs_match_for_migration "$LEGACY_CONFIG" "$XDG_CONFIG"
cp "$LEGACY_CONFIG" "$XDG_CONFIG"
assert_status 1 git_configs_match_for_migration "$LEGACY_CONFIG" "$XDG_CONFIG"
printf '[example]\nvalue = "alpha\\n"\n' >"$LEGACY_CONFIG"
printf '[example]\nvalue = alpha\n' >"$XDG_CONFIG"
assert_status 1 git_configs_match_for_migration "$LEGACY_CONFIG" "$XDG_CONFIG"

# Invalid/missing input cannot compare equal through two failed empty snapshots.
printf '[invalid\n' >"$LEGACY_CONFIG"
cp "$LEGACY_CONFIG" "$XDG_CONFIG"
assert_status 1 git_configs_match_for_migration "$LEGACY_CONFIG" "$XDG_CONFIG"
assert_status 1 git_configs_match_for_migration "$TEST_ROOT/missing" "$TEST_ROOT/missing"
: >"$LEGACY_CONFIG"
: >"$XDG_CONFIG"
assert_status 0 git_configs_match_for_migration "$LEGACY_CONFIG" "$XDG_CONFIG"
printf '[feature]\nenabled\n' >"$LEGACY_CONFIG"
printf '[feature]\nenabled =\n' >"$XDG_CONFIG"
assert_status 1 git_configs_match_for_migration "$LEGACY_CONFIG" "$XDG_CONFIG"

# Isolated normal/linked repos with no templates, user hooks or signed commits.
NORMAL_REPO="$TEST_ROOT/normal repo"
LINKED_REPO="$TEST_ROOT/linked worktree"
mkdir "$TEST_ROOT/empty-template"
git init --quiet --initial-branch=main --template="$TEST_ROOT/empty-template" "$NORMAL_REPO"
git -C "$NORMAL_REPO" -c core.hooksPath=/dev/null -c commit.gpgsign=false \
    -c user.name=Fixture -c user.email=fixture@example.invalid \
    commit --quiet --allow-empty -m fixture
git -C "$NORMAL_REPO" worktree add --quiet --detach "$LINKED_REPO"
HOOK_FILE="$NORMAL_REPO/.git/hooks/pre-commit"
assert_status 0 git_default_pre_commit_path "$NORMAL_REPO"
[ "$(cat "$TEST_ROOT/result")" = "$HOOK_FILE" ]
[ -f "$LINKED_REPO/.git" ]
assert_status 0 git_default_pre_commit_path "$LINKED_REPO"
[ "$(cat "$TEST_ROOT/result")" = "$HOOK_FILE" ]
# Resolution itself must not create either hooks directory.
[ ! -e "$NORMAL_REPO/.git/hooks" ]
[ ! -e "$LINKED_REPO/.git/hooks" ]

mkdir -p "$NORMAL_REPO/subdirectory" "$TEST_ROOT/not-a-repo/.git"
assert_status 1 git_default_pre_commit_path "$NORMAL_REPO/subdirectory"
assert_status 1 git_default_pre_commit_path "$TEST_ROOT/not-a-repo"

# Custom relative, absolute and disabled paths remain under their owner's
# control. Exercise repository, global and worktree-specific config scopes.
CUSTOM_HOOKS="$TEST_ROOT/custom hooks"
mkdir "$CUSTOM_HOOKS"
printf 'custom hook must remain unchanged\n' >"$CUSTOM_HOOKS/pre-commit"
cp "$CUSTOM_HOOKS/pre-commit" "$TEST_ROOT/custom-original"
for hooks_path in .custom-hooks "$CUSTOM_HOOKS" /dev/null ''; do
    git -C "$NORMAL_REPO" config core.hooksPath "$hooks_path"
    assert_status 2 git_default_pre_commit_path "$NORMAL_REPO"
    [ ! -s "$TEST_ROOT/result" ]
    assert_status 2 git_default_pre_commit_path "$LINKED_REPO"
    [ ! -s "$TEST_ROOT/result" ]
done
git -C "$NORMAL_REPO" config --unset core.hooksPath
git config --global core.hooksPath "$CUSTOM_HOOKS"
assert_status 2 git_default_pre_commit_path "$LINKED_REPO"
git config --global --unset core.hooksPath
git -C "$NORMAL_REPO" config extensions.worktreeConfig true
git -C "$LINKED_REPO" config --worktree core.hooksPath .worktree-hooks
assert_status 2 git_default_pre_commit_path "$LINKED_REPO"
assert_status 0 git_default_pre_commit_path "$NORMAL_REPO"
cmp "$CUSTOM_HOOKS/pre-commit" "$TEST_ROOT/custom-original"
[ ! -e "$NORMAL_REPO/.custom-hooks" ]
[ ! -e "$LINKED_REPO/.worktree-hooks" ]
git -C "$LINKED_REPO" config --worktree --unset core.hooksPath

# Resolve after each filesystem fixture exists, as the entry script does.
# Checking ownership of a hand-built path alone misses final-symlink traversal.
assert_shared_pre_commit_status() {
    local expected="$1" worktree resolved
    for worktree in "$NORMAL_REPO" "$LINKED_REPO"; do
        assert_status 0 git_default_pre_commit_path "$worktree"
        resolved="$(cat "$TEST_ROOT/result")"
        if [ "$resolved" != "$HOOK_FILE" ]; then
            printf 'Hook resolver followed the final component: %s -> %s\n' "$HOOK_FILE" "$resolved" >&2
            exit 1
        fi
        assert_status "$expected" git_pre_commit_replace_status "$resolved"
    done
}

assert_shared_pre_commit_status 0
mkdir -p "${HOOK_FILE%/*}"
printf '#!/bin/sh\nprintf unmanaged\\n\n' >"$HOOK_FILE"
cp "$HOOK_FILE" "$TEST_ROOT/unmanaged-original"
assert_shared_pre_commit_status 1
cmp "$HOOK_FILE" "$TEST_ROOT/unmanaged-original"
printf '#!/bin/sh\n# Managed by chezmoi extra\n' >"$HOOK_FILE"
assert_shared_pre_commit_status 1
printf '#!/bin/sh\n# Managed by chezmoi\n' >"$HOOK_FILE"
assert_shared_pre_commit_status 0
rm "$HOOK_FILE"
ln -s "$CUSTOM_HOOKS/pre-commit" "$HOOK_FILE"
assert_shared_pre_commit_status 2
[ -L "$HOOK_FILE" ]
[ "$(readlink "$HOOK_FILE")" = "$CUSTOM_HOOKS/pre-commit" ]
cmp "$CUSTOM_HOOKS/pre-commit" "$TEST_ROOT/custom-original"
rm "$HOOK_FILE"

# A managed marker in an external target must never grant ownership through a
# symlink, even though that marker would permit replacing a direct regular file.
MANAGED_EXTERNAL_HOOK="$TEST_ROOT/managed-external-pre-commit"
printf '#!/bin/sh\n# Managed by chezmoi\nprintf external\\n\n' >"$MANAGED_EXTERNAL_HOOK"
cp "$MANAGED_EXTERNAL_HOOK" "$TEST_ROOT/managed-external-original"
ln -s "$MANAGED_EXTERNAL_HOOK" "$HOOK_FILE"
assert_shared_pre_commit_status 2
[ -L "$HOOK_FILE" ]
[ "$(readlink "$HOOK_FILE")" = "$MANAGED_EXTERNAL_HOOK" ]
cmp "$MANAGED_EXTERNAL_HOOK" "$TEST_ROOT/managed-external-original"
rm "$HOOK_FILE"
ln -s "$TEST_ROOT/missing-hook" "$HOOK_FILE"
assert_shared_pre_commit_status 2
[ -L "$HOOK_FILE" ]
[ "$(readlink "$HOOK_FILE")" = "$TEST_ROOT/missing-hook" ]
[ ! -e "$TEST_ROOT/missing-hook" ]
rm "$HOOK_FILE"
mkfifo "$HOOK_FILE"
assert_shared_pre_commit_status 2
[ -p "$HOOK_FILE" ]

# Directory resolution must preserve path bytes before appending the filename,
# even when hooks points to a directory whose name ends with a newline.
rm "$HOOK_FILE"
rmdir "$NORMAL_REPO/.git/hooks"
NEWLINE_HOOK_DIR="$TEST_ROOT/hooks"$'\n'
mkdir "$NEWLINE_HOOK_DIR"
ln -s "$NEWLINE_HOOK_DIR" "$NORMAL_REPO/.git/hooks"
HOOK_FILE="$NEWLINE_HOOK_DIR/pre-commit"
assert_shared_pre_commit_status 0
ln -s "$MANAGED_EXTERNAL_HOOK" "$HOOK_FILE"
assert_shared_pre_commit_status 2
cmp "$MANAGED_EXTERNAL_HOOK" "$TEST_ROOT/managed-external-original"

# Keep the tested policies wired into the entry scripts without executing them.
grep -Fq '{{ includeTemplate "git_config_migration.sh" . }}' \
    "$REPO_ROOT/home/.chezmoiscripts/run_once_after_40_migrate_xdg.sh.tmpl"
grep -Fq 'if git_configs_match_for_migration "$LEGACY_GIT_CONFIG" "$XDG_GIT_CONFIG"; then' \
    "$REPO_ROOT/home/.chezmoiscripts/run_once_after_40_migrate_xdg.sh.tmpl"
grep -Fq '{{ includeTemplate "git_hook_policy.sh" . }}' \
    "$REPO_ROOT/home/.chezmoiscripts/run_onchange_after_50_install_git_hooks.sh.tmpl"
grep -Fq 'if HOOK_FILE="$(git_default_pre_commit_path "$WORKING_TREE")"; then' \
    "$REPO_ROOT/home/.chezmoiscripts/run_onchange_after_50_install_git_hooks.sh.tmpl"
grep -Fq 'if git_pre_commit_replace_status "$HOOK_FILE"; then' \
    "$REPO_ROOT/home/.chezmoiscripts/run_onchange_after_50_install_git_hooks.sh.tmpl"

printf 'Git migration and hook policy fixtures passed; no entry scripts executed\n'
