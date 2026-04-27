#!/usr/bin/env bash
# nvm installer. Runs as the workspace user — installs to $HOME/.nvm via
# the upstream installer, which appends its loader snippet to ~/.profile.
# https://github.com/nvm-sh/nvm
set -e

NVM_VERSION="${NVM_VERSION:-0.40.4}"
NODE_VERSION="${NODE:-lts}"

curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh" \
  | PROFILE="$HOME/.profile" bash

if [ "$NODE_VERSION" != "none" ]; then
  export NVM_DIR="$HOME/.nvm"
  # shellcheck disable=SC1091
  . "$NVM_DIR/nvm.sh"
  if [ "$NODE_VERSION" = "lts" ]; then
    nvm install --lts
    nvm alias default "lts/*"
  else
    # shellcheck disable=SC2086
    nvm install "$NODE_VERSION"
    nvm alias default "$NODE_VERSION"
  fi
fi
