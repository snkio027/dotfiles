#!/usr/bin/env zsh

set -euo pipefail
unsetopt BGNICE

# This regression only loads runtime configuration in disposable homes. It never
# renders or executes a chezmoi entry script and never opens the user's history.
repo_root="${0:A:h:h:h}"
plugins="$repo_root/home/dot_config/zsh/plugins.zsh"
zsh_binary="${commands[zsh]:A}"
test_root="$(mktemp -d)"
typeset -a children=()
cleanup() {
    local child
    for child in "${children[@]}"; do
        kill "$child" 2>/dev/null || true
        wait "$child" 2>/dev/null || true
    done
    rm -rf -- "$test_root"
}
trap cleanup EXIT

new_home() {
    case_home="$test_root/$1/home"
    case_state="$test_root/$1/state with spaces"
    mkdir -p "$case_home"
}

run_zsh() {
    env -i PATH="$PATH" HOME="$case_home" XDG_STATE_HOME="$case_state" \
        XDG_CACHE_HOME="$case_home/.cache" TERM=xterm-256color \
        "$zsh_binary" "$@"
}

assert_config() {
    run_zsh -dfc '
        set -eu
        source "$1"
        [[ "$HISTFILE" == "$2" ]] || {
            print -u2 -r -- "history path mismatch: $HISTFILE != $2"
            exit 1
        }
        [[ "$HISTSIZE" == 200000 && "$SAVEHIST" == 100000 ]]
        [[ -o appendhistory && -o sharehistory && -o histfcntllock ]]
        [[ -o histsavenodups && -o histsavebycopy ]]
    ' _ "$plugins" "$1"
}

write_history() {
    run_zsh -dfi -c '
        set -eu
        source "$1"
        [[ "$HISTFILE" == "$2" && -o histsavebycopy ]]
        [[ ! -f "$HISTFILE" ]] || fc -R "$HISTFILE"
        print -s -- "$3"
        fc -W "$HISTFILE"
    ' _ "$plugins" "$1" "$2"
}

# No legacy file: use the XDG default or its explicit override, with a private
# directory. Creating or restarting a shell must not introduce a legacy alias.
for destination in default override; do
    new_home "fresh-$destination"
    [[ "$destination" != default ]] || case_state=''
    expected="${case_state:-$case_home/.local/state}/zsh/history"
    assert_config "$expected"
    zmodload zsh/stat
    typeset -A directory_stat
    zstat -H directory_stat -- "${expected:h}"
    # Decimal 511/448 are octal 0777/0700; do not change Zsh's output base.
    (( (directory_stat[mode] & 511) == 448 ))
    write_history "$expected" "fresh-$destination-sentinel"
    assert_config "$expected"
    grep -q "fresh-$destination-sentinel" "$expected"
    [[ ! -e "$case_home/.zsh_history" && ! -L "$case_home/.zsh_history" ]]
done

# An existing regular history stays at the pathname held by older shells. No
# migration, symlink, or XDG history is created behind their backs.
new_home legacy
legacy="$case_home/.zsh_history"
print -r -- ': 1:0;legacy-history-sentinel' > "$legacy"
cp "$legacy" "$test_root/legacy.before"
assert_config "$legacy"
cmp "$legacy" "$test_root/legacy.before"
write_history "$legacy" legacy-new-session-sentinel
assert_config "$legacy"
grep -q legacy-history-sentinel "$legacy"
grep -q legacy-new-session-sentinel "$legacy"
[[ ! -L "$legacy" && ! -e "$case_state/zsh/history" ]]

# Already split histories are not silently merged or deleted. New sessions use
# the legacy pathname; the XDG file remains available for a deliberate recovery.
new_home split
legacy="$case_home/.zsh_history"
xdg="$case_state/zsh/history"
mkdir -p "${xdg:h}"
print -r -- ': 1:0;split-legacy-sentinel' > "$legacy"
print -r -- ': 2:0;split-xdg-sentinel' > "$xdg"
cp "$legacy" "$test_root/split-legacy.before"
cp "$xdg" "$test_root/split-xdg.before"
assert_config "$legacy"
cmp "$legacy" "$test_root/split-legacy.before"
cmp "$xdg" "$test_root/split-xdg.before"
write_history "$legacy" split-new-session-sentinel
assert_config "$legacy"
grep -q split-legacy-sentinel "$legacy"
grep -q split-new-session-sentinel "$legacy"
! grep -q split-xdg-sentinel "$legacy"
cmp "$xdg" "$test_root/split-xdg.before"

# Unknown absolute, relative, and dangling links belong to the user. The runtime
# uses XDG without replacing those links or modifying their custom targets.
for link_kind in absolute relative dangling; do
    new_home "custom-$link_kind"
    legacy="$case_home/.zsh_history"
    custom="$case_home/custom-history"
    print -r -- ': 1:0;custom-history-sentinel' > "$custom"
    cp "$custom" "$test_root/custom.before"
    case "$link_kind" in
        absolute) target="$custom" ;;
        relative) target=custom-history ;;
        dangling) target="$case_home/missing-history" ;;
    esac
    ln -s "$target" "$legacy"
    assert_config "$case_state/zsh/history"
    write_history "$case_state/zsh/history" "custom-$link_kind-xdg-sentinel"
    assert_config "$case_state/zsh/history"
    [[ -L "$legacy" && "$(readlink "$legacy")" == "$target" ]]
    cmp "$custom" "$test_root/custom.before"
    [[ "$link_kind" != dangling || ! -e "$target" ]]
done

# Lexically removing '..' can cross a directory symlink and change its meaning.
# A custom target must not be treated as managed merely because :a produces the
# same spelling. Cover the ambiguous component in either side of the comparison.
for parent_component in target xdg; do
    new_home "custom-parent-$parent_component"
    legacy="$case_home/.zsh_history"
    other="$test_root/custom-parent-$parent_component/other"
    mkdir -p "$case_state/zsh" "$other/subdir" "$other/zsh"
    ln -s "$other/subdir" "$case_state/through"
    if [[ "$parent_component" == target ]]; then
        target="$case_state/through/../zsh/history"
        custom="$other/zsh/history"
    else
        target="$case_state/zsh/history"
        custom="$target"
        case_state="$case_state/through/.."
    fi
    xdg="$case_state/zsh/history"
    print -r -- ': 1:0;custom-parent-history-sentinel' > "$custom"
    print -r -- ': 2:0;custom-parent-xdg-sentinel' > "$xdg"
    cp "$custom" "$test_root/custom-parent.before"
    ln -s "$target" "$legacy"
    assert_config "$xdg"
    write_history "$xdg" "custom-parent-$parent_component-new-sentinel"
    assert_config "$xdg"
    [[ -L "$legacy" && "$(readlink "$legacy")" == "$target" ]]
    cmp "$custom" "$test_root/custom-parent.before"
    grep -q custom-parent-xdg-sentinel "$xdg"
    grep -q "custom-parent-$parent_component-new-sentinel" "$xdg"
done

# A previous migration may have left a broken managed link. Recreate only its
# XDG parent, then let the normal copy-on-save produce a regular legacy file.
new_home managed-dangling
legacy="$case_home/.zsh_history"
ln -s "$case_state/zsh/history" "$legacy"
assert_config "$legacy"
[[ -L "$legacy" && -d "$case_state/zsh" ]]
write_history "$legacy" managed-dangling-sentinel
[[ ! -L "$legacy" ]]
grep -q managed-dangling-sentinel "$legacy"
assert_config "$legacy"

# Keep both real shell processes alive across an old-shell rewrite. The new
# shell must select the legacy pathname *before* the link is replaced, retain
# default copy-on-save, and still write there after the old shell has saved.
# Also accept harmless dot normalization and exact XDG targets containing '..'.
for spelling in exact normalized exact-parent; do
    new_home "managed-$spelling"
    if [[ "$spelling" == exact-parent ]]; then
        other="$test_root/managed-$spelling/other"
        mkdir -p "$case_state" "$other/subdir"
        ln -s "$other/subdir" "$case_state/through"
        case_state="$case_state/through/.."
    fi
    legacy="$case_home/.zsh_history"
    xdg="$case_state/zsh/history"
    mkdir -p "${xdg:h}"
    print -r -- ': 1:0;managed-original-sentinel' > "$xdg"
    cp "$xdg" "$test_root/managed.before"
    target="$xdg"
    [[ "$spelling" != normalized ]] || target="$case_state/./zsh/history"
    ln -s "$target" "$legacy"
    assert_config "$legacy"
    [[ -L "$legacy" && "$(readlink "$legacy")" == "$target" ]]
    mkfifo "$case_home/old.ready" "$case_home/old.go" \
        "$case_home/new.ready" "$case_home/new.go"
    # Open both sides so a failed child cannot leave the test blocked opening a
    # FIFO; bounded reads report the failure and the EXIT trap reaps children.
    exec {old_ready_fd}<> "$case_home/old.ready"
    exec {old_go_fd}<> "$case_home/old.go"
    exec {new_ready_fd}<> "$case_home/new.ready"
    exec {new_go_fd}<> "$case_home/new.go"

    env -i PATH="$PATH" HOME="$case_home" XDG_STATE_HOME="$case_state" \
        XDG_CACHE_HOME="$case_home/.cache" TERM=xterm-256color \
        "$zsh_binary" -dfi -c '
        set -eu
        HISTFILE="$HOME/.zsh_history"
        HISTSIZE=200000 SAVEHIST=100000
        setopt APPEND_HISTORY SHARE_HISTORY EXTENDED_HISTORY HIST_FCNTL_LOCK
        [[ -o histsavebycopy ]]
        fc -R "$HISTFILE"
        print -r -- ready > "$HOME/old.ready"
        read -r -t 20 signal < "$HOME/old.go"
        print -s -- old-shell-rewrite-sentinel
        fc -W "$HISTFILE"
    ' &
    old_pid=$!
    children+=("$old_pid")
    env -i PATH="$PATH" HOME="$case_home" XDG_STATE_HOME="$case_state" \
        XDG_CACHE_HOME="$case_home/.cache" TERM=xterm-256color \
        "$zsh_binary" -dfi -c '
        set -eu
        source "$1"
        [[ "$HISTFILE" == "$HOME/.zsh_history" && -o histsavebycopy ]]
        print -r -- ready > "$HOME/new.ready"
        read -r -t 20 signal < "$HOME/new.go"
        fc -R "$HISTFILE"
        print -s -- new-shell-rewrite-sentinel
        fc -W "$HISTFILE"
    ' _ "$plugins" &
    new_pid=$!
    children+=("$new_pid")
    read -r -t 20 -u "$old_ready_fd" ready
    read -r -t 20 -u "$new_ready_fd" ready
    print -r -- save >&$old_go_fd
    wait "$old_pid"
    children=("$new_pid")
    [[ ! -L "$legacy" && -f "$legacy" ]]
    cmp "$xdg" "$test_root/managed.before"
    print -r -- save >&$new_go_fd
    wait "$new_pid"
    children=()
    exec {old_ready_fd}>&-
    exec {old_go_fd}>&-
    exec {new_ready_fd}>&-
    exec {new_go_fd}>&-
    grep -q managed-original-sentinel "$legacy"
    grep -q old-shell-rewrite-sentinel "$legacy"
    grep -q new-shell-rewrite-sentinel "$legacy"
    cmp "$xdg" "$test_root/managed.before"
    assert_config "$legacy"
    write_history "$legacy" restarted-shell-sentinel
    grep -q restarted-shell-sentinel "$legacy"
    grep -q old-shell-rewrite-sentinel "$legacy"
    grep -q new-shell-rewrite-sentinel "$legacy"
    cmp "$xdg" "$test_root/managed.before"
done

print 'Zsh history compatibility: fresh XDG, legacy, split, custom links, atomic rewrite and restart passed'
