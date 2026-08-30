#!/usr/bin/env bash

set -euo pipefail

fail() {
    echo "chezmoi bootstrap: $*" >&2
    exit 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROVENANCE_FILE="${CHEZMOI_PROVENANCE_FILE:-$SCRIPT_DIR/chezmoi-provenance.env}"
[[ -r "$PROVENANCE_FILE" ]] || fail "provenance manifest is unavailable: $PROVENANCE_FILE"

# shellcheck disable=SC1090
source "$PROVENANCE_FILE"

required_values=(
    CHEZMOI_VERSION
    CHEZMOI_RELEASE_BASE_URL
    CHEZMOI_LINUX_AMD64_SHA256
    CHEZMOI_LINUX_ARM64_SHA256
)
for required_value in "${required_values[@]}"; do
    [[ -n "${!required_value:-}" ]] || fail "manifest value is missing: $required_value"
done

[[ "$CHEZMOI_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "invalid version: $CHEZMOI_VERSION"
[[ "$CHEZMOI_LINUX_AMD64_SHA256" =~ ^[0-9a-f]{64}$ ]] || fail "invalid amd64 checksum"
[[ "$CHEZMOI_LINUX_ARM64_SHA256" =~ ^[0-9a-f]{64}$ ]] || fail "invalid arm64 checksum"

requested_os="${CHEZMOI_OS:-$(uname -s)}"
case "${requested_os,,}" in
    linux) ;;
    *) fail "unsupported operating system: $requested_os" ;;
esac

requested_arch="${CHEZMOI_ARCH:-$(uname -m)}"
case "$requested_arch" in
    amd64 | x86_64)
        release_arch="amd64"
        expected_sha256="$CHEZMOI_LINUX_AMD64_SHA256"
        ;;
    arm64 | aarch64)
        release_arch="arm64"
        expected_sha256="$CHEZMOI_LINUX_ARM64_SHA256"
        ;;
    *)
        fail "unsupported Linux architecture: $requested_arch"
        ;;
esac

install_dir="${CHEZMOI_INSTALL_DIR:-${HOME:?HOME is required}/.local/bin}"
target="$install_dir/chezmoi"
receipt="${CHEZMOI_RECEIPT_PATH:-$install_dir/.chezmoi-provenance}"
download_base="${CHEZMOI_DOWNLOAD_BASE_URL:-$CHEZMOI_RELEASE_BASE_URL}"
artifact="chezmoi_${CHEZMOI_VERSION}_linux_${release_arch}.tar.gz"
archive_url="${download_base%/}/$artifact"
curl_bin="${CHEZMOI_CURL_BIN:-curl}"

command -v "$curl_bin" >/dev/null 2>&1 || fail "curl is unavailable: $curl_bin"
command -v tar >/dev/null 2>&1 || fail "tar is unavailable"

temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/chezmoi-bootstrap.XXXXXX")"
archive="$temp_dir/$artifact"
extract_dir="$temp_dir/extract"
staged_target="$temp_dir/chezmoi.install"
staged_receipt="$temp_dir/chezmoi.receipt"
installed_by_this_run=false

cleanup() {
    if [[ "$installed_by_this_run" == true ]]; then
        rm -f -- "$target" "$receipt"
    fi
    rm -rf -- "$temp_dir"
}
trap cleanup EXIT

if ! "$curl_bin" --fail --location --silent --show-error \
    --retry 3 --retry-all-errors --output "$archive" "$archive_url"; then
    fail "download failed: $artifact"
fi

if command -v sha256sum >/dev/null 2>&1; then
    actual_sha256="$(sha256sum "$archive" | awk '{print $1}')"
elif command -v shasum >/dev/null 2>&1; then
    actual_sha256="$(shasum -a 256 "$archive" | awk '{print $1}')"
else
    fail "no SHA-256 implementation is available"
fi
[[ "$actual_sha256" == "$expected_sha256" ]] || fail "checksum mismatch for $artifact"

mkdir -p "$extract_dir"
tar -xzf "$archive" -C "$extract_dir"
[[ -f "$extract_dir/chezmoi" ]] || fail "verified archive does not contain chezmoi"
chmod 0755 "$extract_dir/chezmoi"
version_output="$("$extract_dir/chezmoi" --version 2>/dev/null || true)"
[[ "$version_output" == "chezmoi version v$CHEZMOI_VERSION,"* ]] ||
    fail "embedded version does not match $CHEZMOI_VERSION"

install -m 0755 "$extract_dir/chezmoi" "$staged_target"
printf 'version=%s\nplatform=linux/%s\nartifact=%s\nsha256=%s\n' \
    "$CHEZMOI_VERSION" "$release_arch" "$artifact" "$expected_sha256" >"$staged_receipt"

mkdir -p "$install_dir" "$(dirname "$receipt")"
mv "$staged_target" "$target"
installed_by_this_run=true
mv "$staged_receipt" "$receipt"
installed_by_this_run=false
trap - EXIT
rm -rf -- "$temp_dir"

printf 'chezmoi bootstrap verified %s linux/%s\n' "$CHEZMOI_VERSION" "$release_arch"
