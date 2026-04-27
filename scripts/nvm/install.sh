#!/usr/bin/env bash
# nvm installer. Runs as the workspace user — installs to $HOME/.nvm via
# the upstream installer. PROFILE=/dev/null suppresses dotfile modification;
# a guarded loader is appended to ~/.bashrc explicitly below.
# https://github.com/nvm-sh/nvm
set -eo pipefail

NVM_VERSION="${NVM_VERSION:-0.40.4}"
NODE_VERSION="${NODE_VERSION:-lts}"

curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh" \
  | PROFILE=/dev/null bash

cat >> "$HOME/.bashrc" <<'EOF'

if [ -z "${NVM_DIR:-}" ]; then
  export NVM_DIR="$HOME/.nvm"
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
  [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
fi
EOF

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
  mkdir -p "$HOME/.local/share/bash-completion/completions"
  npm completion > "$HOME/.local/share/bash-completion/completions/npm"
fi
