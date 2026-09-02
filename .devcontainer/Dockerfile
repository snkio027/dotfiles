# ------------------------------------------------------------------------------
# DevContainer Workstation Dockerfile — Disposable Platform Image
# DevSecOps Grade Platform Engineering Standard
# ------------------------------------------------------------------------------
FROM mcr.microsoft.com/devcontainers/base:resolute@sha256:00e84e24112159d45c0262f07cb013cb58cb6a415f3e1c743d4a3115ac5d76c6

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

USER root

# The pinned base owns bootstrap OS commands. Fail closed if a future digest
# loses one; Homebrew provisions age and the workstation tools post-create.
RUN for command in bash cc curl git jq make sha256sum tar unzip xz zsh; do \
      command -v "$command" >/dev/null || { echo "missing base command: $command" >&2; exit 1; }; \
    done \
  && usermod --shell /bin/zsh vscode

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
