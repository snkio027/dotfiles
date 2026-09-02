#!/usr/bin/env python3
"""Behavior contract for pull-request CI path classification."""

from __future__ import annotations

import importlib.util
import subprocess
import sys
import tempfile
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
CLASSIFIER_PATH = REPO_ROOT / "scripts/ci/classify_pr_paths.py"
WORKFLOW_PATH = REPO_ROOT / ".github/workflows/ci.yml"
SPEC = importlib.util.spec_from_file_location("classify_pr_paths", CLASSIFIER_PATH)
assert SPEC and SPEC.loader
CLASSIFIER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CLASSIFIER)


def expected(**enabled: bool) -> dict[str, bool]:
    result = dict.fromkeys(CLASSIFIER.LANES, False)
    result.update(enabled)
    return result


def assert_case(name: str, paths: list[str], wanted: dict[str, bool]) -> None:
    actual = CLASSIFIER.classify_paths(paths)
    assert actual == wanted, f"{name}: expected {wanted}, got {actual}"


def expensive_lane_runs(event: str, classifier_result: str, output: str | None) -> bool:
    """Model the workflow condition, including case-insensitive string comparison."""

    formatted_output = f"lane:{'' if output is None else output}"
    return (
        event.casefold() != "pull_request"
        or classifier_result.casefold() != "success"
        or formatted_output.casefold() != "lane:0"
    )


def git(*args: str, cwd: Path) -> str:
    return subprocess.run(
        ["git", *args], cwd=cwd, check=True, text=True, stdout=subprocess.PIPE
    ).stdout.strip()


def run_classifier(base: str, head: str, repository: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(CLASSIFIER_PATH), base, head],
        cwd=repository,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def test_git_diff_integration() -> None:
    with tempfile.TemporaryDirectory() as directory:
        repository = Path(directory)
        git("init", "--initial-branch=main", cwd=repository)
        git("config", "user.name", "CI Classifier", cwd=repository)
        git("config", "user.email", "classifier@example.invalid", cwd=repository)

        (repository / "README.md").write_text("base\n", encoding="utf-8")
        git("add", "README.md", cwd=repository)
        git("commit", "-m", "base", cwd=repository)
        base = git("rev-parse", "HEAD", cwd=repository)

        (repository / "README.md").write_text("docs only\n", encoding="utf-8")
        (repository / "docs").mkdir()
        (repository / "docs" / "path with space.md").write_text("fixture\n", encoding="utf-8")
        git("add", "README.md", "docs/path with space.md", cwd=repository)
        git("commit", "-m", "docs", cwd=repository)
        head = git("rev-parse", "HEAD", cwd=repository)

        classified = run_classifier(base, head, repository)
        assert classified.returncode == 0
        assert classified.stdout.splitlines() == [f"{lane}=0" for lane in CLASSIFIER.LANES]

        failed = run_classifier("missing-base", head, repository)
        assert failed.returncode == 1
        assert not failed.stdout
        assert "PR path classification failed" in failed.stderr

        blob = subprocess.run(
            ["git", "hash-object", "-w", "--stdin"],
            cwd=repository,
            check=True,
            input=b"non-UTF-8 path fixture\n",
            stdout=subprocess.PIPE,
        ).stdout.strip()
        subprocess.run(
            ["git", "update-index", "-z", "--index-info"],
            cwd=repository,
            check=True,
            input=b"100644 " + blob + b"\tdocs/bad-\xff.md\0",
        )
        subprocess.run(
            ["git", "commit", "-m", "non-UTF-8 path"],
            cwd=repository,
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
        )
        non_utf8_head = git("rev-parse", "HEAD", cwd=repository)

        rejected = run_classifier(head, non_utf8_head, repository)
        assert rejected.returncode == 1
        assert not rejected.stdout
        assert "non-UTF-8 path" in rejected.stderr


def main() -> None:
    all_lanes = dict.fromkeys(CLASSIFIER.LANES, True)

    assert_case("README only", ["README.md"], expected())
    assert_case("docs only", ["docs/recovery.md"], expected())
    assert_case(
        "docs plus Neovim",
        ["README.md", "home/dot_config/nvim/lua/config/lazy.lua"],
        expected(neovim_locked=True, devcontainer_lifecycle=True),
    )
    assert_case(
        "Neovim",
        ["home/dot_config/nvim/lua/config/lazy.lua"],
        expected(neovim_locked=True, devcontainer_lifecycle=True),
    )
    assert_case(
        "Dev Container",
        [".devcontainer/post-create.sh"],
        expected(devcontainer_build=True, devcontainer_lifecycle=True),
    )
    assert_case(
        "Brew ownership",
        ["brew/ownership.toml"],
        expected(
            macos=True,
            devcontainer_build=True,
            brew_core=True,
            devcontainer_lifecycle=True,
            neovim_locked=True,
        ),
    )
    assert_case("fonts", ["fonts/monolisa-opentype.toml"], expected(macos=True))
    assert_case(
        "icons",
        ["icons/contract.toml"],
        expected(macos=True, neovim_locked=True, devcontainer_lifecycle=True),
    )
    assert_case(
        "managed shell",
        ["home/dot_config/zsh/aliases.zsh"],
        expected(macos=True, devcontainer_lifecycle=True),
    )
    assert_case("workflow", [".github/workflows/ci.yml"], all_lanes)
    assert_case("classifier", ["scripts/ci/classify_pr_paths.py"], all_lanes)
    assert_case("unknown", ["new-area/contract.txt"], all_lanes)
    assert_case("empty", [], all_lanes)

    test_git_diff_integration()

    workflow = WORKFLOW_PATH.read_text(encoding="utf-8")
    assert workflow.count("always() && !cancelled()") == 6
    assert workflow.count("needs.classify_pr.result != 'success'") == 5
    for lane in CLASSIFIER.LANES:
        expression = (
            f"format('lane:{{0}}', needs.classify_pr.outputs.{lane}) != 'lane:0'"
        )
        assert workflow.count(expression) == 1
    assert "!= 'false'" not in workflow
    assert "github.event_name != 'pull_request'" in workflow
    assert "github.event_name == 'push'" in workflow

    assert not expensive_lane_runs("pull_request", "success", "0")
    for untrusted in ("1", "false", "False", "FALSE", "", "garbage", None):
        assert expensive_lane_runs(
            "pull_request", "success", untrusted
        ), f"untrusted output skipped a lane: {untrusted!r}"
    assert expensive_lane_runs("pull_request", "failure", "0")
    assert expensive_lane_runs("push", "success", "0")

    print(
        "PR path classification scenarios 13/13; non-UTF-8 and fail-open contracts passed"
    )


if __name__ == "__main__":
    main()
