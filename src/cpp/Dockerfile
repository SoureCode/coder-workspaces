# syntax=docker/dockerfile:1

ARG BASE_IMAGE=ghcr.io/sourecode/coder-workspace:base
FROM ${BASE_IMAGE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV DEBIAN_FRONTEND=noninteractive

RUN --mount=type=bind,source=scripts,target=/scripts \
    for s in llvm cmake sccache; do \
      bash "/scripts/$s/install.sh"; \
    done

RUN printf 'export CC=/usr/local/bin/clang\nexport CXX=/usr/local/bin/clang++\n' \
    > /etc/profile.d/llvm-env.sh
