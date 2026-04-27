#!/usr/bin/env bash
# ICU installer. Extracts upstream's Ubuntu22.04 prebuilt into /usr/local so
# JetBrains' bundled JBR, .NET, Node intl, etc. pick up a current libicu
# with fresh CLDR + IANA tz + Unicode/emoji data.
#
# Ubuntu22.04 binaries run on Debian trixie: glibc and libstdc++ are
# forward-compatible, and trixie's toolchain is newer than Ubuntu 22.04's.
# x86_64 only — upstream ships no arm64 prebuilt.
# https://github.com/unicode-org/icu
set -euo pipefail

ICU_VERSION="${ICU_VERSION:-latest}"

if [ "$ICU_VERSION" = "latest" ]; then
  TAG="$(curl -fsSL https://api.github.com/repos/unicode-org/icu/releases/latest \
    | sed -n 's/^.*"tag_name": *"\([^"]*\)".*$/\1/p')"
  ICU_VERSION="${TAG#release-}"
fi

ARCH="$(uname -m)"
if [ "$ARCH" != "x86_64" ]; then
  echo "icu: no upstream prebuilt for $ARCH (only x86_64). Install from source or use Debian's libicu." >&2
  exit 1
fi

TAG="release-${ICU_VERSION}"
FILE="icu4c-${ICU_VERSION}-Ubuntu22.04-x64.tgz"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

curl -fsSL -o "$TMPDIR/icu.tgz" \
  "https://github.com/unicode-org/icu/releases/download/${TAG}/${FILE}"

# Tarball layout: icu/usr/local/{bin,lib,include,share}/... — strip the
# leading `icu/` and drop the rest onto the root filesystem.
tar -xzf "$TMPDIR/icu.tgz" -C / --strip-components=1

# /usr/local/lib isn't on Debian's default ld.so search path — drop a conf
# snippet so the dynamic linker finds the new libicu*.so.
echo "/usr/local/lib" > /etc/ld.so.conf.d/usr-local.conf
ldconfig
