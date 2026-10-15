#!/usr/bin/env python3
"""Fail-closed aggregation of this workflow's actual job results."""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path


LANES = {
    "macos-smoke": "macos",
    "devcontainer-build": "devcontainer_build",
    "brew-core-profile": "brew_core",
    "devcontainer-lifecycle": "devcontainer_lifecycle",
    "neovim-locked-cold-start": "neovim_locked",
}
MAINTENANCE = {"supply-chain-provenance", "neovim-cold-start"}
JOBS = {"classify_pr", "validate", *LANES, *MAINTENANCE}


def evaluate(event: str, needs: object, cancelled: bool) -> tuple[bool, str]:
    """Only success satisfies required work; skipped needs an explicit exemption."""
    if event not in {"pull_request", "push", "schedule", "workflow_dispatch"}:
        raise ValueError("unsupported workflow event")
    if not isinstance(needs, dict) or set(needs) != JOBS:
        raise ValueError("job inventory does not match gate policy")
    for job, observation in needs.items():
        if (
            not isinstance(observation, dict)
            or not isinstance(observation.get("result"), str)
            or observation["result"] not in {"success", "failure", "cancelled", "skipped"}
        ):
            raise ValueError(f"missing or invalid result: {job}")

    required = {"validate"}
    if event == "pull_request":
        required.add("classify_pr")
        classifier = needs["classify_pr"]
        if classifier["result"] != "success":
            raise ValueError(
                "path classification did not succeed; fallback runs cannot authorize a merge"
            )
        outputs = classifier.get("outputs")
        if not isinstance(outputs, dict) or set(outputs) != set(LANES.values()):
            raise ValueError("missing or unexpected classifier outputs")
        if any(
            type(value) is not str or value not in {"0", "1"}
            for value in outputs.values()
        ):
            raise ValueError("classifier outputs must be exactly '0' or '1'")
        required.update(job for job, lane in LANES.items() if outputs[lane] == "1")
    elif event == "push":
        required.update(LANES)
    else:
        required.update(set(LANES) - {"neovim-locked-cold-start"})
        required.update(MAINTENANCE)

    passed = not cancelled
    lines = [
        f"## CI gate: {event}", "",
        "| Job | Policy | Actual result | Verdict |",
        "| --- | --- | --- | --- |",
    ]
    for job in sorted(JOBS):
        result = needs[job]["result"]
        needed = job in required
        accepted = result == "success" or (result == "skipped" and not needed)
        passed = passed and accepted
        verdict = "PASS" if accepted else "BLOCK"
        if result == "skipped" and accepted:
            verdict = "NOT APPLICABLE (not executed)"
        policy = "required" if needed else "not required"
        lines.append(f"| {job} | {policy} | {result} | {verdict} |")
    if cancelled:
        lines.extend(["", "BLOCK: workflow cancelled, even if completed jobs passed."])
    lines.extend(["", "Gate: PASS" if passed else "Gate: BLOCK"])
    return passed, "\n".join(lines) + "\n"


def main() -> int:
    try:
        cancellation = os.environ["WORKFLOW_CANCELLED"]
        if cancellation not in {"true", "false"}:
            raise ValueError("missing or invalid cancellation state")
        passed, report = evaluate(
            os.environ["GITHUB_EVENT_NAME"],
            json.loads(os.environ["NEEDS_JSON"]),
            cancellation == "true",
        )
    except (KeyError, ValueError) as error:
        passed, report = False, f"Gate: BLOCK — {error}\n"
    print(report, end="")
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with Path(summary).open("a", encoding="utf-8") as output:
            output.write(report)
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
