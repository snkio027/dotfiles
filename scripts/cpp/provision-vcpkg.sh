#!/usr/bin/env bash
# Machine-owned Git checkout; project manifests own their dependency baselines.
set -euo pipefail

BREW_PREFIX="${1:?absolute Homebrew prefix is required}"
export VCPKG_ROOT="${VCPKG_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/vcpkg}"
[[ "$BREW_PREFIX" == /* && "$VCPKG_ROOT" == /* ]] || {
    echo 'Homebrew prefix and VCPKG_ROOT must be absolute paths' >&2
    exit 1
}
GIT_BIN="$BREW_PREFIX/bin/git"
[[ -x "$GIT_BIN" ]] || {
    echo "Brew Git is missing: $GIT_BIN" >&2
    exit 1
}
export PATH="$BREW_PREFIX/bin:$PATH"
# Do not let a caller's repository environment redirect checkout operations.
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES

# Used only for a fresh installation; never reset/pull an existing checkout.
INITIAL_REVISION=434307da09bc05b2c86996dccc8b2351fc0d5d37
target="$VCPKG_ROOT"
staging=""
if [[ ! -e "$target" && ! -L "$target" ]]; then
    mkdir -p -- "$(dirname -- "$target")"
    staging="$(mktemp -d "$(dirname -- "$target")/.vcpkg-bootstrap.XXXXXX")"
    trap 'rm -rf -- "$staging"' EXIT
    "$GIT_BIN" clone --no-checkout https://github.com/microsoft/vcpkg.git "$staging/checkout"
    target="$staging/checkout"
    "$GIT_BIN" -C "$target" checkout --detach "$INITIAL_REVISION"
fi

[[ -d "$target" && ! -L "$target" && -f "$target/scripts/buildsystems/vcpkg.cmake" ]] || {
    echo "Invalid vcpkg checkout (left unchanged): $target" >&2
    exit 1
}
[[ "$("$GIT_BIN" -C "$target" rev-parse --show-toplevel)" == "$(cd "$target" && pwd -P)" ]] || {
    echo "VCPKG_ROOT is not a Git checkout root: $target" >&2
    exit 1
}
if [[ ! -e "$target/vcpkg" && ! -L "$target/vcpkg" ]]; then
    case "$("$GIT_BIN" -C "$target" remote get-url origin)" in
        https://github.com/microsoft/vcpkg | https://github.com/microsoft/vcpkg.git) ;;
        *)
            echo 'Refusing bootstrap from an unrecognized vcpkg origin' >&2
            exit 1
            ;;
    esac
    "$GIT_BIN" -C "$target" diff --exit-code HEAD -- bootstrap-vcpkg.sh scripts/bootstrap.sh
    (cd "$target" && VCPKG_ROOT="$target" bash ./bootstrap-vcpkg.sh -disableMetrics)
fi
[[ -x "$target/vcpkg" ]] || {
    echo "vcpkg is not executable: $target/vcpkg" >&2
    exit 1
}
version="$(VCPKG_ROOT="$target" VCPKG_DISABLE_METRICS=1 "$target/vcpkg" version)"
if [[ -n "$staging" ]]; then
    [[ ! -e "$VCPKG_ROOT" && ! -L "$VCPKG_ROOT" ]] || {
        echo 'VCPKG_ROOT appeared during bootstrap; refusing to overwrite it' >&2
        exit 1
    }
    mv -- "$target" "$VCPKG_ROOT"
fi
printf 'vcpkg ready: %s\n%s\n' "$VCPKG_ROOT" "$version"
