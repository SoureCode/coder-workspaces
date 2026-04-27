#!/usr/bin/env bash
# cmake installer. Runs as the workspace user — binaries land in $HOME/.local/.
# https://cmake.org/
set -e

CMAKE_VERSION="${CMAKE_VERSION:-latest}"

if [ "$CMAKE_VERSION" = "latest" ]; then
  CMAKE_VERSION="$(curl -fsSL https://api.github.com/repos/Kitware/CMake/releases/latest \
    | sed -n 's/^.*"tag_name": *"v\([^"]*\)".*$/\1/p')"
fi

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64)  CM_ARCH=x86_64 ;;
  aarch64) CM_ARCH=aarch64 ;;
  *) echo "cmake: unsupported arch: $ARCH" >&2; exit 1 ;;
esac

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

curl -fsSL -o "$TMPDIR/cmake.tar.gz" \
  "https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-${CM_ARCH}.tar.gz"

# Merge tarball contents into $HOME/.local — binaries land at $HOME/.local/bin/,
# which is on PATH via claude-code's .profile hook. No symlinks.
mkdir -p "$HOME/.local"
tar -xzf "$TMPDIR/cmake.tar.gz" -C "$HOME/.local" --strip-components=1
