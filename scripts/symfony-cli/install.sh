#!/usr/bin/env bash
# symfony-cli installer. Runs as the workspace user — prebuilt tarball from
# GitHub releases into $HOME/.local/bin.
# https://github.com/symfony-cli/symfony-cli
set -e

SF_VERSION_OPT="${SYMFONY_VERSION:-latest}"
INSTALL_DIR="$HOME/.local/bin"
mkdir -p "$INSTALL_DIR"

arch=$(dpkg --print-architecture)
case "$arch" in
  amd64) asset_arch=amd64 ;;
  arm64) asset_arch=arm64 ;;
  *) echo "symfony-cli: unsupported arch '$arch'." >&2; exit 1 ;;
esac

if [ "$SF_VERSION_OPT" = "latest" ]; then
  SF_VERSION="$(curl -fsSL https://api.github.com/repos/symfony-cli/symfony-cli/releases/latest | jq -r .tag_name)"
else
  SF_VERSION="$SF_VERSION_OPT"
fi
SF_VERSION="${SF_VERSION#v}"
if [ -z "$SF_VERSION" ] || [ "$SF_VERSION" = "null" ]; then
  echo "symfony-cli: failed to resolve release version (got '$SF_VERSION_OPT')." >&2
  exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

curl -fsSL "https://github.com/symfony-cli/symfony-cli/releases/download/v${SF_VERSION}/symfony-cli_linux_${asset_arch}.tar.gz" \
  | tar -xz -C "$tmp"
install -m 0755 "$tmp/symfony" "$INSTALL_DIR/symfony"

if ! "$INSTALL_DIR/symfony" version >/dev/null 2>&1; then
  echo "symfony-cli: binary not runnable after install." >&2
  exit 1
fi
