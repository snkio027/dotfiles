#!/usr/bin/env python3
"""Classify pull-request paths into the existing CI validation lanes."""

from __future__ import annotations

import subprocess
import sys
from collections.abc import Iterable


LANES = (
    "macos",
    "devcontainer_build",
    "brew_core",
    "devcontainer_lifecycle",
    "neovim_locked",
)


def _all_lanes() -> dict[str, bool]:
    return dict.fromkeys(LANES, True)


def classify_paths(paths: Iterable[str]) -> dict[str, bool]:
    """Return the extra CI lanes required for a set of repository paths.

    Validate always runs. Unknown paths deliberately select every lane so a
    new repository area cannot silently lose coverage.
    """

    result = dict.fromkeys(LANES, False)
    saw_path = False

    for path in paths:
        if not path:
            continue
        saw_path = True

        # Workflow or classifier changes exercise the complete matrix. This
        # also makes classification policy changes self-validating.
        if path.startswith(".github/") or path in {
            "scripts/ci/classify_pr_paths.py",
            "tests/ci/test_pr_path_classifier.py",
        }:
            return _all_lanes()

        # Documentation and inert repository metadata only need Validate.
        if (
            path == "README.md"
            or path.startswith("docs/")
            or ("/" not in path and path.endswith(".md"))
            or path in {".envrc.example", ".gitignore"}
        ):
            continue

        if path.startswith(("home/dot_config/nvim/", "tests/nvim/")) or path == (
            "home/dot_config/neocmakelsp/config.toml"
        ):
            result["neovim_locked"] = True
            result["devcontainer_lifecycle"] = True
            continue

        if path.startswith(("icons/", "tests/icons/")):
            result["macos"] = True
            result["neovim_locked"] = True
            result["devcontainer_lifecycle"] = True
            continue

        if path.startswith(("fonts/", "tests/fonts/")):
            result["macos"] = True
            continue

        if path == "Brewfile" or path.startswith(("brew/", "tests/brew/")):
            result["macos"] = True
            result["devcontainer_build"] = True
            result["brew_core"] = True
            result["devcontainer_lifecycle"] = True
            result["neovim_locked"] = True
            continue

        if path.startswith((".devcontainer/", "tests/devcontainer/")):
            result["devcontainer_build"] = True
            result["devcontainer_lifecycle"] = True
            continue

        if path.startswith(("scripts/supply-chain/", "supply-chain/", "tests/supply-chain/")):
            result["devcontainer_build"] = True
            result["devcontainer_lifecycle"] = True
            continue

        # Chezmoi-managed host configuration is exercised on both macOS and
        # the disposable Linux lifecycle lane. Neovim is handled above so its
        # focused PR matrix remains Validate + Locked + Lifecycle.
        if path.startswith("home/") or path == ".chezmoiroot":
            result["macos"] = True
            result["devcontainer_lifecycle"] = True
            continue

        # These behavior tests execute inside Validate and do not alter the
        # corresponding runtime image or host configuration.
        if path.startswith(("tests/chezmoi/", "tests/git/", "tests/zsh/")):
            continue

        return _all_lanes()

    return result if saw_path else _all_lanes()


def changed_paths(base_sha: str, head_sha: str) -> list[str]:
    command = ["git", "diff", "--name-only", "-z", "--no-renames", f"{base_sha}...{head_sha}"]
    try:
        completed = subprocess.run(
            command,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except subprocess.CalledProcessError as error:
        detail = error.stderr.decode("utf-8", "replace").strip()
        message = f"unable to classify {base_sha}...{head_sha}"
        if detail:
            message = f"{message}: {detail}"
        raise RuntimeError(message) from error

    paths = []
    for raw_path in completed.stdout.split(b"\0"):
        if not raw_path:
            continue
        try:
            path = raw_path.decode("utf-8")
        except UnicodeDecodeError as error:
            raise RuntimeError(
                "git diff returned a non-UTF-8 path; refusing to narrow validation"
            ) from error
        if path.startswith("/") or any(part in {"", ".", ".."} for part in path.split("/")):
            raise RuntimeError(
                "git diff returned a non-normalized path; refusing to narrow validation"
            )
        paths.append(path)
    return paths


def emit_outputs(result: dict[str, bool]) -> None:
    for name in LANES:
        print(f"{name}={int(result[name])}")


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(f"usage: {argv[0]} <base-sha> <head-sha>", file=sys.stderr)
        return 2

    try:
        paths = changed_paths(argv[1], argv[2])
    except RuntimeError as error:
        print(f"PR path classification failed: {error}", file=sys.stderr)
        return 1

    emit_outputs(classify_paths(paths))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
