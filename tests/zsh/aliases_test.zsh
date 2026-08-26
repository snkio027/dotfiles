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
