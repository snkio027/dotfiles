#!/usr/bin/env python3

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any


EXPECTED_CASES = ["m5", "native-mocha", "native-macchiato", "native-frappe"]


def load(path: str) -> dict[str, Any]:
    with Path(path).open(encoding="utf-8") as handle:
        return json.load(handle)


def observation_identity(observation: dict[str, Any]) -> dict[str, Any]:
    return {
        "language": observation["language"],
        "tag": observation["tag"],
        "token": observation["token"],
        "position": observation["position"],
    }


def raw_token_facts(observation: dict[str, Any]) -> list[dict[str, Any]]:
    facts = []
    for token in observation["raw_semantic_tokens"]:
        facts.append(
            {
                "provider": token["provider"],
                "position_encoding": token["position_encoding"],
                "row": token["row"],
                "start_col": token["start_col"],
                "end_col": token["end_col"],
                "type": token["type"],
                "modifiers": token["modifiers"],
            }
        )
    return sorted(facts, key=lambda token: json.dumps(token, sort_keys=True))


def validate_reports(reports: list[dict[str, Any]]) -> None:
    if len(reports) != 4:
        raise ValueError("expected exactly four E1 reports")
    case_names = [report["case"] for report in reports]
    if case_names != EXPECTED_CASES:
        raise ValueError(
            f"case order drift: expected {EXPECTED_CASES}, observed {case_names}"
        )
    if any(report.get("schema") != 2 for report in reports):
        raise ValueError("E1 report schema drift")

    run_ids = {report.get("run_id") for report in reports}
    if None in run_ids or "" in run_ids or len(run_ids) != 1:
        raise ValueError(f"run ID mismatch or missing: {sorted(map(str, run_ids))}")

    baseline_input = reports[0].get("input_identity")
    for report in reports[1:]:
        if report.get("input_identity") != baseline_input:
            raise ValueError(
                f"input identity drift between {reports[0]['case']} and {report['case']}"
            )

    baseline_observations = reports[0]["observations"]
    baseline_positions = [observation_identity(item) for item in baseline_observations]
    baseline_tokens = [raw_token_facts(item) for item in baseline_observations]
    for report in reports[1:]:
        positions = [observation_identity(item) for item in report["observations"]]
        if positions != baseline_positions:
            raise ValueError(
                f"observation identity/position drift between {reports[0]['case']} and {report['case']}"
            )
        tokens = [raw_token_facts(item) for item in report["observations"]]
        if tokens != baseline_tokens:
            raise ValueError(
                f"raw semantic token facts drift between {reports[0]['case']} and {report['case']}"
            )


def render(reports: list[dict[str, Any]]) -> str:
    lines = [
        "# Catppuccin native-first E1 generated summary",
        "",
        f"Run ID: `{reports[0]['run_id']}`",
        "",
        "| Case | Flavour | Normal background | Graph groups | Graph SHA-256 | Observations |",
        "| --- | --- | --- | ---: | --- | ---: |",
    ]
    for report in reports:
        graph = report["highlight_graph"]
        lines.append(
            f"| `{report['case']}` | `{report['flavour']}` | "
            f"`{report['normal']['bg']}` | {graph['count']} | "
            f"`{graph['sha256']}` | {len(report['observations'])} |"
        )
    lines.extend(
        [
            "",
            "Input identity, observation positions, and normalized raw token facts match across all four cases.",
            "Visual winners and resolved attributes are deliberately not required to match.",
            "All four rows are harness observations, not a visual-policy verdict.",
        ]
    )
    return "\n".join(lines) + "\n"


def main(paths: list[str]) -> None:
    reports = [load(path) for path in paths]
    try:
        validate_reports(reports)
    except (KeyError, TypeError, ValueError) as error:
        raise SystemExit(str(error)) from error
    print(render(reports), end="")


if __name__ == "__main__":
    main(sys.argv[1:])
