#!/usr/bin/env python3
"""Validate the shared image and privilege boundary of both Dev Container lanes."""

from __future__ import annotations

import json
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
HUMAN_CONFIG_PATH = REPO_ROOT / ".devcontainer/devcontainer.json"
AGENT_CONFIG_PATH = REPO_ROOT / ".devcontainer/agent/devcontainer.json"
AGENT_POST_CREATE_PATH = REPO_ROOT / ".devcontainer/agent/post-create.sh"


def fail(message: str) -> None:
    raise AssertionError(message)


def load_config(path: Path) -> dict[str, object]:
    with path.open(encoding="utf-8") as config_file:
        return json.load(config_file)


def resolved_build(config_path: Path, config: dict[str, object]) -> tuple[Path, Path]:
    build = config.get("build")
    if not isinstance(build, dict):
        fail(f"{config_path} has no object build configuration")

    dockerfile = build.get("dockerfile")
    context = build.get("context")
    if not isinstance(dockerfile, str) or not isinstance(context, str):
        fail(f"{config_path} build paths are invalid")

    config_dir = config_path.parent
    return (config_dir / dockerfile).resolve(), (config_dir / context).resolve()


def assert_no_host_capabilities(config_path: Path, config: dict[str, object]) -> None:
    serialized = json.dumps(config, sort_keys=True)
    forbidden = (
        "1password",
        "docker.sock",
        "--cap-add",
        "seccomp=unconfined",
        "--privileged",
    )
    for token in forbidden:
        if token.lower() in serialized.lower():
            fail(f"{config_path} contains forbidden Agent boundary token: {token}")

    for key in ("mounts", "features", "privileged"):
        if key in config:
            fail(f"{config_path} must not declare {key}")


def main() -> None:
    human = load_config(HUMAN_CONFIG_PATH)
    agent = load_config(AGENT_CONFIG_PATH)

    expected_dockerfile = (REPO_ROOT / ".devcontainer/Dockerfile").resolve()
    expected_context = REPO_ROOT.resolve()
    for path, config in ((HUMAN_CONFIG_PATH, human), (AGENT_CONFIG_PATH, agent)):
        dockerfile, context = resolved_build(path, config)
        if (dockerfile, context) != (expected_dockerfile, expected_context):
            fail(f"{path} does not reuse the canonical Dockerfile and build context")
        if config.get("workspaceFolder") != "/workspaces/${localWorkspaceFolderBasename}":
            fail(f"{path} workspace folder drifted")
        if config.get("remoteUser") != "vscode":
            fail(f"{path} remote user is not vscode")
        container_env = config.get("containerEnv")
        if container_env != {"CHEZMOI_PROFILE": "devcontainer"}:
            fail(f"{path} does not use the shared devcontainer profile")

    if human.get("runArgs") != [
        "--cap-add=SYS_PTRACE",
        "--security-opt=seccomp=unconfined",
    ]:
        fail("Human lane debugging privileges drifted")
    expected_human_post_create = (
        '/bin/bash "/workspaces/${localWorkspaceFolderBasename}/.devcontainer/post-create.sh" '
        '"/workspaces/${localWorkspaceFolderBasename}"'
    )
    if human.get("postCreateCommand") != expected_human_post_create:
        fail("Human lane no longer invokes the canonical post-create entry point")

    assert_no_host_capabilities(AGENT_CONFIG_PATH, agent)
    if agent.get("containerUser") != "vscode":
        fail("Agent lane container user is not vscode")
    if agent.get("waitFor") != "postCreateCommand":
        fail("Agent lane can attach before post-create lockdown completes")
    if agent.get("runArgs") != [
        "--cap-drop=SYS_PTRACE",
        "--security-opt=seccomp=builtin",
    ]:
        fail("Agent lane runtime confinement drifted")
    if agent.get("remoteEnv") != {
        "SSH_AUTH_SOCK": "",
        "OP_SSH_AUTH_SOCK": "",
        "GH_TOKEN": "",
        "GITHUB_TOKEN": "",
    }:
        fail("Agent lane remote credential environment is not explicitly empty")
    expected_agent_post_create = [
        "/bin/bash",
        "/workspaces/${localWorkspaceFolderBasename}/.devcontainer/agent/post-create.sh",
        "/workspaces/${localWorkspaceFolderBasename}",
    ]
    if agent.get("postCreateCommand") != expected_agent_post_create:
        fail("Agent lane does not invoke its lockdown wrapper directly")

    wrapper = AGENT_POST_CREATE_PATH.read_text(encoding="utf-8")
    if wrapper.count(".devcontainer/post-create.sh") != 1:
        fail("Agent wrapper must delegate to the shared post-create exactly once")
    for duplicated_owner in (
        "chezmoi init",
        "brew install",
        "brew bundle",
        "MasonToolsInstall",
        "MasonToolsUpdate",
        "provision-nvim.sh",
    ):
        if duplicated_owner.lower() in wrapper.lower():
            fail(f"Agent wrapper duplicates provisioning ownership: {duplicated_owner}")
    for required_marker in (
        "/etc/sudoers.d/vscode",
        "/usr/bin/sudo -n /bin/rm",
        "/usr/bin/sudo -k",
        "/usr/bin/sudo -n true",
        "Restricted Agent lane lockdown complete",
    ):
        if required_marker not in wrapper:
            fail(f"Agent wrapper is missing lockdown contract: {required_marker}")

    print("Dev Container lane configuration contract passed")


if __name__ == "__main__":
    main()
