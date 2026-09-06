#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("summarize.py")
SPEC = importlib.util.spec_from_file_location("native_first_summarize", MODULE_PATH)
assert SPEC and SPEC.loader
SUMMARIZE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SUMMARIZE)


def report(case: str) -> dict:
    return {
        "schema": 2,
        "run_id": "run-123",
        "case": case,
        "input_identity": {
            "source": {"head": "abc", "tree": "def", "status": ""},
            "neovim": {"major": 0, "minor": 11},
            "lazy_lock_sha256": "lock",
        },
        "observations": [
            {
                "language": "cpp",
                "tag": "cpp.binding.local_variable",
                "token": "local_value",
                "position": {"row": 5, "byte_column": 8},
                "raw_semantic_tokens": [
                    {
                        "provider": "clangd",
                        "client_id": 4,
                        "position_encoding": "utf-8",
                        "row": 5,
                        "start_col": 8,
                        "end_col": 19,
                        "type": "variable",
                        "modifiers": ["declaration"],
                    }
                ],
            }
        ],
        "flavour": "mocha",
        "normal": {"bg": "#000000"},
        "highlight_graph": {"count": 1, "sha256": "graph"},
    }


def reports() -> list[dict]:
    values = [report(case) for case in SUMMARIZE.EXPECTED_CASES]
    for index, value in enumerate(values):
        value["observations"][0]["raw_semantic_tokens"][0]["client_id"] = index + 1
    return values


def expect_failure(values: list[dict], message: str) -> None:
    try:
        SUMMARIZE.validate_reports(values)
    except ValueError as error:
        assert message in str(error), (message, str(error))
        return
    raise AssertionError(f"expected validation failure containing {message!r}")


SUMMARIZE.validate_reports(reports())

wrong_run = reports()
wrong_run[3]["run_id"] = "stale-run"
expect_failure(wrong_run, "run ID")

wrong_input = reports()
wrong_input[1]["input_identity"]["neovim"]["minor"] = 12
expect_failure(wrong_input, "input identity")

wrong_position = reports()
wrong_position[2]["observations"][0]["position"]["row"] = 6
expect_failure(wrong_position, "observation identity/position")

wrong_token = reports()
wrong_token[3]["observations"][0]["raw_semantic_tokens"][0]["type"] = "property"
expect_failure(wrong_token, "raw semantic token facts")

print("Native-first cross-case comparison contract passed")
