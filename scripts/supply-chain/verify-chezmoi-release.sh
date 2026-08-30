#!/usr/bin/env bash

set -euo pipefail

fail() {
    echo "chezmoi provenance: $*" >&2
    exit 1
}

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROVENANCE_FILE="$REPO_ROOT/.devcontainer/chezmoi-provenance.env"
PUBLIC_KEY="$REPO_ROOT/supply-chain/chezmoi_cosign.pub"
COSIGN_BIN="${COSIGN_BIN:-cosign}"
CURL_BIN="${CURL_BIN:-curl}"

[[ -r "$PROVENANCE_FILE" ]] || fail "manifest is unavailable"
[[ -r "$PUBLIC_KEY" ]] || fail "pinned public key is unavailable"
# shellcheck disable=SC1090
source "$PROVENANCE_FILE"

command -v "$COSIGN_BIN" >/dev/null 2>&1 || fail "cosign is unavailable"
command -v "$CURL_BIN" >/dev/null 2>&1 || fail "curl is unavailable"

temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/chezmoi-provenance.XXXXXX")"
trap 'rm -rf -- "$temp_dir"' EXIT
checksums="$temp_dir/$CHEZMOI_CHECKSUMS_ASSET"
bundle="$temp_dir/$CHEZMOI_SIGSTORE_BUNDLE_ASSET"

download() {
    local asset="${1:?asset is required}"
    local output="${2:?output path is required}"
    "$CURL_BIN" --fail --location --silent --show-error \
        --retry 3 --retry-all-errors --output "$output" \
        "${CHEZMOI_RELEASE_BASE_URL%/}/$asset"
}

download "$CHEZMOI_CHECKSUMS_ASSET" "$checksums"
download "$CHEZMOI_SIGSTORE_BUNDLE_ASSET" "$bundle"

"$COSIGN_BIN" verify-blob --key "$PUBLIC_KEY" --bundle "$bundle" "$checksums"

verify_manifest_entry() {
    local arch="${1:?architecture is required}"
    local expected_sha256="${2:?checksum is required}"
    local artifact="chezmoi_${CHEZMOI_VERSION}_linux_${arch}.tar.gz"
    local -a matches

    mapfile -t matches < <(awk -v artifact="$artifact" '$2 == artifact { print $1 }' "$checksums")
    [[ "${#matches[@]}" -eq 1 ]] || fail "signed checksum does not uniquely identify $artifact"
    [[ "${matches[0]}" == "$expected_sha256" ]] || fail "manifest checksum drifted for $artifact"
}

verify_manifest_entry amd64 "$CHEZMOI_LINUX_AMD64_SHA256"
verify_manifest_entry arm64 "$CHEZMOI_LINUX_ARM64_SHA256"
printf 'chezmoi signed provenance verified %s (linux/amd64, linux/arm64)\n' "$CHEZMOI_VERSION"
