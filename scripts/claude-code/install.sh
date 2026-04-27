#!/usr/bin/env bash
# claude-code installer. Runs as the workspace user (see src/base/Dockerfile).
set -e

curl -fsSL https://claude.ai/install.sh | bash

if [ ! -x "$HOME/.local/bin/claude" ]; then
  echo "claude-code: expected $HOME/.local/bin/claude after install, but it was not found." >&2
  exit 1
fi

# Declare the HOME paths Claude Code needs persisted. The home-persist
# resolver reads every /etc/home-persist.d/*.json at workspace start and
# symlinks these into /mnt/home-persist. /etc/home-persist.d is root-owned.
sudo mkdir -p /etc/home-persist.d
sudo tee /etc/home-persist.d/claude-code.json >/dev/null <<'EOF'
{
  "source": "claude-code",
  "paths": [".claude/", ".claude.json"]
}
EOF
