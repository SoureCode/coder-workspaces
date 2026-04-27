#!/usr/bin/env bash
# FrankenPHP installer. Runs as the workspace user — single static binary
# from GitHub releases into $HOME/.local/bin. FrankenPHP is a modern PHP
# app server (Caddy + PHP embedded).
# https://github.com/dunglas/frankenphp
set -e

FP_VERSION_OPT="${FRANKENPHP_VERSION:-latest}"
INSTALL_DIR="$HOME/.local/bin"
mkdir -p "$INSTALL_DIR"

arch=$(uname -m)
case "$arch" in
  x86_64)  asset_arch=x86_64 ;;
  aarch64) asset_arch=aarch64 ;;
  *) echo "frankenphp: unsupported arch '$arch'." >&2; exit 1 ;;
esac

if [ "$FP_VERSION_OPT" = "latest" ]; then
  FP_VERSION="$(curl -fsSL https://api.github.com/repos/dunglas/frankenphp/releases/latest | jq -r .tag_name)"
else
  FP_VERSION="$FP_VERSION_OPT"
fi
FP_VERSION="${FP_VERSION#v}"
if [ -z "$FP_VERSION" ] || [ "$FP_VERSION" = "null" ]; then
  echo "frankenphp: failed to resolve release version (got '$FP_VERSION_OPT')." >&2
  exit 1
fi

curl -fsSL "https://github.com/dunglas/frankenphp/releases/download/v${FP_VERSION}/frankenphp-linux-${asset_arch}" \
  -o "$INSTALL_DIR/frankenphp"
chmod 0755 "$INSTALL_DIR/frankenphp"

if ! "$INSTALL_DIR/frankenphp" version >/dev/null 2>&1; then
  echo "frankenphp: binary not runnable after install." >&2
  exit 1
fi
