#!/usr/bin/env bash
# claude-code installer.
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
  echo "claude-code: expected $USER_HOME/.local/bin/claude after install, but it was not found." >&2
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

# Declare the HOME paths Claude Code needs persisted. The home-persist
# resolver reads every /etc/home-persist.d/*.json at workspace start and
# symlinks these into /mnt/home-persist.
mkdir -p /etc/home-persist.d
cat > /etc/home-persist.d/claude-code.json <<'EOF'
{
  "source": "claude-code",
  "paths": [".claude/", ".claude.json"]
}
EOF
