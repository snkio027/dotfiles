#!/usr/bin/env bash

set -euo pipefail

fail() {
    echo "$1" >&2
    exit 1
}

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALLER="$REPO_ROOT/.devcontainer/install-chezmoi.sh"
TEST_ROOT="$(mktemp -d)"
FAKE_BIN="$TEST_ROOT/fake-bin"
DOWNLOAD_LOG="$TEST_ROOT/download.log"
mkdir -p "$FAKE_BIN"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

cat >"$FAKE_BIN/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
output=""
while (($#)); do
    case "$1" in
    --output)
        output="$2"
        shift 2
        ;;
    *)
        shift
        ;;
    esac
done
printf '%s\n' "${FAKE_CURL_MODE:?}" >>"${FAKE_CURL_LOG:?}"
case "$FAKE_CURL_MODE" in
success)
    cp "${FAKE_CURL_SOURCE:?}" "$output"
    ;;
missing)
    exit 22
    ;;
network)
    exit 7
    ;;
*)
    exit 99
    ;;
esac
EOF
chmod +x "$FAKE_BIN/curl"

make_archive() {
    local destination="${1:?archive path is required}"
    local embedded_version="${2:?embedded version is required}"
    local source_dir="$TEST_ROOT/archive-source"
    rm -rf -- "$source_dir"
    mkdir -p "$source_dir"
    cat >"$source_dir/chezmoi" <<EOF
#!/usr/bin/env bash
echo "chezmoi version v$embedded_version, commit fixture"
EOF
    chmod +x "$source_dir/chezmoi"
    tar -czf "$destination" -C "$source_dir" chezmoi
}

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

write_manifest() {
    local path="${1:?manifest path is required}"
    local amd64_sha="${2:?amd64 checksum is required}"
    local arm64_sha="${3:?arm64 checksum is required}"
    cat >"$path" <<EOF
CHEZMOI_VERSION=2.72.1
CHEZMOI_RELEASE_BASE_URL=https://invalid.example/releases/v2.72.1
CHEZMOI_LINUX_AMD64_SHA256=$amd64_sha
CHEZMOI_LINUX_ARM64_SHA256=$arm64_sha
EOF
}

run_success() {
    local arch="${1:?architecture is required}"
    local install_dir="$TEST_ROOT/success-$arch"
    local manifest="$TEST_ROOT/success-$arch.env"
    local archive="$TEST_ROOT/success-$arch.tar.gz"
    local checksum

    make_archive "$archive" 2.72.1
    checksum="$(sha256_file "$archive")"
    write_manifest "$manifest" "$checksum" "$checksum"
    FAKE_CURL_MODE=success FAKE_CURL_SOURCE="$archive" FAKE_CURL_LOG="$DOWNLOAD_LOG" \
        CHEZMOI_CURL_BIN="$FAKE_BIN/curl" CHEZMOI_OS=linux CHEZMOI_ARCH="$arch" \
        CHEZMOI_PROVENANCE_FILE="$manifest" CHEZMOI_INSTALL_DIR="$install_dir" \
        "$INSTALLER" >/dev/null
    [[ -x "$install_dir/chezmoi" ]] || fail "$arch executable was not installed"
    [[ -f "$install_dir/.chezmoi-provenance" ]] || fail "$arch receipt was not installed"
    grep -Fq "platform=linux/$arch" "$install_dir/.chezmoi-provenance" ||
        fail "$arch receipt has the wrong platform"
}

run_failure() {
    local name="${1:?case name is required}"
    local arch="${2:?architecture is required}"
    local mode="${3:?curl mode is required}"
    local embedded_version="${4:?embedded version is required}"
    local checksum_mode="${5:?checksum mode is required}"
    local install_dir="$TEST_ROOT/failure-$name"
    local manifest="$TEST_ROOT/failure-$name.env"
    local archive="$TEST_ROOT/failure-$name.tar.gz"
    local checksum

    make_archive "$archive" "$embedded_version"
    checksum="$(sha256_file "$archive")"
    if [[ "$checksum_mode" == wrong ]]; then
        checksum="$(printf '0%.0s' {1..64})"
    fi
    write_manifest "$manifest" "$checksum" "$checksum"

    if FAKE_CURL_MODE="$mode" FAKE_CURL_SOURCE="$archive" FAKE_CURL_LOG="$DOWNLOAD_LOG" \
        CHEZMOI_CURL_BIN="$FAKE_BIN/curl" CHEZMOI_OS="${CHEZMOI_TEST_OS:-linux}" CHEZMOI_ARCH="$arch" \
        CHEZMOI_PROVENANCE_FILE="$manifest" CHEZMOI_INSTALL_DIR="$install_dir" \
        "$INSTALLER" >"$TEST_ROOT/$name.log" 2>&1; then
        fail "$name unexpectedly succeeded"
    fi
    [[ ! -e "$install_dir/chezmoi" ]] || fail "$name left an executable"
    [[ ! -e "$install_dir/.chezmoi-provenance" ]] || fail "$name left a success receipt"
    ! grep -Fq 'bootstrap verified' "$TEST_ROOT/$name.log" || fail "$name emitted a success marker"
}

run_success amd64
run_success arm64
run_failure checksum amd64 success 2.72.1 wrong
run_failure missing amd64 missing 2.72.1 correct
run_failure download amd64 network 2.72.1 correct
run_failure version amd64 success 9.9.9 correct

before_unknown="$(wc -l <"$DOWNLOAD_LOG" | tr -d ' ')"
run_failure unknown riscv64 success 2.72.1 correct
after_unknown="$(wc -l <"$DOWNLOAD_LOG" | tr -d ' ')"
[[ "$before_unknown" == "$after_unknown" ]] || fail "unknown architecture attempted a download"

before_unknown_os="$after_unknown"
CHEZMOI_TEST_OS=darwin run_failure unknown-os amd64 success 2.72.1 correct
after_unknown_os="$(wc -l <"$DOWNLOAD_LOG" | tr -d ' ')"
[[ "$before_unknown_os" == "$after_unknown_os" ]] || fail "unknown operating system attempted a download"

echo "chezmoi bootstrap contract passed (2 architectures, 6 fail-closed cases)"
