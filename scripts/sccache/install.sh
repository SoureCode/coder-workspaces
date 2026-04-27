#!/usr/bin/env bash
# sccache installer. Runs as the workspace user — binary lands in $HOME/.local/bin.
# https://github.com/mozilla/sccache
set -e

SCCACHE_VERSION="${SCCACHE_VERSION:-latest}"

if [ "$SCCACHE_VERSION" = "latest" ]; then
  SCCACHE_VERSION="$(curl -fsSL https://api.github.com/repos/mozilla/sccache/releases/latest \
    | sed -n 's/^.*"tag_name": *"v\([^"]*\)".*$/\1/p')"
fi

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64)  SC_ARCH=x86_64-unknown-linux-musl ;;
  aarch64) SC_ARCH=aarch64-unknown-linux-musl ;;
  *) echo "sccache: unsupported arch: $ARCH" >&2; exit 1 ;;
esac

mkdir -p "$HOME/.local/bin"
curl -fsSL "https://github.com/mozilla/sccache/releases/download/v${SCCACHE_VERSION}/sccache-v${SCCACHE_VERSION}-${SC_ARCH}.tar.gz" \
  | tar -xzf - -C "$HOME/.local/bin" --strip-components=1 \
      "sccache-v${SCCACHE_VERSION}-${SC_ARCH}/sccache"
