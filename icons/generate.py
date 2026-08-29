#!/usr/bin/env python3
"""Validate the icon contract and generate all consumer artifacts."""

from __future__ import annotations

import argparse
import json
import sys
import tomllib
import unicodedata
from dataclasses import dataclass
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[1]
CONTRACT_PATH = REPO_ROOT / "icons" / "contract.toml"
OUTPUTS = {
    REPO_ROOT / "home/dot_config/nvim/lua/config/icon_contract.lua": "nvim",
    REPO_ROOT / "home/dot_config/eza/theme.yml": "eza",
    REPO_ROOT / "tests/icons/generated_cases.json": "cases",
}


class ContractError(ValueError):
    pass


@dataclass(frozen=True)
class Icon:
    glyph: str
    color_role: str
    nvim_highlight: str
    eza_color: str


def load_contract(path: Path = CONTRACT_PATH) -> dict[str, Any]:
    with path.open("rb") as stream:
        contract = tomllib.load(stream)
    validate_contract(contract)
    return contract


def validate_glyph(label: str, glyph: object) -> None:
    if not isinstance(glyph, str) or len(glyph) != 1:
        raise ContractError(f"{label}: glyph must be exactly one Unicode codepoint")

    codepoint = ord(glyph)
    category = unicodedata.category(glyph)
    if category in {"Cc", "Cf", "Cs", "Cn"} or codepoint in {0xFFFE, 0xFFFF}:
        raise ContractError(f"{label}: illegal glyph U+{codepoint:04X}")
    if unicodedata.combining(glyph) or unicodedata.east_asian_width(glyph) in {"W", "F"}:
        raise ContractError(f"{label}: glyph U+{codepoint:04X} is not single-cell safe")


def validate_entry(
    category: str,
    entry: dict[str, Any],
    colors: dict[str, Any],
    names: set[str],
) -> None:
    name = entry.get("name")
    if not isinstance(name, str) or not name or "/" in name:
        raise ContractError(f"{category}: name must be a non-empty basename")
    if category == "extensions" and (name.startswith(".") or name != name.lower()):
        raise ContractError(f"extensions.{name}: use a lowercase extension without a dot")
    if name in names:
        raise ContractError(f"{category}: duplicate name {name!r}")
    names.add(name)

    validate_glyph(f"{category}.{name}", entry.get("glyph"))
    role = entry.get("color_role")
    if role not in colors:
        raise ContractError(f"{category}.{name}: unknown color role {role!r}")


def resolve(contract: dict[str, Any], filename: str) -> tuple[str, str, dict[str, Any]]:
    files = {entry["name"]: entry for entry in contract.get("files", [])}
    extensions = {entry["name"]: entry for entry in contract.get("extensions", [])}

    if filename in files:
        return "file", filename, files[filename]
    extension = filename.rsplit(".", 1)[-1].lower() if "." in filename else ""
    if extension in extensions:
        return "extension", extension, extensions[extension]
    return "default", "file", contract["defaults"]["file"]


def validate_contract(contract: dict[str, Any]) -> None:
    metadata = contract.get("contract", {})
    if metadata.get("version") != 1:
        raise ContractError("contract.version must be 1")
    if metadata.get("priority") != ["file", "extension", "default"]:
        raise ContractError("contract.priority must be file > extension > default")

    colors = contract.get("colors", {})
    if not colors:
        raise ContractError("at least one color role is required")
    for role, value in colors.items():
        if not isinstance(value.get("nvim"), str) or not value["nvim"].startswith("MiniIcons"):
            raise ContractError(f"colors.{role}.nvim must name a MiniIcons highlight")
        eza_color = value.get("eza")
        if (
            not isinstance(eza_color, str)
            or len(eza_color) != 7
            or not eza_color.startswith("#")
            or any(character not in "0123456789abcdefABCDEF" for character in eza_color[1:])
        ):
            raise ContractError(f"colors.{role}.eza must be a #RRGGBB color")

    defaults = contract.get("defaults", {})
    for category in ("file", "directory"):
        entry = defaults.get(category, {})
        validate_glyph(f"defaults.{category}", entry.get("glyph"))
        if entry.get("color_role") not in colors:
            raise ContractError(
                f"defaults.{category}: unknown color role {entry.get('color_role')!r}"
            )

    for category in ("files", "extensions"):
        names: set[str] = set()
        for entry in contract.get(category, []):
            validate_entry(category, entry, colors, names)

    coverage = contract.get("coverage", {})
    cases = coverage.get("cases", [])
    if len(cases) != coverage.get("expected"):
        raise ContractError(
            f"coverage contains {len(cases)} cases, expected {coverage.get('expected')}"
        )
    observed_count = sum(case.get("observed") is True for case in cases)
    if observed_count != coverage.get("real_project_expected"):
        raise ContractError(
            f"coverage records {observed_count} observed cases, expected "
            f"{coverage.get('real_project_expected')}"
        )

    patterns: set[str] = set()
    fixtures: set[str] = set()
    for case in cases:
        pattern = case.get("pattern")
        fixture = case.get("fixture")
        if not isinstance(pattern, str) or not pattern:
            raise ContractError("coverage case is missing a pattern")
        if pattern in patterns:
            raise ContractError(f"coverage: duplicate pattern {pattern!r}")
        patterns.add(pattern)
        if not isinstance(fixture, str) or not fixture or "/" in fixture:
            raise ContractError(f"coverage.{pattern}: fixture must be a basename")
        if fixture in fixtures:
            raise ContractError(f"coverage: duplicate fixture {fixture!r}")
        fixtures.add(fixture)
        if case.get("observed") not in {True, False}:
            raise ContractError(f"coverage.{pattern}: observed must be true or false")
        if pattern.startswith("*.") and not fixture.endswith(pattern[1:]):
            raise ContractError(f"coverage.{pattern}: fixture {fixture!r} does not match")
        if not pattern.startswith("*.") and fixture != pattern:
            raise ContractError(f"coverage.{pattern}: exact fixture must match the pattern")
        category, _, _ = resolve(contract, fixture)
        if category == "default":
            raise ContractError(f"coverage.{pattern}: no explicit file or extension mapping")


def icon_for(contract: dict[str, Any], entry: dict[str, Any]) -> Icon:
    role = entry["color_role"]
    colors = contract["colors"][role]
    return Icon(entry["glyph"], role, colors["nvim"], colors["eza"])


def lua_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def render_nvim(contract: dict[str, Any]) -> str:
    lines = [
        "-- Generated from icons/contract.toml by icons/generate.py. Do not edit.",
        "return {",
        "  default = {",
    ]
    for category in ("directory", "file"):
        icon = icon_for(contract, contract["defaults"][category])
        lines.append(
            f"    {category} = {{ glyph = {lua_string(icon.glyph)}, "
            f"hl = {lua_string(icon.nvim_highlight)} }},"
        )
    lines.extend(["  },", "  extension = {"])
    for entry in sorted(contract.get("extensions", []), key=lambda item: item["name"]):
        icon = icon_for(contract, entry)
        lines.append(
            f"    [{lua_string(entry['name'])}] = {{ glyph = {lua_string(icon.glyph)}, "
            f"hl = {lua_string(icon.nvim_highlight)} }},"
        )
    lines.extend(["  },", "  file = {"])
    for entry in sorted(contract.get("files", []), key=lambda item: item["name"]):
        icon = icon_for(contract, entry)
        lines.append(
            f"    [{lua_string(entry['name'])}] = {{ glyph = {lua_string(icon.glyph)}, "
            f"hl = {lua_string(icon.nvim_highlight)} }},"
        )
    lines.extend(["  },", "}", ""])
    return "\n".join(lines)


def yaml_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def render_eza(contract: dict[str, Any]) -> str:
    lines = [
        "# Generated from icons/contract.toml by icons/generate.py. Do not edit.",
        "filenames:",
    ]
    for entry in sorted(contract.get("files", []), key=lambda item: item["name"]):
        icon = icon_for(contract, entry)
        lines.extend(
            [
                f"  {yaml_string(entry['name'])}:",
                "    icon:",
                f"      glyph: {yaml_string(icon.glyph)}",
                "      style:",
                f"        foreground: {yaml_string(icon.eza_color)}",
            ]
        )
    lines.append("extensions:")
    for entry in sorted(contract.get("extensions", []), key=lambda item: item["name"]):
        icon = icon_for(contract, entry)
        lines.extend(
            [
                f"  {yaml_string(entry['name'])}:",
                "    icon:",
                f"      glyph: {yaml_string(icon.glyph)}",
                "      style:",
                f"        foreground: {yaml_string(icon.eza_color)}",
            ]
        )
    lines.append("")
    return "\n".join(lines)


def generated_cases(contract: dict[str, Any]) -> list[dict[str, Any]]:
    cases = []
    for case in contract["coverage"]["cases"]:
        category, key, entry = resolve(contract, case["fixture"])
        icon = icon_for(contract, entry)
        cases.append(
            {
                "pattern": case["pattern"],
                "fixture": case["fixture"],
                "observed": case["observed"],
                "category": category,
                "key": key,
                "glyph": icon.glyph,
                "color_role": icon.color_role,
                "nvim_highlight": icon.nvim_highlight,
                "eza_color": icon.eza_color,
            }
        )
    return cases


def render_cases(contract: dict[str, Any]) -> str:
    payload = {
        "contract_version": contract["contract"]["version"],
        "source_eza_version": contract["contract"]["source_eza_version"],
        "priority": contract["contract"]["priority"],
        "expected": contract["coverage"]["expected"],
        "real_project_expected": contract["coverage"]["real_project_expected"],
        "cases": generated_cases(contract),
    }
    return json.dumps(payload, ensure_ascii=False, indent=2) + "\n"


def render_outputs(contract: dict[str, Any]) -> dict[Path, str]:
    renderers = {"nvim": render_nvim, "eza": render_eza, "cases": render_cases}
    return {path: renderers[kind](contract) for path, kind in OUTPUTS.items()}


def write_outputs(outputs: dict[Path, str]) -> None:
    for path, content in outputs.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        print(f"generated {path.relative_to(REPO_ROOT)}")


def check_outputs(outputs: dict[Path, str]) -> None:
    stale = []
    for path, content in outputs.items():
        if not path.exists() or path.read_text(encoding="utf-8") != content:
            stale.append(str(path.relative_to(REPO_ROOT)))
    if stale:
        raise ContractError("generated artifacts are stale: " + ", ".join(stale))


def print_summary(contract: dict[str, Any]) -> None:
    expected = contract["coverage"]["expected"]
    observed = contract["coverage"]["real_project_expected"]
    print(f"Contract verification   {expected}/{expected}")
    print(f"Real-project observation {observed}/{expected}")


def main() -> int:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--write", action="store_true", help="generate consumer artifacts")
    mode.add_argument("--check", action="store_true", help="validate committed artifacts")
    arguments = parser.parse_args()

    try:
        contract = load_contract()
        outputs = render_outputs(contract)
        if arguments.write:
            write_outputs(outputs)
        else:
            check_outputs(outputs)
        print_summary(contract)
    except (ContractError, OSError, tomllib.TOMLDecodeError) as error:
        print(f"icon contract error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
