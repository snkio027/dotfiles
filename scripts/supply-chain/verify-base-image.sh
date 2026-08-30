#!/usr/bin/env bash

set -euo pipefail

fail() {
    echo "base image provenance: $*" >&2
    exit 1
}

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DOCKERFILE="${BASE_IMAGE_DOCKERFILE:-$REPO_ROOT/.devcontainer/Dockerfile}"
DOCKER_BIN="${BASE_IMAGE_DOCKER_BIN:-docker}"
JQ_BIN="${BASE_IMAGE_JQ_BIN:-jq}"
PYTHON_BIN="${BASE_IMAGE_PYTHON_BIN:-python3}"
MAX_ATTEMPTS="${BASE_IMAGE_MAX_ATTEMPTS:-3}"
TIMEOUT_SECONDS="${BASE_IMAGE_TIMEOUT_SECONDS:-45}"

command -v "$DOCKER_BIN" >/dev/null 2>&1 || fail "docker is unavailable"
command -v "$JQ_BIN" >/dev/null 2>&1 || fail "jq is unavailable"
command -v "$PYTHON_BIN" >/dev/null 2>&1 || fail "python3 is unavailable"
[[ -r "$DOCKERFILE" ]] || fail "Dockerfile is unavailable"
[[ "$MAX_ATTEMPTS" =~ ^[1-9][0-9]*$ ]] || fail "attempt count must be a positive integer"
[[ "$TIMEOUT_SECONDS" =~ ^[1-9][0-9]*$ ]] || fail "timeout must be a positive integer"

image_ref="$(awk '$1 == "FROM" { print $2; exit }' "$DOCKERFILE")"
[[ "$image_ref" =~ :resolute@sha256:([0-9a-f]{64})$ ]] || fail "base image is not pinned as resolute@sha256"
expected_digest="sha256:${BASH_REMATCH[1]}"

inspect_image() {
    local attempt
    for ((attempt = 1; attempt <= MAX_ATTEMPTS; attempt++)); do
        if "$PYTHON_BIN" - "$DOCKER_BIN" "$image_ref" "$TIMEOUT_SECONDS" <<'PY'
import subprocess
import sys

docker_bin, image_ref, timeout = sys.argv[1], sys.argv[2], int(sys.argv[3])
try:
    result = subprocess.run(
        [docker_bin, "buildx", "imagetools", "inspect", image_ref,
         "--format", "{{json .Manifest}}"],
        check=True,
        capture_output=True,
        text=True,
        timeout=timeout,
    )
except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
    if isinstance(error, subprocess.CalledProcessError) and error.stderr:
        print(error.stderr, file=sys.stderr, end="")
    raise SystemExit(1)
print(result.stdout, end="")
PY
        then
            return 0
        fi
        echo "base image provenance: registry query failed (attempt $attempt/$MAX_ATTEMPTS)" >&2
    done
    return 1
}

first_manifest="$(inspect_image)" || fail "first registry resolution is unavailable"
second_manifest="$(inspect_image)" || fail "second registry resolution is unavailable"
first_digest="$(printf '%s' "$first_manifest" | "$JQ_BIN" -er '.digest')"
second_digest="$(printf '%s' "$second_manifest" | "$JQ_BIN" -er '.digest')"

[[ "$first_digest" == "$expected_digest" ]] || fail "registry digest differs from Dockerfile"
[[ "$second_digest" == "$expected_digest" ]] || fail "repeated registry resolution drifted"
[[ "$first_manifest" == "$second_manifest" ]] || fail "repeated manifest resolution returned different objects"
printf '%s' "$first_manifest" | "$JQ_BIN" -e '
    .mediaType == "application/vnd.oci.image.index.v1+json" and
    any(.manifests[]; .platform.os == "linux" and .platform.architecture == "amd64") and
    any(.manifests[]; .platform.os == "linux" and .platform.architecture == "arm64")
' >/dev/null || fail "pinned digest is not the required multi-platform OCI index"

printf 'base image provenance verified twice: %s\n' "$expected_digest"
