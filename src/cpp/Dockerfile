# syntax=docker/dockerfile:1

ARG BASE_IMAGE=ghcr.io/sourecode/coder-workspace:base
FROM ${BASE_IMAGE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV DEBIAN_FRONTEND=noninteractive

# Per-tool bind mounts so a change in one installer only busts its own layer.
RUN --mount=type=bind,source=scripts/llvm,target=/scripts/llvm \
    bash /scripts/llvm/install.sh

RUN printf 'export CC=/usr/local/bin/clang\nexport CXX=/usr/local/bin/clang++\n' \
    > /etc/profile.d/llvm-env.sh

# cmake and sccache drop their binaries in $HOME/.local → run as the remote user.
USER ${_REMOTE_USER}
RUN --mount=type=bind,source=scripts/cmake,target=/scripts/cmake \
    bash /scripts/cmake/install.sh
RUN --mount=type=bind,source=scripts/sccache,target=/scripts/sccache \
    bash /scripts/sccache/install.sh
USER root
