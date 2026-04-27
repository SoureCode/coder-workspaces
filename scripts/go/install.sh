#!/usr/bin/env bash
# Go installer — installs to /usr/local/go (system-wide).
set -e

GO_VERSION="${GO_VERSION:-latest}"

if [ "$GO_VERSION" = "latest" ]; then
  GO_VERSION="$(curl -fsSL 'https://go.dev/VERSION?m=text' | head -1 | sed 's/^go//')"
fi

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64)  GO_ARCH=amd64 ;;
  aarch64) GO_ARCH=arm64 ;;
  *) echo "go: unsupported arch: $ARCH" >&2; exit 1 ;;
esac

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

curl -fsSL -o "$TMPDIR/go.tar.gz" \
  "https://dl.google.com/go/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz"

rm -rf /usr/local/go
tar -C /usr/local -xzf "$TMPDIR/go.tar.gz"

ln -sf /usr/local/go/bin/go /usr/local/bin/go
ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt

printf 'export PATH="/usr/local/go/bin:$HOME/go/bin:$PATH"\n' \
  > /etc/profile.d/go.sh
