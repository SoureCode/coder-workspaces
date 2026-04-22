#!/usr/bin/env bash
# claude-code feature installer.
set -e

USER_NAME="${_REMOTE_USER:-${USERNAME:-root}}"
if [ "$USER_NAME" = "root" ]; then
  USER_GROUP="root"
else
  USER_GROUP="$(id -gn "$USER_NAME")"
fi

USER_HOME="$(getent passwd "$USER_NAME" | cut -d: -f6)"

HOME="$USER_HOME" curl -fsSL https://claude.ai/install.sh | HOME="$USER_HOME" bash

if [ ! -x "$USER_HOME/.local/bin/claude" ]; then
  echo "claude-code feature: expected $USER_HOME/.local/bin/claude after install, but it was not found." >&2
  exit 1
fi

# The upstream installer runs as root with HOME=$USER_HOME and writes into
# $HOME/.claude, $HOME/.local AND $HOME/.cache (its own state dir plus
# node-gyp from any native-module compile). Chown all three so nothing is
# left root-owned on the remote user's home. .cache is guarded because it
# may not exist on minimal installs.
chown -R "$USER_NAME:$USER_GROUP" "$USER_HOME/.claude" "$USER_HOME/.local"
if [ -d "$USER_HOME/.cache" ]; then
  chown -R "$USER_NAME:$USER_GROUP" "$USER_HOME/.cache"
fi

# Declare the HOME paths Claude Code needs persisted. The home-persist feature
# reads every /etc/devcontainer-persist.d/*.json at create time and symlinks
# these into /mnt/home-persist. Safe to write even if home-persist isn't
# installed — the directory is harmless on its own.
mkdir -p /etc/devcontainer-persist.d
cat > /etc/devcontainer-persist.d/claude-code.json <<'EOF'
{
  "source": "claude-code",
  "paths": [".claude/", ".claude.json"]
}
EOF
