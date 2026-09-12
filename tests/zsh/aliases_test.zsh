#!/usr/bin/env zsh

set -euo pipefail

source "${0:A:h}/../../home/dot_config/zsh/aliases.zsh"

# Inspect registered aliases/functions, not incidental config-path strings.
assert_mason_only_markdownlint() {
  [[ -z "${aliases[(R)*markdownlint-cli2*]}" ]] &&
    (( ! ${+aliases[markdownlint-cli2]} && ! ${+functions[markdownlint-cli2]} ))
}
assert_mason_only_markdownlint
alias mdl='markdownlint-cli2 --fix'
if assert_mason_only_markdownlint; then
  print -u2 'Shell Markdownlint alias escaped ownership control'
  exit 1
fi
unalias mdl

test_dir="$(mktemp -d)"
trap 'rm -rf -- "$test_dir"' EXIT
real_nvim="$(command -v nvim)"
repo_root="${0:A:h:h:h}"

print -r -- 'PLAIN=alpha' > "$test_dir/valid.env"
print -r -- 'export EMPTY=' >> "$test_dir/valid.env"
print -r -- "SINGLE='hello world'" >> "$test_dir/valid.env"
print -r -- 'DOUBLE="literal value"' >> "$test_dir/valid.env"
print -r -- 'HASH=abc#def' >> "$test_dir/valid.env"

dotenv "$test_dir/valid.env"
[[ "$PLAIN" == alpha ]]
[[ -z "$EMPTY" ]]
[[ "$SINGLE" == "hello world" ]]
[[ "$DOUBLE" == "literal value" ]]
[[ "$HASH" == "abc#def" ]]

export SAFE=unchanged
unset PWNED 2>/dev/null || true
print -r -- 'SAFE=changed' > "$test_dir/unsafe.env"
print -r -- 'PWNED=$(printf owned)' >> "$test_dir/unsafe.env"

if dotenv "$test_dir/unsafe.env" 2>/dev/null; then
  print -u2 "dotenv accepted command substitution"
  exit 1
fi
[[ "$SAFE" == unchanged ]]
(( ! ${+PWNED} ))

ln -s "$test_dir/valid.env" "$test_dir/link.env"
if dotenv "$test_dir/link.env" 2>/dev/null; then
  print -u2 "dotenv accepted a symbolic link"
  exit 1
fi

print "dotenv behavior tests passed"

fake_bin="$test_dir/bin"
chezmoi_log="$test_dir/chezmoi.log"
mkdir -p "$fake_bin"
cat > "$fake_bin/chezmoi" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

{
  printf 'argc=%d' "$#"
  printf ' arg=%q' "$@"
  printf '\n'
} >> "$CHEZMOI_TEST_LOG"

if [[ "${CHEZMOI_TEST_FAIL_UPDATE:-0}" == 1 && "${1:-}" == update ]]; then
  exit 72
fi
if [[ "${1:-}" == source-path ]]; then
  printf '%s\n' "$DEVUP_SOURCE"
fi
EOF
chmod +x "$fake_bin/chezmoi"

export CHEZMOI_TEST_LOG="$chezmoi_log"
PATH="$fake_bin:$PATH"

czu
[[ "$(sed -n '1p' "$chezmoi_log")" == 'argc=2 arg=update arg=--apply=false' ]]
[[ "$(sed -n '2p' "$chezmoi_log")" == 'argc=1 arg=diff' ]]
[[ "$(wc -l < "$chezmoi_log" | tr -d ' ')" == 2 ]]

: > "$chezmoi_log"
if CHEZMOI_TEST_FAIL_UPDATE=1 czu 2>/dev/null; then
  print -u2 "czu ignored a failed source update"
  exit 1
fi
[[ "$(cat "$chezmoi_log")" == 'argc=2 arg=update arg=--apply=false' ]]

: > "$chezmoi_log"
for rejected_arg in --apply --apply=true -a -va -na -ar -ra -av arbitrary; do
  if czu "$rejected_arg" 2>/dev/null; then
    print -u2 "czu accepted an argument: $rejected_arg"
    exit 1
  fi
done
[[ ! -s "$chezmoi_log" ]]

print "czu argument rejection 9/9; failed update stops before diff"

# A candidate may update only its own config/data/state/cache, never source or daily state.
export DEVUP_SOURCE="$test_dir/source repo/home"
mkdir -p "$DEVUP_SOURCE/dot_config/"{nvim,neocmakelsp,markdownlint-cli2} "$DEVUP_SOURCE/../scripts/nvim"
print 'source lock' > "$DEVUP_SOURCE/dot_config/nvim/lazy-lock.json"
print 'markdown config' > "$DEVUP_SOURCE/dot_config/markdownlint-cli2/config.yaml"
touch "$DEVUP_SOURCE/../scripts/nvim/update_candidate.lua"
export XDG_CONFIG_HOME="$test_dir/daily/config" XDG_DATA_HOME="$test_dir/daily/data"
export XDG_STATE_HOME="$test_dir/daily/state" XDG_CACHE_HOME="$test_dir/daily/cache"
export NVIM_APPNAME=poison NVIM_LOG_FILE="$test_dir/daily/log"
mkdir -p "$test_dir/daily"/{config,data,state,cache} "$test_dir/candidates"
for location in config data state cache; do
  print unchanged > "$test_dir/daily/$location/sentinel"
done
export TMPDIR="$test_dir/candidates" DEVUP_CALLS="$test_dir/calls"
cat > "$fake_bin/nvim" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
root="${XDG_CONFIG_HOME%/config}"
[[ "$root" == "$TMPDIR"/dotfiles-nvim-candidate.* ]]
[[ "$XDG_DATA_HOME" == "$root/data" && "$XDG_STATE_HOME" == "$root/state" ]]
[[ "$XDG_CACHE_HOME" == "$root/cache" && "$NVIM_LOG_FILE" == "$root/state/nvim.log" ]]
[[ "$NVIM_APPNAME" == nvim && "$PWD" == "${DEVUP_SOURCE%/home}" ]]
case "${*: -1}" in
  scripts/nvim/update_candidate.lua) phase=update; marker='Neovim plugin candidate downloaded.' ;;
  tests/nvim/provision.lua) phase=provision; marker='Tree-sitter evidence parser provisioning 5/5' ;;
  tests/nvim/smoke.lua) phase=smoke; marker='Neovim toolchain smoke tests passed' ;;
  *) exit 91 ;;
esac
printf '%s\n' "$phase" >> "$DEVUP_CALLS"
printf 'candidate lock\n' > "$XDG_CONFIG_HOME/nvim/lazy-lock.json"
for location in "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"; do
  printf 'candidate only\n' > "$location/write"
done
[[ "${DEVUP_FAIL:-}" != "$phase" ]] || exit 47
[[ "${DEVUP_OMIT_MARKER:-}" == "$phase" ]] || printf '%s\n' "$marker"
EOF
cat > "$fake_bin/brew" <<'EOF'
#!/bin/sh
echo 'unexpected global update' >> "$DEVUP_CALLS"
exit 99
EOF
cp "$fake_bin/brew" "$fake_bin/uv"
chmod +x "$fake_bin/"{nvim,brew,uv}
for scenario in success update provision smoke no-marker; do
  : > "$DEVUP_CALLS"
  export DEVUP_FAIL='' DEVUP_OMIT_MARKER=''
  [[ "$scenario" == success || "$scenario" == no-marker ]] || DEVUP_FAIL="$scenario"
  [[ "$scenario" != no-marker ]] || DEVUP_OMIT_MARKER=provision
  result=0
  devup > "$test_dir/devup.log" 2>&1 || result=$?
  candidate="$(sed -n 's/^devup candidate: //p' "$test_dir/devup.log")"
  [[ -d "$candidate" && -x "$candidate/nvim" ]]
  [[ "$(cat "$candidate/config/markdownlint-cli2/config.yaml")" == 'markdown config' ]]
  case "$scenario" in
    success) [[ "$result" == 0 ]]; grep -q 'toolchain smoke 通过' "$test_dir/devup.log" ;;
    no-marker) [[ "$result" == 1 ]] ;;
    *) [[ "$result" == 47 ]] ;;
  esac
  [[ "$scenario" == success ]] || ! grep -q 'toolchain smoke 通过' "$test_dir/devup.log"
  case "$scenario" in
    update) [[ "$(cat "$DEVUP_CALLS")" == update ]] ;;
    provision|no-marker) [[ "$(cat "$DEVUP_CALLS")" == $'update\nprovision' ]] ;;
    *) [[ "$(cat "$DEVUP_CALLS")" == $'update\nprovision\nsmoke' ]] ;;
  esac
  [[ "$(cat "$DEVUP_SOURCE/dot_config/nvim/lazy-lock.json")" == 'source lock' ]]
  for location in config data state cache; do
    [[ "$(cat "$test_dir/daily/$location/sentinel")" == unchanged ]]
    [[ ! -e "$test_dir/daily/$location/write" ]]
  done
  [[ ! -e "$NVIM_LOG_FILE" && "$NVIM_APPNAME" == poison ]]
done
if devup --apply >/dev/null 2>&1; then
  print -u2 'devup accepted an adoption argument'
  exit 1
fi

# Lazy records task errors without throwing. Real Neovim must still exit nonzero.
cat > "$test_dir/update-probe.lua" <<'EOF'
local mode = vim.env.DEVUP_PROBE
package.preload.lazy = function()
  return { sync = function(opts) assert(opts.wait and opts.show == false) end }
end
package.preload['lazy.core.config'] = function()
  local task = {
    running = function() return mode == 'running' end,
    has_errors = function() return mode == 'error' end,
    output = function() return 'injected task failure' end,
  }
  return { plugins = { fixture = { name = 'fixture', _ = { tasks = { task } } } }, to_clean = {} }
end
if mode == 'startup' then vim.v.errmsg = 'injected startup failure' end
dofile(vim.env.DEVUP_UPDATE_SCRIPT)
EOF
export DEVUP_UPDATE_SCRIPT="$repo_root/scripts/nvim/update_candidate.lua"
for mode in success error running startup; do
  result=0
  DEVUP_PROBE="$mode" "$real_nvim" --headless -u NONE -n -i NONE \
    "+luafile $repo_root/tests/nvim/run_contract.lua" "$test_dir/update-probe.lua" \
    > "$test_dir/probe.log" 2>&1 || result=$?
  if [[ "$mode" == success ]]; then
    [[ "$result" == 0 ]]; grep -q 'Neovim plugin candidate downloaded.' "$test_dir/probe.log"
  else
    [[ "$result" == 1 ]]; ! grep -q 'Neovim plugin candidate downloaded.' "$test_dir/probe.log"
  fi
done
print 'devup isolation, failure propagation, completion markers and Lazy task error controls passed'
