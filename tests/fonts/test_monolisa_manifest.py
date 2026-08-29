#!/usr/bin/env python3
"""Validate the public MonoLisa feature manifest and an optional licensed build."""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import tomllib
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
MANIFEST_PATH = REPO_ROOT / "fonts/monolisa-opentype.toml"
GHOSTTY_CONFIG = REPO_ROOT / "home/dot_config/ghostty/config"
EXPECTED_FEATURES = {
    "calt",
    "liga",
    "dlig",
    "zero",
    *(f"cv{index:02d}" for index in range(1, 13)),
    *(f"ss{index:02d}" for index in range(1, 16)),
}


def load_manifest() -> dict:
    with MANIFEST_PATH.open("rb") as stream:
        manifest = tomllib.load(stream)

    policy = manifest["policy"]
    if policy["version"] != 1:
        raise AssertionError("unsupported MonoLisa manifest version")
    if policy["delivery"] != "customizer-font-build":
        raise AssertionError("MonoLisa features must be delivered by the licensed font build")

    enabled = policy["enabled"]
    disabled = policy["disabled"]
    if len(enabled) != len(set(enabled)) or len(disabled) != len(set(disabled)):
        raise AssertionError("MonoLisa feature manifest contains duplicates")
    if set(enabled) & set(disabled):
        raise AssertionError("MonoLisa features cannot be both enabled and disabled")
    if set(enabled) | set(disabled) != EXPECTED_FEATURES:
        raise AssertionError("MonoLisa feature manifest does not cover all 31 switches")

    ghostty = GHOSTTY_CONFIG.read_text(encoding="utf-8")
    if any(line.lstrip().startswith("font-feature") for line in ghostty.splitlines()):
        raise AssertionError("Ghostty must not apply MonoLisa features to fallback fonts")
    return manifest


def probe_font(font: Path, probe: dict) -> None:
    hb_shape = shutil.which("hb-shape")
    if hb_shape is None:
        raise AssertionError("hb-shape is required to verify a licensed font build")
    result = subprocess.run(
        [hb_shape, str(font), f"--text={probe['text']}"],
        check=True,
        capture_output=True,
        text=True,
    )
    output = result.stdout
    missing = [glyph for glyph in probe["required_glyphs"] if glyph not in output]
    present = [glyph for glyph in probe["forbidden_glyphs"] if glyph in output]
    if missing or present:
        details = []
        if missing:
            details.append("missing " + ", ".join(missing))
        if present:
            details.append("unexpected " + ", ".join(present))
        raise AssertionError("font build does not match manifest: " + "; ".join(details))
    print(f"MonoLisa font build      PASS ({font.name})")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--upright", type=Path)
    parser.add_argument("--italic", type=Path)
    arguments = parser.parse_args()

    try:
        manifest = load_manifest()
        print("MonoLisa feature policy  31/31")
        if arguments.upright:
            probe_font(arguments.upright, manifest["probe"]["upright"])
        if arguments.italic:
            probe_font(arguments.italic, manifest["probe"]["italic"])
    except (AssertionError, KeyError, OSError, subprocess.CalledProcessError) as error:
        print(f"MonoLisa manifest error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
