#!/usr/bin/env bash
# cmake feature installer.
# https://cmake.org/
set -e

CMAKE_VERSION="${VERSION:-latest}"

if ! command -v curl >/dev/null 2>&1 || ! command -v tar >/dev/null 2>&1; then
  apt-get update
  apt-get install -y --no-install-recommends curl ca-certificates tar
  rm -rf /var/lib/apt/lists/*
fi

if [ "$CMAKE_VERSION" = "latest" ]; then
  CMAKE_VERSION="$(curl -fsSL https://api.github.com/repos/Kitware/CMake/releases/latest \
    | sed -n 's/^.*"tag_name": *"v\([^"]*\)".*$/\1/p')"
fi

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64)  CM_ARCH=x86_64 ;;
  aarch64) CM_ARCH=aarch64 ;;
  *) echo "cmake feature: unsupported arch: $ARCH" >&2; exit 1 ;;
esac

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

curl -fsSL -o "$TMPDIR/cmake.tar.gz" \
  "https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-${CM_ARCH}.tar.gz"
tar -xzf "$TMPDIR/cmake.tar.gz" -C "$TMPDIR"

INSTALL_DIR="/usr/local/cmake-${CMAKE_VERSION}"
rm -rf "$INSTALL_DIR"
mv "$TMPDIR/cmake-${CMAKE_VERSION}-linux-${CM_ARCH}" "$INSTALL_DIR"

for bin in cmake ctest cpack ccmake; do
  [ -x "$INSTALL_DIR/bin/$bin" ] || continue
  ln -sf "$INSTALL_DIR/bin/$bin" "/usr/local/bin/$bin"
done
