#!/usr/bin/env zsh

set -euo pipefail

repo_root="${0:A:h:h:h}"
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

print "Zsh history and key ownership tests passed"
