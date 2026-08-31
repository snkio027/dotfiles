# ------------------------------------------------------------------------------
# DevContainer Workstation Dockerfile — Disposable Platform Image
# DevSecOps Grade Platform Engineering Standard
# ------------------------------------------------------------------------------
FROM mcr.microsoft.com/devcontainers/base:resolute@sha256:00e84e24112159d45c0262f07cb013cb58cb6a415f3e1c743d4a3115ac5d76c6

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
  && usermod --shell /bin/zsh vscode \
  && rm -rf /var/lib/apt/lists/*

# Install user-scoped tooling without granting the interactive user root access
USER vscode
ENV USER=vscode
ENV HOME=/home/vscode
ENV PATH="/home/vscode/.local/bin:${PATH}"

# Install one verified Linux release asset. The bootstrap writes its receipt
# only after the archive checksum and embedded version both match the manifest.
ARG TARGETARCH
COPY --chown=vscode:vscode .devcontainer/install-chezmoi.sh \
  .devcontainer/chezmoi-provenance.env /tmp/chezmoi-bootstrap/
RUN CHEZMOI_ARCH="$TARGETARCH" \
    CHEZMOI_INSTALL_DIR="$HOME/.local/bin" \
    /tmp/chezmoi-bootstrap/install-chezmoi.sh \
  && rm -rf /tmp/chezmoi-bootstrap

# Set default shell to Zsh
ENV SHELL=/bin/zsh
WORKDIR /home/vscode
