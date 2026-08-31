#!/usr/bin/env python3
"""Static supply-chain ownership and immutable-input contract checks."""

from __future__ import annotations

import json
import re
from pathlib import Path

import tomllib

ROOT = Path(__file__).resolve().parents[2]


def fail(message: str) -> None:
    raise AssertionError(message)


dockerfile = (ROOT / ".devcontainer" / "Dockerfile").read_text(encoding="utf-8")
match = re.search(
    r"^FROM (mcr\.microsoft\.com/devcontainers/base:resolute)@"
    r"(sha256:[0-9a-f]{64})$",
    dockerfile,
    re.MULTILINE,
)
if not match:
    fail("Dev Container base must retain resolute and use a manifest digest")
if match.group(2) != "sha256:00e84e24112159d45c0262f07cb013cb58cb6a415f3e1c743d4a3115ac5d76c6":
    fail("Dev Container base digest drifted without provenance review")

devcontainer = json.loads(
    (ROOT / ".devcontainer" / "devcontainer.json").read_text(encoding="utf-8")
)
if devcontainer.get("build", {}).get("context") != "..":
    fail("Dev Container build context must include the verified bootstrap inputs")
if "features" in devcontainer:
    fail("Feature dependencies require restoring a devcontainers Dependabot updater")

dependabot = (ROOT / ".github" / "dependabot.yml").read_text(encoding="utf-8")
if dependabot.count("package-ecosystem: docker") != 1:
    fail("Dependabot must own Docker image updates exactly once")
if "package-ecosystem: devcontainers" in dependabot:
    fail("The Feature-only Dependabot updater must stay absent without Features")
if not re.search(
    r"package-ecosystem: docker\n\s+directory: /\.devcontainer", dependabot
):
    fail("Docker Dependabot must target .devcontainer/Dockerfile")

manifest: dict[str, str] = {}
for raw_line in (
    ROOT / ".devcontainer" / "chezmoi-provenance.env"
).read_text(encoding="utf-8").splitlines():
    line = raw_line.strip()
    if not line or line.startswith("#"):
        continue
    key, value = line.split("=", 1)
    manifest[key] = value

if manifest.get("CHEZMOI_VERSION") != "2.72.1":
    fail("chezmoi version drifted without a signed provenance update")
expected_hashes = {
    "CHEZMOI_LINUX_AMD64_SHA256": "9f97d32caca166e5c92160ec3a9325519809c38963121cef38173142065c981f",
    "CHEZMOI_LINUX_ARM64_SHA256": "75508ef41216b6d64f3145986b751729d7f92d09c6bad77d51cf2895ab35a508",
}
for key, expected in expected_hashes.items():
    if manifest.get(key) != expected:
        fail(f"signed chezmoi checksum drifted: {key}")

with (ROOT / "brew" / "ownership.toml").open("rb") as handle:
    ownership = tomllib.load(handle)
trusted = {
    (tool["kind"], tool["name"]): tool["trusted"]
    for tool in ownership["tools"]
    if tool.get("trusted")
}
if trusted != {("tap", "hashicorp/tap"): {"formulae": ["terraform"]}}:
    fail("Homebrew trust must be object-scoped to HashiCorp Terraform")

for path in (
    ROOT / "Brewfile",
    ROOT / "brew" / "profiles" / "workstation.Brewfile",
    ROOT / "brew" / "profiles" / "devcontainer.Brewfile",
):
    content = path.read_text(encoding="utf-8")
    expected = 'tap "hashicorp/tap", trusted: { formulae: ["terraform"] }'
    if content.count(expected) != 1 or "trusted: true" in content:
        fail(f"Homebrew trust scope drifted in {path.relative_to(ROOT)}")

for path in (
    ROOT / "brew" / "profiles" / "core.Brewfile",
    ROOT / "brew" / "profiles" / "quality.Brewfile",
):
    if "trusted:" in path.read_text(encoding="utf-8"):
        fail(f"official-only profile contains explicit trust: {path.relative_to(ROOT)}")

for root in (ROOT / ".github", ROOT / "home" / ".chezmoiscripts", ROOT / "scripts"):
    for path in root.rglob("*"):
        if path.is_file() and "brew bundle cleanup" in path.read_text(
            encoding="utf-8", errors="ignore"
        ):
            fail(f"automatic path mutates the global Homebrew trust store: {path.relative_to(ROOT)}")

workflow = (ROOT / ".github" / "workflows" / "ci.yml").read_text(encoding="utf-8")


def workflow_job(name: str) -> str:
    marker = f"  {name}:\n"
    if marker not in workflow:
        fail(f"CI job is missing: {name}")
    remainder = workflow.split(marker, 1)[1]
    next_job = re.search(r"^  [a-z0-9-]+:\n", remainder, re.MULTILINE)
    return remainder[: next_job.start()] if next_job else remainder


validate_job = workflow_job("validate")
maintenance_job = workflow_job("supply-chain-provenance")
if "verify-chezmoi-release.sh" in validate_job or "check-brew-vulnerabilities.sh" in validate_job:
    fail("PR validation must not depend on live Sigstore or OSV queries")
for test in ("chezmoi_bootstrap_test.sh", "brew_vulnerabilities_test.sh"):
    if test not in validate_job:
        fail(f"PR validation does not exercise the local state contract: {test}")
if "github.event_name == 'schedule' || github.event_name == 'workflow_dispatch'" not in maintenance_job:
    fail("live provenance checks must be limited to schedule/manual events")
if "sigstore/cosign-installer@6f9f17788090df1f26f669e9d70d6ae9567deba6" not in maintenance_job:
    fail("maintenance Cosign verifier must stay pinned to an immutable action commit")
for command in (
    "scripts/supply-chain/verify-chezmoi-release.sh",
    "scripts/supply-chain/check-brew-vulnerabilities.sh",
):
    if command not in maintenance_job:
        fail(f"maintenance CI does not exercise {command}")
if "scripts/supply-chain/verify-base-image.sh" not in workflow_job("devcontainer-build"):
    fail("Dev Container build does not verify its immutable base")

print("Docker provenance contract     tag + multi-platform digest")
print("Dependabot ownership           docker only (no Features)")
print("chezmoi bootstrap artifacts    linux/amd64 + linux/arm64")
print("Homebrew explicit trust        hashicorp/tap/terraform only")
print("Live upstream checks           schedule/manual only")
