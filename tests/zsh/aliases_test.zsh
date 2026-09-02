#!/usr/bin/env zsh

set -euo pipefail

source "${0:A:h}/../../home/dot_config/zsh/aliases.zsh"

test_dir="$(mktemp -d)"
trap 'rm -rf -- "$test_dir"' EXIT

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
