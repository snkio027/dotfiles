# Read-only policy helpers; no hook installation or scanner execution occurs here.
git_default_pre_commit_path() {
    local working_tree="$1" status
    # Both a normal .git directory and a linked worktree's .git file are valid.
    # Requiring the marker also prevents accidentally discovering a parent repo.
    [ -e "$working_tree/.git" ] || return 1
    [ "$(git -C "$working_tree" rev-parse --is-inside-work-tree)" = true ] || return 1

    # An explicit path belongs to the user's hook setup (including /dev/null).
    # Do not inject into a shared/custom directory or install an inactive hook.
    if git -C "$working_tree" config --get core.hooksPath >/dev/null; then
        return 2
    else
        status=$?
        [ "$status" -eq 1 ] || return "$status"
    fi

    # Git resolves linked worktrees to their common hooks directory.
    git -C "$working_tree" rev-parse --path-format=absolute --git-path hooks/pre-commit
}

git_pre_commit_replace_status() {
    local hook_file="$1"
    if [ -L "$hook_file" ] || { [ -e "$hook_file" ] && [ ! -f "$hook_file" ]; }; then
        return 2
    fi
    if [ -f "$hook_file" ] && [ "$(sed -n '2p' "$hook_file")" != '# Managed by chezmoi' ]; then
        return 1
    fi
    return 0
}
