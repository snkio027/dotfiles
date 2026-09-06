#!/usr/bin/env python3

"""Create and validate a writable, case-private Neovim data snapshot."""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path


COMPONENTS = ("lazy", "mason", "site")


def is_relative_to(path: Path, parent: Path) -> bool:
    try:
        path.relative_to(parent)
    except ValueError:
        return False
    return True


def copy_component(source: Path, destination: Path) -> None:
    if sys.platform == "darwin":
        command = ["cp", "-cR", str(source), str(destination)]
    else:
        command = ["cp", "-a", "--reflink=auto", str(source), str(destination)]
    result = subprocess.run(command, capture_output=True, text=True, check=False)
    if result.returncode == 0:
        return
    if destination.exists() or destination.is_symlink():
        shutil.rmtree(destination)
    shutil.copytree(source, destination, symlinks=True)


def redirect_seed_links(seed: Path, destination: Path) -> None:
    for root, directories, files in os.walk(destination, followlinks=False):
        for name in (*directories, *files):
            link = Path(root, name)
            if not link.is_symlink():
                continue
            resolved = link.resolve(strict=False)
            if not is_relative_to(resolved, seed):
                continue
            replacement = destination / resolved.relative_to(seed)
            if not replacement.exists():
                raise RuntimeError(
                    f"seed-relative symlink has no private target: {link} -> {resolved}"
                )
            link.unlink()
            link.symlink_to(os.path.relpath(replacement, link.parent))


def validate_snapshot(seed: Path, destination: Path) -> None:
    destination_real = destination.resolve(strict=True)
    seed_real = seed.resolve(strict=True)
    for component in COMPONENTS:
        copied = destination / component
        if copied.is_symlink() or not copied.is_dir():
            raise RuntimeError(f"snapshot component is not a private directory: {copied}")
        if not is_relative_to(copied.resolve(strict=True), destination_real):
            raise RuntimeError(f"snapshot component escaped run data root: {copied}")

    for root, directories, files in os.walk(destination, followlinks=False):
        for name in (*directories, *files):
            link = Path(root, name)
            if link.is_symlink() and is_relative_to(link.resolve(strict=False), seed_real):
                raise RuntimeError(f"snapshot symlink still resolves into seed: {link}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("seed", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()

    seed = args.seed.resolve(strict=True)
    destination = args.destination.resolve(strict=True)
    if any(destination.iterdir()):
        raise RuntimeError(f"snapshot destination is not empty: {destination}")

    for component in COMPONENTS:
        source = seed / component
        if not source.exists():
            raise RuntimeError(f"validated Neovim data seed is missing: {source}")
        copy_component(source, destination / component)

    redirect_seed_links(seed, destination)
    validate_snapshot(seed, destination)


if __name__ == "__main__":
    main()
