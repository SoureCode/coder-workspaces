#!/usr/bin/env bash
# claude-code feature installer. TEMPORARY — remove this feature in favor of
# ghcr.io/anthropics/devcontainer-features/claude-code once
# https://github.com/anthropics/devcontainer-features/pull/37 is merged.
set -e

USER_NAME="${_REMOTE_USER:-${USERNAME:-root}}"
if [ "$USER_NAME" = "root" ]; then
  USER_HOME="/root"
else
  USER_HOME="$(getent passwd "$USER_NAME" | cut -d: -f6)"
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

run_as_user 'curl -fsSL https://claude.ai/install.sh | bash'

CLAUDE_BIN="$USER_HOME/.local/bin/claude"
if [ -x "$CLAUDE_BIN" ]; then
  ln -sf "$CLAUDE_BIN" /usr/local/bin/claude
else
  echo "claude-code feature: expected $CLAUDE_BIN after install, but it was not found." >&2
  exit 1
fi
