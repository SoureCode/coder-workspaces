# syntax=docker/dockerfile:1

ARG BASE_IMAGE=ghcr.io/sourecode/coder-workspace:base
FROM ${BASE_IMAGE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV DEBIAN_FRONTEND=noninteractive

RUN --mount=type=bind,source=scripts/go,target=/scripts/go \
    bash /scripts/go/install.sh

RUN --mount=type=bind,source=scripts/php,target=/scripts/php \
    bash /scripts/php/install.sh

USER ${_REMOTE_USER}
RUN --mount=type=bind,source=scripts/composer,target=/scripts/composer \
    bash /scripts/composer/install.sh
RUN --mount=type=bind,source=scripts/symfony-cli,target=/scripts/symfony-cli \
    bash /scripts/symfony-cli/install.sh
RUN --mount=type=bind,source=scripts/frankenphp,target=/scripts/frankenphp \
    bash /scripts/frankenphp/install.sh
USER root
