#!/usr/bin/env bash
# rtk feature installer.
# https://github.com/rtk-ai/rtk
set -e

AUTO_PATCH_CLAUDE="${AUTOPATCHCLAUDE:-true}"

USER_NAME="${_REMOTE_USER:-${USERNAME:-root}}"
USER_HOME="${_REMOTE_USER_HOME:-}"
if [ -z "$USER_HOME" ]; then
  if [ "$USER_NAME" = "root" ]; then
    USER_HOME="/root"
  else
    USER_HOME="$(getent passwd "$USER_NAME" | cut -d: -f6)"
  fi
fi

if ! command -v curl >/dev/null 2>&1; then
  apt-get update
  apt-get install -y --no-install-recommends curl ca-certificates
  rm -rf /var/lib/apt/lists/*
fi

run_as_user() {
  if [ "$USER_NAME" = "root" ]; then
    bash -c "$1"
  else
    su - "$USER_NAME" -c "$1"
  fi
}

run_as_user 'curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh'

if [ "$AUTO_PATCH_CLAUDE" = "true" ]; then
  if run_as_user 'command -v claude >/dev/null 2>&1'; then
    run_as_user 'rtk init -g --auto-patch'
  else
    echo "rtk feature: claude CLI not on PATH, skipping auto-patch. Install ghcr.io/anthropics/devcontainer-features/claude-code to enable it." >&2
  fi
fi
