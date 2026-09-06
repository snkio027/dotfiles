#!/usr/bin/env python3

import json
import sys
from pathlib import Path


def load(path: str) -> dict:
    with Path(path).open(encoding="utf-8") as handle:
        return json.load(handle)


reports = [load(path) for path in sys.argv[1:]]
if len(reports) != 4:
    raise SystemExit("expected exactly four E1 reports")

case_names = [report["case"] for report in reports]
expected = ["m5", "native-mocha", "native-macchiato", "native-frappe"]
if case_names != expected:
    raise SystemExit(f"case order drift: expected {expected}, observed {case_names}")

print("# Catppuccin native-first E1 generated summary")
print()
print("| Case | Flavour | Normal background | Graph groups | Graph SHA-256 | Observations |")
print("| --- | --- | --- | ---: | --- | ---: |")
for report in reports:
    graph = report["highlight_graph"]
    print(
        f'| `{report["case"]}` | `{report["flavour"]}` | '
        f'`{report["normal"]["bg"]}` | {graph["count"]} | '
        f'`{graph["sha256"]}` | {len(report["observations"])} |'
    )

print()
print("All four rows are harness observations, not a visual-policy verdict.")
