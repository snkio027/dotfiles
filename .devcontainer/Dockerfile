# ------------------------------------------------------------------------------
# DevContainer Workstation Dockerfile — Disposable Platform Image
# DevSecOps Grade Platform Engineering Standard
# ------------------------------------------------------------------------------
FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

USER vscode
ENV USER=vscode
ENV HOME=/home/vscode

# Install core build dependencies, Zsh, git, curl
RUN apt-get update && apt-get install -y --no-install-recommends \
  build-essential \
  curl \
  git \
  zsh \
  age \
  jq \
  ca-certificates \
  && rm -rf /var/lib/apt/lists/*

# Install chezmoi
RUN sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"

# Set default shell to Zsh
ENV SHELL=/bin/zsh
WORKDIR /home/vscode
