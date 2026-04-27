#!/usr/bin/env bash
# codex installer. Runs as the workspace user — npm install -g goes into
# the user's own nvm prefix ($HOME/.nvm/versions/node/<v>/bin).
# https://github.com/openai/codex
set -e

CODEX_VERSION_OPT="${CODEX_VERSION:-latest}"

# Activate nvm so `npm` resolves against the user's default Node.
export NVM_DIR="$HOME/.nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then
  # shellcheck disable=SC1091
  . "$NVM_DIR/nvm.sh"
  nvm use default >/dev/null
fi

if ! command -v npm >/dev/null 2>&1; then
  echo "codex: npm not on PATH. scripts/nvm/install.sh must run before scripts/codex/install.sh." >&2
  exit 1
fi

# Resolve target version. `latest` → newest tag via GitHub API.
if [ "$CODEX_VERSION_OPT" = "latest" ]; then
  CODEX_VERSION="$(curl -fsSL https://api.github.com/repos/openai/codex/releases/latest | jq -r .tag_name)"
else
  CODEX_VERSION="$CODEX_VERSION_OPT"
fi
CODEX_VERSION="${CODEX_VERSION#rust-v}"
if [ -z "$CODEX_VERSION" ] || [ "$CODEX_VERSION" = "null" ]; then
  echo "codex: failed to resolve release version (got '$CODEX_VERSION_OPT')." >&2
  exit 1
fi

npm install -g "@openai/codex@${CODEX_VERSION}"

if ! command -v codex >/dev/null 2>&1; then
  echo "codex: binary not on PATH after npm install." >&2
  exit 1
fi

# Declare the HOME paths Codex needs persisted. The home-persist
# resolver reads every /etc/home-persist.d/*.json at workspace start and
# symlinks these into /mnt/home-persist. /etc/home-persist.d is root-owned.
sudo mkdir -p /etc/home-persist.d
sudo tee /etc/home-persist.d/codex.json >/dev/null <<'EOF'
{
  "source": "codex",
  "paths": [".codex/"]
}
EOF
