#!/usr/bin/env bash

BOLD='\033[0;1m'
RESET='\033[0m'

function run_web_shell() {
  echo "👷 Running web-shell in the background..."
  echo "Check logs at ${LOG_PATH}!"
  HOST="${HOST}" PORT="${PORT}" AUTH_TOKEN="${AUTH_TOKEN}" WEB_SHELL_CWD="${CWD}" \
    web-shell > "${LOG_PATH}" 2>&1 &
}

# Resolve the version to install. Empty means latest.
WANTED_VERSION="${VERSION}"
if [ -z "$${WANTED_VERSION}" ]; then
  WANTED_VERSION=$(curl -fsSL https://api.github.com/repos/SoureCode/web-shell/releases/latest \
    | awk -F\" '/"tag_name":/ {print $4; exit}')
fi
WANTED_VERSION="$${WANTED_VERSION#v}"

if [ -z "$${WANTED_VERSION}" ]; then
  echo "Failed to resolve web-shell release tag."
  exit 1
fi

# Install prereqs: dtach is required at runtime; build-essential + python3 cover
# node-pty's native build step when a prebuilt binding isn't available.
need=()
for pkg in dtach build-essential python3; do
  dpkg -s "$pkg" >/dev/null 2>&1 || need+=("$pkg")
done
if [ $${#need[@]} -gt 0 ]; then
  printf "$${BOLD}Installing prereqs: $${need[*]}$${RESET}\n"
  sudo apt-get update
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$${need[@]}"
fi

# Install or upgrade web-shell if the installed version doesn't match.
INSTALLED_VERSION=""
if command -v web-shell >/dev/null 2>&1; then
  INSTALLED_VERSION=$(npm ls -g --depth=0 --json web-shell 2>/dev/null \
    | awk -F\" '/"version":/ {print $4; exit}')
fi

if [ "$${INSTALLED_VERSION}" != "$${WANTED_VERSION}" ]; then
  printf "$${BOLD}Installing web-shell $${WANTED_VERSION}$${RESET}\n"
  TARBALL="https://github.com/SoureCode/web-shell/releases/download/v$${WANTED_VERSION}/web-shell-$${WANTED_VERSION}.tgz"
  if ! sudo -E env "PATH=$PATH" npm install -g "$${TARBALL}"; then
    echo "Failed to install web-shell $${WANTED_VERSION}"
    exit 1
  fi
  printf "🥳 web-shell $${WANTED_VERSION} installed\n\n"
fi

# Make web-shell available via CODER_SCRIPT_BIN_DIR too, like code-server does.
if [ -n "$CODER_SCRIPT_BIN_DIR" ] && [ ! -e "$CODER_SCRIPT_BIN_DIR/web-shell" ]; then
  ln -s "$(command -v web-shell)" "$CODER_SCRIPT_BIN_DIR/web-shell"
fi

run_web_shell
