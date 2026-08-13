# ------------------------------------------------------------------------------
# DevContainer Workstation Dockerfile — Disposable Platform Image
# DevSecOps Grade Platform Engineering Standard
# ------------------------------------------------------------------------------
FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

USER root

# Install the OS base; chezmoi provisions current Homebrew formulae afterwards.
RUN apt-get update && apt-get install -y --no-install-recommends \
  age \
  build-essential \
  ca-certificates \
  curl \
  git \
  jq \
  unzip \
  xz-utils \
  zsh \
  && rm -rf /var/lib/apt/lists/*

# Install user-scoped tooling without granting the interactive user root access
USER vscode
ENV USER=vscode
ENV HOME=/home/vscode
ENV PATH="/home/vscode/.local/bin:${PATH}"

# Install chezmoi
RUN sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"

# Set default shell to Zsh
ENV SHELL=/bin/zsh
WORKDIR /home/vscode
