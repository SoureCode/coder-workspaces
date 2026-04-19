#!/usr/bin/env bash
# context-mode Claude Code plugin installer.
# https://github.com/mksglu/context-mode
set -e

USER_NAME="${_REMOTE_USER:-${USERNAME:-root}}"

run_as_user() {
  if [ "$USER_NAME" = "root" ]; then
    bash -c "$1"
  else
    su - "$USER_NAME" -c "$1"
  fi
}

if ! run_as_user 'command -v claude >/dev/null 2>&1'; then
  echo "context-mode feature: claude CLI not found. Install a claude-code feature (e.g. ghcr.io/sourecode/devcontainer-features/claude-code) first." >&2
  exit 1
fi

run_as_user 'claude plugin marketplace add mksglu/context-mode && claude plugin install context-mode@context-mode'
