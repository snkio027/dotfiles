#!/usr/bin/env python3
"""Guard deterministic CI installation ownership and cost boundaries."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = (ROOT / ".github" / "workflows" / "ci.yml").read_text(encoding="utf-8")
DOCKERFILE = (ROOT / ".devcontainer" / "Dockerfile").read_text(encoding="utf-8")
DEVCONTAINER_PROFILE = (
    ROOT / "brew" / "profiles" / "devcontainer.Brewfile"
).read_text(encoding="utf-8")


def workflow_job(name: str) -> str:
    marker = f"  {name}:\n"
    assert marker in WORKFLOW, f"CI job is missing: {name}"
    remainder = WORKFLOW.split(marker, 1)[1]
    next_job = re.search(r"^  [a-z0-9_-]+:\n", remainder, re.MULTILINE)
    return remainder[: next_job.start()] if next_job else remainder


assert "brew update" not in WORKFLOW, (
    "setup-homebrew owns metadata refresh; jobs must not repeat brew update"
)

lifecycle_job = workflow_job("devcontainer-lifecycle")
assert lifecycle_job.count("brew install devcontainer") == 1, (
    "Lifecycle host must install only the Dev Container CLI"
)
assert "quality.Brewfile" not in lifecycle_job, (
    "Lifecycle host must not install the complete quality profile"
)

cxx_marker = "      - name: Validate latest cxx-init release\n"
assert cxx_marker in WORKFLOW, "latest cxx-init conformance step is missing"
cxx_step = WORKFLOW.split(cxx_marker, 1)[1].split("      - name:", 1)[0]
maintenance_only = (
    "        if: github.event_name == 'schedule' || "
    "github.event_name == 'workflow_dispatch'\n"
)
assert cxx_step.startswith(maintenance_only), (
    "latest cxx-init conformance must run only for schedule/manual maintenance"
)

assert "apt-get" not in DOCKERFILE, (
    "the pinned Dev Container base already owns bootstrap OS packages"
)
base_commands = "bash cc curl git jq make sha256sum tar unzip xz zsh"
assert f"for command in {base_commands}; do" in DOCKERFILE, (
    "the Dockerfile must fail closed when a pinned-base command disappears"
)
assert 'command -v "$command"' in DOCKERFILE
assert DEVCONTAINER_PROFILE.count('brew "age"') == 1, (
    "the generated Dev Container Homebrew profile must own age exactly once"
)

print("Homebrew metadata refresh       setup-homebrew only")
print("Lifecycle host installation     devcontainer CLI only")
print("Latest cxx-init conformance      schedule/manual only")
print("Dev Container OS bootstrap      pinned-base capability contract")
