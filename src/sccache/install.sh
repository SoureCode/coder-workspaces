#!/usr/bin/env bash
# sccache feature installer.
# https://github.com/mozilla/sccache
set -e

SCCACHE_VERSION="${VERSION:-latest}"

if ! command -v curl >/dev/null 2>&1 || ! command -v tar >/dev/null 2>&1; then
  apt-get update
  apt-get install -y --no-install-recommends curl ca-certificates tar
  rm -rf /var/lib/apt/lists/*
fi

if [ "$SCCACHE_VERSION" = "latest" ]; then
  SCCACHE_VERSION="$(curl -fsSL https://api.github.com/repos/mozilla/sccache/releases/latest \
    | sed -n 's/^.*"tag_name": *"v\([^"]*\)".*$/\1/p')"
fi

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64)  SC_ARCH=x86_64-unknown-linux-musl ;;
  aarch64) SC_ARCH=aarch64-unknown-linux-musl ;;
  *) echo "sccache feature: unsupported arch: $ARCH" >&2; exit 1 ;;
esac

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

curl -fsSL -o "$TMPDIR/sccache.tar.gz" \
  "https://github.com/mozilla/sccache/releases/download/v${SCCACHE_VERSION}/sccache-v${SCCACHE_VERSION}-${SC_ARCH}.tar.gz"
tar -xzf "$TMPDIR/sccache.tar.gz" -C "$TMPDIR"

install -m 0755 "$TMPDIR/sccache-v${SCCACHE_VERSION}-${SC_ARCH}/sccache" /usr/local/bin/sccache
