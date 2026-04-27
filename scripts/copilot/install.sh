#!/usr/bin/env bash
# GitHub Copilot CLI installer. Runs as the workspace user — the upstream
# installer drops the binary into $HOME/.local/bin/copilot (on PATH via
# claude-code's .profile hook). Requires an active Copilot subscription at
# runtime; the install itself needs no auth.
# https://gh.io/copilot-install
set -eo pipefail

curl -fsSL https://gh.io/copilot-install | bash

if [ ! -x "$HOME/.local/bin/copilot" ]; then
  echo "copilot: expected $HOME/.local/bin/copilot after install, but it was not found." >&2
  exit 1
fi

# Persist Copilot CLI state across workspace rebuilds. ~/.copilot holds
# config.json (auth + settings), session-state/ (chat history, checkpoints),
# and logs/ — persist the whole dir so logins and sessions survive.
sudo mkdir -p /etc/home-persist.d
sudo tee /etc/home-persist.d/copilot.json >/dev/null <<'EOF'
{
  "source": "copilot",
  "paths": [".copilot/"]
}
EOF
