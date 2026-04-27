# syntax=docker/dockerfile:1

ARG BASE_IMAGE=ghcr.io/sourecode/coder-workspace:base
FROM ${BASE_IMAGE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV DEBIAN_FRONTEND=noninteractive

RUN --mount=type=bind,source=scripts/go,target=/scripts/go \
    bash /scripts/go/install.sh
