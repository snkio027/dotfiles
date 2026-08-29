#!/usr/bin/env python3
"""Consumer, coverage, drift, and font checks for the shared icon contract."""

from __future__ import annotations

import argparse
import copy
import importlib.util
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from types import ModuleType
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[2]
ANSI_ESCAPE = re.compile(r"\x1b\[[0-9;]*m")
ALLOWED_ICON_FACES = ("Maple Mono NF CN", "Symbols Nerd Font")


def load_generator() -> ModuleType:
    path = REPO_ROOT / "icons/generate.py"
    spec = importlib.util.spec_from_file_location("icon_contract_generator", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def run_eza(
    eza: str,
    config_dir: Path,
    path: Path,
    color: bool,
    list_dirs: bool = False,
) -> str:
    environment = os.environ.copy()
    environment["EZA_CONFIG_DIR"] = str(config_dir)
    arguments = [
        eza,
        "--icons=always",
        f"--color={'always' if color else 'never'}",
        "--oneline",
    ]
    if list_dirs:
        arguments.append("--list-dirs")
    arguments.append(str(path))
    result = subprocess.run(
        arguments,
        check=True,
        capture_output=True,
        env=environment,
        text=True,
    )
    return result.stdout.rstrip("\n")


def visible_glyph(output: str) -> str:
    visible = ANSI_ESCAPE.sub("", output)
    if not visible:
        raise AssertionError("eza returned no visible output")
    return visible[0]


def truecolor_sequence(hex_color: str) -> str:
    red, green, blue = (int(hex_color[index : index + 2], 16) for index in (1, 3, 5))
    return f"\x1b[38;2;{red};{green};{blue}m"


def check_priority(generator: ModuleType, contract: dict[str, Any]) -> None:
    for filename, exact_glyph, extension_glyph in (
        ("pyproject.toml", "", ""),
        ("Cargo.toml", "", ""),
        ("package.json", "", ""),
        ("docker-compose.yml", "", ""),
    ):
        category, _, entry = generator.resolve(contract, filename)
        assert category == "file", f"exact filename did not win for {filename}"
        assert entry["glyph"] == exact_glyph
        assert entry["glyph"] != extension_glyph


def check_schema_rejections(generator: ModuleType, contract: dict[str, Any]) -> None:
    def rejected(mutated: dict[str, Any], label: str) -> None:
        try:
            generator.validate_contract(mutated)
        except generator.ContractError:
            return
        raise AssertionError(f"schema accepted {label}")

    duplicate_file = copy.deepcopy(contract)
    duplicate_file["files"].append(copy.deepcopy(duplicate_file["files"][0]))
    rejected(duplicate_file, "duplicate filename")

    duplicate_extension = copy.deepcopy(contract)
    duplicate_extension["extensions"].append(
        copy.deepcopy(duplicate_extension["extensions"][0])
    )
    rejected(duplicate_extension, "duplicate extension")

    illegal_codepoint = copy.deepcopy(contract)
    illegal_codepoint["extensions"][0]["glyph"] = "\n"
    rejected(illegal_codepoint, "illegal codepoint")

    wide_glyph = copy.deepcopy(contract)
    wide_glyph["extensions"][0]["glyph"] = "中"
    rejected(wide_glyph, "wide glyph")

    missing_role = copy.deepcopy(contract)
    missing_role["files"][0]["color_role"] = "missing"
    rejected(missing_role, "missing color role")

    invalid_color = copy.deepcopy(contract)
    invalid_color["colors"]["grey"]["eza"] = "#not-rgb"
    rejected(invalid_color, "invalid shared RGB")

    missing_runtime_case = copy.deepcopy(contract)
    missing_runtime_case["runtime"]["eza"].pop("empty_directory")
    rejected(missing_runtime_case, "incomplete consumer runtime observations")

    invalid_runtime_highlight = copy.deepcopy(contract)
    invalid_runtime_highlight["runtime"]["nvim"]["build_directory"]["highlight"] = (
        "UnknownHighlight"
    )
    rejected(invalid_runtime_highlight, "invalid runtime highlight")


def check_eza(
    contract: dict[str, Any],
    cases: list[dict[str, Any]],
) -> None:
    eza = shutil.which("eza")
    if eza is None:
        raise AssertionError("eza is required for icon contract verification")

    config_dir = REPO_ROOT / "home/dot_config/eza"
    with tempfile.TemporaryDirectory(prefix="icon-contract-") as directory:
        fixture_dir = Path(directory)
        for case in cases:
            path = fixture_dir / case["fixture"]
            path.touch()
            plain_output = run_eza(eza, config_dir, path, color=False)
            actual_glyph = visible_glyph(plain_output)
            assert actual_glyph == case["glyph"], (
                f"eza glyph mismatch for {case['pattern']}: "
                f"expected {case['glyph']} U+{ord(case['glyph']):04X}, "
                f"got {actual_glyph} U+{ord(actual_glyph):04X}"
            )

            color_output = run_eza(eza, config_dir, path, color=True)
            expected_color = truecolor_sequence(case["eza_color"])
            glyph_offset = color_output.find(case["glyph"])
            assert glyph_offset >= 0
            assert expected_color in color_output[:glyph_offset], (
                f"eza color-role mismatch for {case['pattern']} "
                f"({case['color_role']} / {case['eza_color']})"
            )

    expected = len(contract["files"]) + len(contract["extensions"])
    print(f"Explicit consumer mappings  {len(cases)}/{expected}")


def check_audit(contract: dict[str, Any], cases: list[dict[str, Any]]) -> None:
    expected = contract["coverage"]["expected"]
    observed = contract["coverage"]["real_project_expected"]
    assert len(cases) == expected
    assert sum(case["observed"] is True for case in cases) == observed
    print(f"Audit scope                 {len(cases)}/{expected}")
    print(f"Real-project observations   {observed}/{expected}")


def check_eza_runtime(observations: list[dict[str, Any]]) -> None:
    eza = shutil.which("eza")
    if eza is None:
        raise AssertionError("eza is required for runtime observation verification")

    with tempfile.TemporaryDirectory(prefix="icon-runtime-") as directory:
        root = Path(directory)
        config_dir = root / "empty-config"
        fixture_dir = root / "fixtures"
        config_dir.mkdir()
        fixture_dir.mkdir()
        differences = []
        for observation in observations:
            path = fixture_dir / observation["fixture"]
            if observation["kind"] == "directory":
                path.mkdir()
                if observation["populate"]:
                    (path / "child").touch()
            else:
                path.touch()
            output = run_eza(
                eza,
                config_dir,
                path,
                color=False,
                list_dirs=observation["kind"] == "directory",
            )
            actual = visible_glyph(output)
            expected = observation["glyph"]
            if actual != expected:
                differences.append(
                    f"{observation['label']}: baseline {expected} "
                    f"U+{ord(expected):04X}, upstream {actual} U+{ord(actual):04X}"
                )
    verified = len(observations) - len(differences)
    print(f"eza runtime observations    {verified}/{len(observations)} (informational)")
    for difference in differences:
        print(f"  {difference}")


def ghostty_binary() -> str:
    discovered = shutil.which("ghostty")
    if discovered:
        return discovered
    application_binary = Path("/Applications/Ghostty.app/Contents/MacOS/ghostty")
    if application_binary.is_file():
        return str(application_binary)
    raise AssertionError("Ghostty is required for font coverage verification")


def check_fonts(glyphs: list[str]) -> None:
    ghostty = ghostty_binary()
    glyph_string = "".join(glyphs)
    result = subprocess.run(
        [
            ghostty,
            f"--config-file={REPO_ROOT / 'home/dot_config/ghostty/config'}",
            "+show-face",
            f"--string={glyph_string}",
        ],
        check=False,
        capture_output=True,
        text=True,
    )
    output = result.stdout + result.stderr
    found = {
        int(codepoint, 16): face
        for codepoint, face in re.findall(
            r"U\+([0-9A-F]+).*found in face [“\"]([^”\"]+)[”\"]", output
        )
    }
    failures = []
    for glyph in glyph_string:
        face = found.get(ord(glyph))
        if face is None or not face.startswith(ALLOWED_ICON_FACES):
            failures.append(f"U+{ord(glyph):04X} -> {face or 'missing'}")
    if failures:
        raise AssertionError("font coverage failed: " + ", ".join(failures))
    print(f"Unique glyph font coverage  {len(glyphs)}/{len(glyphs)}")


def report_eza_drift(cases: list[dict[str, Any]]) -> None:
    eza = shutil.which("eza")
    if eza is None:
        print("Upstream eza drift     SKIP (eza unavailable)")
        return
    with tempfile.TemporaryDirectory(prefix="icon-contract-drift-") as directory:
        root = Path(directory)
        config_dir = root / "empty-eza-config"
        fixture_dir = root / "fixtures"
        config_dir.mkdir()
        fixture_dir.mkdir()
        drift = []
        for case in cases:
            path = fixture_dir / case["fixture"]
            path.touch()
            upstream = visible_glyph(run_eza(eza, config_dir, path, color=False))
            if upstream != case["glyph"]:
                drift.append(
                    f"{case['pattern']}: contract {case['glyph']} "
                    f"U+{ord(case['glyph']):04X}, upstream {upstream} U+{ord(upstream):04X}"
                )
    print(f"Upstream eza drift     {len(drift)}/{len(cases)}")
    for item in drift:
        print(f"  {item}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--font-check", action="store_true")
    parser.add_argument("--drift", action="store_true")
    arguments = parser.parse_args()

    generator = load_generator()
    contract = generator.load_contract()
    generator.check_outputs(generator.render_outputs(contract))
    audit_cases = generator.generated_cases(contract)
    mappings = generator.explicit_cases(contract)
    runtime = generator.runtime_observations(contract)
    glyphs = generator.contract_glyphs(contract)
    check_priority(generator, contract)
    check_schema_rejections(generator, contract)
    check_audit(contract, audit_cases)
    check_eza(contract, mappings)
    check_eza_runtime(runtime["eza"])
    if arguments.font_check:
        check_fonts(glyphs)
    if arguments.drift:
        report_eza_drift(mappings)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
