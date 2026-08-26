# ------------------------------------------------------------------------------
# DevContainer Workstation Dockerfile — Disposable Platform Image
# DevSecOps Grade Platform Engineering Standard
# ------------------------------------------------------------------------------
FROM mcr.microsoft.com/devcontainers/base:resolute

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

# Install the latest chezmoi, retrying the complete installer because its
# internal release-asset download does not retry transient network failures.
RUN for attempt in 1 2 3 4 5; do \
    sh -c "$(curl --retry 5 --retry-all-errors -fsLS https://get.chezmoi.io)" \
      -- -b "$HOME/.local/bin" && break; \
    if [ "$attempt" -eq 5 ]; then exit 1; fi; \
    sleep "$((attempt * 2))"; \
  done

# Set default shell to Zsh
ENV SHELL=/bin/zsh
WORKDIR /home/vscode
