#!/usr/bin/env bash
# claude-code feature installer.
#
# Requires Node.js on PATH (provided by the nvm feature via `dependsOn`).
#
# The official installer writes to $HOME/.local/bin. Because our devcontainers
# mount $HOME as a named volume (see docs/persistence.md), anything dropped in
# the user's home at build time is hidden on any run where the volume already
# has content. Install into a scratch HOME and relocate the binary to
# /usr/local/bin so it lives in image layers, outside the mount.
set -e

if ! command -v curl >/dev/null 2>&1; then
  apt-get update
  apt-get install -y --no-install-recommends curl ca-certificates
  rm -rf /var/lib/apt/lists/*
fi

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

HOME="$SCRATCH" curl -fsSL https://claude.ai/install.sh | HOME="$SCRATCH" bash

SRC_BIN="$SCRATCH/.local/bin/claude"
if [ ! -x "$SRC_BIN" ]; then
  echo "claude-code feature: expected $SRC_BIN after install, but it was not found." >&2
  exit 1
fi

install -m 0755 "$SRC_BIN" /usr/local/bin/claude
