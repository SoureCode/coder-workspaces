#!/usr/bin/env bash
# web-shell installer. Runs as the workspace user — npm install -g goes into
# the user's own nvm prefix ($HOME/.nvm/versions/node/<v>/bin).
# https://github.com/SoureCode/web-shell
#
# Supervision is handled at workspace start by coder_script.web_shell in
# main.tf — this installer only places the binary. Bind address is always
# 127.0.0.1 and auth is disabled; web-shell is reached via Coder's reverse
# proxy, which gates access with Coder auth.
set -e

WS_VERSION_OPT="${VERSION:-0.5.0}"

# Activate nvm so `npm` resolves against the user's default Node.
export NVM_DIR="$HOME/.nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then
  # shellcheck disable=SC1091
  . "$NVM_DIR/nvm.sh"
  nvm use default >/dev/null
fi

if ! command -v npm >/dev/null 2>&1; then
  echo "web-shell: npm not on PATH. scripts/nvm/install.sh must run before scripts/web-shell/install.sh." >&2
  exit 1
fi

# Resolve target version. `latest` → newest tag via GitHub API.
if [ "$WS_VERSION_OPT" = "latest" ]; then
  WS_VERSION="$(curl -fsSL https://api.github.com/repos/SoureCode/web-shell/releases/latest | jq -r .tag_name)"
else
  WS_VERSION="$WS_VERSION_OPT"
fi
WS_VERSION="${WS_VERSION#v}"
if [ -z "$WS_VERSION" ] || [ "$WS_VERSION" = "null" ]; then
  echo "web-shell: failed to resolve release version (got '$WS_VERSION_OPT')." >&2
  exit 1
fi

# npm accepts the release-tarball URL directly — no curl+tmpfile dance.
npm install -g "https://github.com/SoureCode/web-shell/releases/download/v${WS_VERSION}/web-shell-${WS_VERSION}.tgz"

if ! command -v web-shell >/dev/null 2>&1; then
  echo "web-shell: binary not on PATH after npm install." >&2
  exit 1
fi
