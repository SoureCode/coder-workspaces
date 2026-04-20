#!/usr/bin/env bash
# claude-code feature installer.
#
# Requires Node.js on PATH (provided by the nvm feature via `dependsOn`).
# Installs the binary to /usr/local/bin so it lives in an image layer,
# independent of the persistence volume, and declares the HOME paths that
# need to survive rebuilds via the home-persist manifest.
set -e

if ! command -v curl >/dev/null 2>&1; then
  apt-get update
  apt-get install -y --no-install-recommends curl ca-certificates
  rm -rf /var/lib/apt/lists/*
fi

curl -fsSL https://claude.ai/install.sh | bash

SRC_BIN="$HOME/.local/bin/claude"
if [ ! -x "$SRC_BIN" ]; then
  echo "claude-code feature: expected $SRC_BIN after install, but it was not found." >&2
  exit 1
fi

install -m 0755 "$SRC_BIN" /usr/local/bin/claude

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
