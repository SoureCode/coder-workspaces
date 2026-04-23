#!/usr/bin/env bash
# web-shell launcher. web-shell is installed under the workspace user's nvm
# default, so nvm must be sourced before the binary is on PATH. Runs as the
# workspace user under web-shell.service.
set -e

export NVM_DIR="$HOME/.nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then
  # shellcheck disable=SC1091
  . "$NVM_DIR/nvm.sh"
  nvm use default >/dev/null 2>&1 || true
fi

exec web-shell
