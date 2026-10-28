#!/usr/bin/env python3
"""Export only CI test logs, never project trees, tool installations or environment."""

import argparse
import json
from pathlib import Path

LIMIT = 10 * 1024 * 1024


def collect(state, logs, output, status):
    output.mkdir(parents=True, exist_ok=True)
    entries = []
    sources = [(state / "nvim" / name, "nvim/" + name) for name in ("lsp.log", "mason.log")]
    sources += [(p, "commands/" + p.name) for p in sorted(logs.glob("*.log"))]
    evidence = state / "nvim" / "dotfiles-ci-evidence"
    sources += [
        (p, "probes/" + p.name)
        for p in sorted(evidence.glob("*"))
        if p.suffix in (".json", ".jsonl", ".log")
    ]
    for source, relative in sources:
        # Never follow a substituted log or directory into unrelated user data.
        if source.is_symlink() or any(p.is_symlink() for p in source.parents):
            continue
        if not source.is_file():
            continue
        target = output / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        with source.open("rb") as stream:
            size = source.stat().st_size
            stream.seek(max(0, size - LIMIT))
            target.write_bytes(stream.read(LIMIT))
        entries.append({"file": relative, "bytes": size, "truncated": size > LIMIT})
    (output / "collection.json").write_text(json.dumps({"exit_status": status, "files": entries}, indent=2) + "\n")
    print(f"CI failure evidence: {output} ({len(entries)} files)")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--state", type=Path, required=True)
    parser.add_argument("--logs", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--status", type=int, help="Original exit status, omitted if the process was interrupted")
    args = parser.parse_args()
    collect(args.state.resolve(), args.logs.resolve(), args.output.resolve(), args.status)
