#!/usr/bin/env python3
"""Generate installable Brewfile profiles from the ownership contract."""

from __future__ import annotations

import argparse
import difflib
import json
import sys
from pathlib import Path

import tomllib

ROOT = Path(__file__).resolve().parents[1]
CONTRACT = ROOT / "brew" / "ownership.toml"
PROFILE_DIR = ROOT / "brew" / "profiles"
OWNER_ORDER = ("core", "workstation", "devcontainer", "quality")
KIND_ORDER = {"tap": 0, "brew": 1, "cask": 2}
VALID_CONDITIONS = {"all", "mac", "linux"}


def load_contract() -> dict:
    with CONTRACT.open("rb") as handle:
        contract = tomllib.load(handle)

    if contract.get("schema_version") != 1:
        raise ValueError("unsupported Brew ownership schema")
    if tuple(contract.get("profiles", {})) != OWNER_ORDER:
        raise ValueError(f"profiles must be ordered as {OWNER_ORDER}")

    seen: set[tuple[str, str]] = set()
    owner_counts = {owner: 0 for owner in OWNER_ORDER}
    for tool in contract.get("tools", []):
        key = (tool.get("kind", ""), tool.get("name", ""))
        if key[0] not in KIND_ORDER or not key[1]:
            raise ValueError(f"invalid tool declaration: {tool}")
        if key in seen:
            raise ValueError(f"duplicate tool declaration: {key[0]} {key[1]}")
        seen.add(key)

        owner = tool.get("owner")
        if owner not in OWNER_ORDER:
            raise ValueError(f"invalid owner for {key}: {owner}")
        owner_counts[owner] += 1

        profiles = tool.get("profiles", [])
        if not profiles or len(profiles) != len(set(profiles)):
            raise ValueError(f"invalid profiles for {key}: {profiles}")
        unknown = set(profiles) - set(OWNER_ORDER)
        if unknown:
            raise ValueError(f"unknown profiles for {key}: {sorted(unknown)}")

        conditions = tool.get("conditions", {})
        if set(conditions) - set(profiles):
            raise ValueError(f"conditions reference absent profiles for {key}")
        if set(conditions.values()) - VALID_CONDITIONS:
            raise ValueError(f"invalid platform condition for {key}")

    if any(count == 0 for count in owner_counts.values()):
        raise ValueError(f"every owner must own at least one tool: {owner_counts}")
    return contract


def render_profile(contract: dict, profile: str) -> str:
    metadata = contract["profiles"][profile]
    lines = [
        "# ------------------------------------------------------------------------------",
        f"# Generated Brewfile profile: {profile}",
        f"# {metadata['description']}",
        "# Source of truth: brew/ownership.toml (run: python3 brew/generate.py --write)",
        "# ------------------------------------------------------------------------------",
        "",
    ]

    selected = [tool for tool in contract["tools"] if profile in tool["profiles"]]
    for owner in OWNER_ORDER:
        owned = [tool for tool in selected if tool["owner"] == owner]
        if not owned:
            continue
        lines.append(f"# --- owner: {owner} ---")
        for tool in sorted(
            owned, key=lambda item: (KIND_ORDER[item["kind"]], item["name"])
        ):
            statement = f"{tool['kind']} {json.dumps(tool['name'], ensure_ascii=False)}"
            condition = tool.get("conditions", {}).get(profile, "all")
            if condition == "mac":
                statement += " if OS.mac?"
            elif condition == "linux":
                statement += " if OS.linux?"
            description = tool.get("description")
            if description:
                statement += f"  # {description}"
            lines.append(statement)
        lines.append("")

    return "\n".join(lines).rstrip() + "\n"


def expected_outputs(contract: dict) -> dict[Path, str]:
    outputs = {
        PROFILE_DIR / f"{profile}.Brewfile": render_profile(contract, profile)
        for profile in OWNER_ORDER
    }
    # Keep the conventional repository-root entry point as a generated,
    # byte-identical workstation profile for existing users and tooling.
    outputs[ROOT / "Brewfile"] = outputs[PROFILE_DIR / "workstation.Brewfile"]
    return outputs


def check(outputs: dict[Path, str]) -> int:
    clean = True
    for path, expected in outputs.items():
        actual = path.read_text(encoding="utf-8") if path.exists() else ""
        if actual == expected:
            continue
        clean = False
        diff = difflib.unified_diff(
            actual.splitlines(keepends=True),
            expected.splitlines(keepends=True),
            fromfile=str(path.relative_to(ROOT)),
            tofile=f"generated/{path.relative_to(ROOT)}",
        )
        sys.stderr.writelines(diff)
    return 0 if clean else 1


def main() -> int:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--write", action="store_true")
    args = parser.parse_args()

    try:
        outputs = expected_outputs(load_contract())
    except (OSError, ValueError, tomllib.TOMLDecodeError) as error:
        print(f"Brew profile generation failed: {error}", file=sys.stderr)
        return 1

    if args.check:
        return check(outputs)

    for path, content in outputs.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        print(f"wrote {path.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
