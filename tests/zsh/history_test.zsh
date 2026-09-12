#!/usr/bin/env zsh

set -euo pipefail

repo_root="${0:A:h:h:h}"
# Keep the interpreter available when CLI probes replace PATH (Linuxbrew Zsh
# need not be installed in /usr/bin or /bin).
zsh_binary="${commands[zsh]:A}"
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT

mkdir -p "$test_root/home" "$test_root/config/zsh" "$test_root/cache"
chezmoi execute-template --source="$repo_root" \
    < "$repo_root/home/dot_config/zsh/exports.zsh.tmpl" \
    > "$test_root/config/zsh/exports.zsh"
chezmoi execute-template --source="$repo_root" \
    < "$repo_root/home/dot_zshrc.tmpl" \
    > "$test_root/zshrc"
chezmoi execute-template --source="$repo_root" \
    < "$repo_root/home/.chezmoiscripts/run_once_after_45_migrate_zsh_history.sh.tmpl" \
    > "$test_root/migrate_history.sh"
ln -s "$repo_root/home/dot_config/zsh/aliases.zsh" "$test_root/config/zsh/aliases.zsh"
ln -s "$repo_root/home/dot_config/zsh/plugins.zsh" "$test_root/config/zsh/plugins.zsh"

print -r -- ': 1:0;legacy-history-sentinel' > "$test_root/home/.zsh_history"

export HOME="$test_root/home"
export XDG_CONFIG_HOME="$test_root/config"
export XDG_CACHE_HOME="$test_root/cache"
export XDG_STATE_HOME="$test_root/state"
export XDG_DATA_HOME="$test_root/data"
export ATUIN_CONFIG_DIR="$test_root/atuin"
export TERM="xterm-256color"

bash "$test_root/migrate_history.sh" >/dev/null
[[ -L "$HOME/.zsh_history" ]]
[[ "$(readlink "$HOME/.zsh_history")" == "$XDG_STATE_HOME/zsh/history" ]]
grep -q 'legacy-history-sentinel' "$XDG_STATE_HOME/zsh/history"

source "$repo_root/home/dot_config/zsh/plugins.zsh"

[[ "$HISTFILE" == "$XDG_STATE_HOME/zsh/history" ]]
[[ "$HISTSIZE" == 200000 ]]
[[ "$SAVEHIST" == 100000 ]]
[[ -d "${HISTFILE:h}" ]]
[[ -o appendhistory ]]
[[ -o sharehistory ]]
[[ -o histfcntllock ]]
[[ -o histsavenodups ]]

if ! zsh -dfi -c '
    source "$1" || {
        print -u2 -- "unable to source rendered zshrc"
        exit 1
    }
    assert_binding() {
        local keymap="$1" key="$2" owner="$3" actual
        actual="$(bindkey -M "$keymap" "$key")"
        [[ "$actual" == *"$owner"* ]] || {
            print -u2 -- "$keymap $key owner mismatch: $actual"
            return 1
        }
    }
    [[ -z "$FZF_CTRL_R_COMMAND" ]] || {
        print -u2 -- "FZF_CTRL_R_COMMAND must be empty"
        exit 1
    }
    assert_binding emacs "^R" atuin-search
    assert_binding viins "^R" atuin-search-viins
    assert_binding emacs "^T" fzf-file-widget
    assert_binding emacs "^[c" fzf-cd-widget
    print -s -- history-contract-sentinel || exit 1
    fc -W "$HISTFILE" || {
        print -u2 -- "unable to persist native Zsh history"
        exit 1
    }
' _ "$test_root/zshrc" 2> "$test_root/interactive.stderr"; then
    cat "$test_root/interactive.stderr" >&2
    exit 1
fi

grep -q 'history-contract-sentinel' "$HISTFILE"
grep -Eq '^enter_accept[[:space:]]*=[[:space:]]*false' \
    "$repo_root/home/dot_config/atuin/config.toml"

# Atuin reads configuration while generating init output. Reuse the same cache
# across a real config edit and check that fzf still honors an empty Ctrl-T command.
mkdir -p "$ATUIN_CONFIG_DIR"
for popup_width in 71% 83%; do
    print -rl -- '[tmux]' 'enabled = true' "width = \"$popup_width\"" \
        > "$ATUIN_CONFIG_DIR/config.toml"
    if ! FZF_CTRL_T_COMMAND='' zsh -dfi -c '
        source "$1" || exit 1
        [[ "$ATUIN_TMUX_POPUP_WIDTH" == "$2" ]] || {
            print -u2 -- "Atuin config change not reflected: $ATUIN_TMUX_POPUP_WIDTH != $2"
            exit 1
        }
        [[ "$(bindkey -M emacs "^T")" != *fzf-file-widget* ]] || {
            print -u2 -- "fzf ignored the disabled Ctrl-T command"
            exit 1
        }
        [[ "$(bindkey -M emacs "^R")" == *atuin-search* ]] || exit 1
    ' _ "$test_root/zshrc" "$popup_width" 2> "$test_root/config-change.stderr"; then
        cat "$test_root/config-change.stderr" >&2
        exit 1
    fi
done

# All sessions share one cache directory. CLI argv, the selected executable
# (including an older symlink target), and generation-time environment must
# take effect on the next startup without manually removing old init files.
mkdir -p "$test_root/first" "$test_root/second" "$test_root/selected"
for tool in direnv fzf atuin zoxide carapace starship; do
    print -r -- "#!$zsh_binary" > "$test_root/first/$tool"
    cat >> "$test_root/first/$tool" <<'EOF'
probe="${0:A:h:t}|${(j: :)@}|$INIT_PROBE_CONTEXT"
print -r -- "typeset -g _init_probe_${0:t}=${(qqq)probe}"
EOF
    chmod +x "$test_root/first/$tool"
    cp "$test_root/first/$tool" "$test_root/second/$tool"
    touch -t 200001010000 "$test_root/second/$tool"
    ln -s "$test_root/first/$tool" "$test_root/selected/$tool"
done

assert_init() {
    local bin_dir="$1" identity="$2" context="$3" rc="$4"
    local atuin_args="${5:-init zsh --disable-up-arrow}"
    env PATH="$bin_dir:/usr/bin:/bin" \
        INIT_PROBE_IDENTITY="$identity" INIT_PROBE_CONTEXT="$context" \
        INIT_PROBE_ATUIN_ARGS="$atuin_args" \
        "$zsh_binary" -dfi -c '
            source "$1" || exit 1
            typeset -A expected=(
                direnv "hook zsh" fzf "--zsh"
                atuin "$INIT_PROBE_ATUIN_ARGS" zoxide "init zsh"
                carapace "_carapace zsh" starship "init zsh"
            )
            for tool in ${(k)expected}; do
                variable="_init_probe_$tool"
                wanted="$INIT_PROBE_IDENTITY|$expected[$tool]|$INIT_PROBE_CONTEXT"
                [[ ${(P)variable} == "$wanted" ]] || {
                    print -u2 -r -- "$tool init mismatch: ${(P)variable} != $wanted"
                    exit 1
                }
            done
        ' _ "$rc"
}

assert_init "$test_root/first" first original "$test_root/zshrc"
sed 's/--disable-up-arrow/--disable-up-arrow --disable-ctrl-r/' \
    "$test_root/zshrc" > "$test_root/zshrc-changed-argv"
assert_init "$test_root/first" first original "$test_root/zshrc-changed-argv" \
    "init zsh --disable-up-arrow --disable-ctrl-r"
assert_init "$test_root/second" second original "$test_root/zshrc"
assert_init "$test_root/selected" first original "$test_root/zshrc"
for tool in direnv fzf atuin zoxide carapace starship; do
    ln -sf "$test_root/second/$tool" "$test_root/selected/$tool"
done
assert_init "$test_root/selected" second original "$test_root/zshrc"
assert_init "$test_root/selected" second changed-environment "$test_root/zshrc"

# Upgrade from the old implementation: stale generated files must not run.
mkdir -p "$XDG_CACHE_HOME/zsh/init"
for tool in direnv fzf atuin zoxide carapace starship; do
    print -r -- 'print -u2 -- "stale init cache was sourced"; exit 99' \
        > "$XDG_CACHE_HOME/zsh/init/$tool.zsh"
done
assert_init "$test_root/selected" second changed-environment "$test_root/zshrc"

print "Zsh history, init freshness and key ownership tests passed"
