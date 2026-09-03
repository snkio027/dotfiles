#!/usr/bin/env bash
# DX Semantic Color System (DX-COLOR-002)
# Compiler-level warning-clean and semantic-clean validation across all 5 language fixtures.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$REPO_ROOT"

echo "==> Validating C fixture (clang -std=c23 -Wall -Wextra -Werror)..."
clang -std=c23 -Wall -Wextra -Werror -fsyntax-only tests/nvim/color/c/main.c

echo "==> Validating C++ fixture (clang++ -std=c++23 -Wall -Wextra -Werror)..."
clang++ -std=c++23 -Wall -Wextra -Werror -fsyntax-only tests/nvim/color/cpp/src/main.cpp

echo "==> Validating Rust fixture (RUSTFLAGS='-Dwarnings' cargo check)..."
RUSTFLAGS="-Dwarnings" cargo check --manifest-path tests/nvim/color/rust/Cargo.toml
rm -rf tests/nvim/color/rust/target

echo "==> Validating Zig fixture (zig build & zig ast-check)..."
zig build --build-file tests/nvim/color/zig/build.zig
zig ast-check tests/nvim/color/zig/src/main.zig

echo "==> Validating Python fixture (py_compile)..."
python3 -m py_compile tests/nvim/color/python/main.py

echo "All 5 language fixtures passed compiler-level warning-clean validation."
