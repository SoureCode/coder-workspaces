# syntax=docker/dockerfile:1

ARG BASE_IMAGE=ghcr.io/sourecode/coder-workspace:base
FROM ${BASE_IMAGE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV DEBIAN_FRONTEND=noninteractive

# System-wide installers (root).
RUN --mount=type=bind,source=scripts,target=/scripts \
    bash "/scripts/llvm/install.sh"

RUN printf 'export CC=/usr/local/bin/clang\nexport CXX=/usr/local/bin/clang++\n' \
    > /etc/profile.d/llvm-env.sh

# cmake and sccache drop their binaries in $HOME/.local → run as the remote user.
USER ${_REMOTE_USER}
RUN --mount=type=bind,source=scripts,target=/scripts \
    for s in cmake sccache; do \
      bash "/scripts/$s/install.sh"; \
    done
USER root
