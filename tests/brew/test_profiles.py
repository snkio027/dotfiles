#!/usr/bin/env python3
"""Verify Brew ownership, profile membership, and automation boundaries."""

from __future__ import annotations

from pathlib import Path

import tomllib

ROOT = Path(__file__).resolve().parents[2]
CONTRACT_PATH = ROOT / "brew" / "ownership.toml"
PROFILE_DIR = ROOT / "brew" / "profiles"

WORKSTATION_BREWS = {
    "actionlint",
    "age",
    "atuin",
    "bat",
    "btop",
    "carapace",
    "ccache",
    "chezmoi",
    "cmake",
    "direnv",
    "duf",
    "dust",
    "eza",
    "fd",
    "fzf",
    "gh",
    "git",
    "git-delta",
    "gitleaks",
    "go",
    "hadolint",
    "hashicorp/tap/terraform",
    "helm",
    "hyperfine",
    "imagemagick",
    "jq",
    "kubernetes-cli",
    "lazygit",
    "llvm",
    "mermaid-cli",
    "neovim",
    "ninja",
    "node",
    "pkgconf",
    "python",
    "ripgrep",
    "rust",
    "rust-analyzer",
    "sd",
    "shellcheck",
    "shfmt",
    "sops",
    "starship",
    "stylua",
    "taplo",
    "tree-sitter-cli",
    "typst",
    "uv",
    "watchexec",
    "wget",
    "xh",
    "yazi",
    "yq",
    "zig",
    "zellij",
    "zizmor",
    "zoxide",
    "zsh",
    "zsh-autosuggestions",
    "zsh-syntax-highlighting",
}
WORKSTATION_CASKS = {
    "1password",
    "1password-cli",
    "font-inter",
    "font-jetbrains-mono-nerd-font",
    "font-maple-mono-nf-cn",
    "font-symbols-only-nerd-font",
    "ghostty",
    "orbstack",
}
QUALITY_BREWS = {
    "actionlint",
    "atuin",
    "chezmoi",
    "cmake",
    "devcontainer",
    "eza",
    "fd",
    "fzf",
    "gitleaks",
    "hadolint",
    "lazygit",
    "llvm",
    "neovim",
    "ninja",
    "python",
    "ripgrep",
    "rust-analyzer",
    "shellcheck",
    "shfmt",
    "starship",
    "stylua",
    "taplo",
    "tree-sitter-cli",
    "uv",
    "wget",
    "yazi",
    "zellij",
    "zizmor",
    "zsh",
    "zsh-autosuggestions",
    "zsh-syntax-highlighting",
}
QUALITY_CASKS = {"ghostty", "font-maple-mono-nf-cn", "font-symbols-only-nerd-font"}


def fail(message: str) -> None:
    raise AssertionError(message)


def names(contract: dict, profile: str, kind: str) -> set[str]:
    return {
        tool["name"]
        for tool in contract["tools"]
        if profile in tool["profiles"] and tool["kind"] == kind
    }


with CONTRACT_PATH.open("rb") as handle:
    contract = tomllib.load(handle)

if contract.get("schema_version") != 1:
    fail("unsupported ownership contract schema")

profiles = contract.get("profiles", {})
if set(profiles) != {"core", "workstation", "devcontainer", "quality"}:
    fail("the four required Brew profiles are not declared")
for profile in ("core", "devcontainer", "quality"):
    if profiles[profile].get("automation") != "ci":
        fail(f"{profile} must be a CI-installable profile")
if profiles["workstation"].get("automation") != "manual-boundary":
    fail("workstation must retain its explicit manual verification boundary")
if not profiles["workstation"].get("boundary"):
    fail("workstation verification boundary is undocumented")

seen: set[tuple[str, str]] = set()
owners: dict[tuple[str, str], str] = {}
for tool in contract["tools"]:
    key = (tool["kind"], tool["name"])
    if key in seen:
        fail(f"duplicate ownership declaration: {key}")
    seen.add(key)
    owners[key] = tool["owner"]
    if tool["owner"] not in profiles:
        fail(f"unknown owner for {key}: {tool['owner']}")
    if not tool["profiles"] or set(tool["profiles"]) - set(profiles):
        fail(f"invalid profile membership for {key}")

if names(contract, "workstation", "brew") != WORKSTATION_BREWS:
    fail("workstation formula set drifted from the pre-profile baseline")
if names(contract, "devcontainer", "brew") != WORKSTATION_BREWS:
    fail("Dev Container formula set no longer matches the Linux workstation baseline")
if names(contract, "quality", "brew") != QUALITY_BREWS:
    fail("quality formula set drifted from the former CI Brewfile")
if names(contract, "workstation", "cask") != WORKSTATION_CASKS:
    fail("workstation cask set drifted from the pre-profile baseline")
if names(contract, "devcontainer", "cask"):
    fail("Dev Container profile must not contain GUI casks")
if names(contract, "quality", "cask") != QUALITY_CASKS:
    fail("quality macOS cask set drifted from the former CI Brewfile")
if names(contract, "workstation", "tap") != {"hashicorp/tap"}:
    fail("workstation HashiCorp tap ownership drifted")
if names(contract, "devcontainer", "tap") != {"hashicorp/tap"}:
    fail("Dev Container HashiCorp tap ownership drifted")
if names(contract, "core", "tap") or names(contract, "core", "cask"):
    fail("core must remain safe for unattended official-formula CI installation")

trusted_tools = {
    (tool["kind"], tool["name"]): tool["trusted"]
    for tool in contract["tools"]
    if tool.get("trusted")
}
if trusted_tools != {
    ("tap", "hashicorp/tap"): {"formulae": ["terraform"]},
}:
    fail("Homebrew trust must remain scoped to HashiCorp Terraform only")

zsh = next(tool for tool in contract["tools"] if tool["name"] == "zsh")
if zsh.get("conditions", {}).get("workstation") != "linux":
    fail("workstation Zsh must remain Linux-only")
if zsh.get("conditions", {}).get("devcontainer", "all") != "all":
    fail("Dev Container Zsh must be unconditional")

if (ROOT / "Brewfile").read_bytes() != (
    PROFILE_DIR / "workstation.Brewfile"
).read_bytes():
    fail("root Brewfile compatibility entry point drifted from workstation profile")

if any("markdownlint" in tool["name"] for tool in contract["tools"]):
    fail("markdownlint-cli2 must not be globally owned by Homebrew")
aliases = (ROOT / "home" / "dot_config" / "zsh" / "aliases.zsh").read_text(
    encoding="utf-8"
)
if "markdownlint-cli2" in aliases:
    fail("Shell still claims global markdownlint-cli2 ownership")
toolchain = (
    ROOT / "home" / "dot_config" / "nvim" / "lua" / "plugins" / "toolchain.lua"
).read_text(encoding="utf-8")
if toolchain.count('"markdownlint-cli2"') != 1:
    fail("Neovim must explicitly own markdownlint-cli2 exactly once")

print(f"Brew ownership declarations  {len(seen)}/{len(seen)}")
print(f"Workstation formulas         {len(WORKSTATION_BREWS)}/{len(WORKSTATION_BREWS)}")
print(f"Dev Container formulas       {len(WORKSTATION_BREWS)}/{len(WORKSTATION_BREWS)}")
print(f"Quality formulas             {len(QUALITY_BREWS)}/{len(QUALITY_BREWS)}")
print("Markdownlint ownership       Mason-only")
