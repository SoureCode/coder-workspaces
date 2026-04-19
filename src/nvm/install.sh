#!/usr/bin/env bash
# nvm feature installer.
# https://github.com/nvm-sh/nvm
set -e

NVM_VERSION="${VERSION:-0.40.4}"
NODE_VERSION="${NODE:-lts}"

USER_NAME="${_REMOTE_USER:-${USERNAME:-root}}"
USER_HOME="${_REMOTE_USER_HOME:-}"
if [ -z "$USER_HOME" ]; then
  if [ "$USER_NAME" = "root" ]; then
    USER_HOME="/root"
  else
    USER_HOME="$(getent passwd "$USER_NAME" | cut -d: -f6)"
  fi
fi

if ! command -v curl >/dev/null 2>&1; then
  apt-get update
  apt-get install -y --no-install-recommends curl ca-certificates
  rm -rf /var/lib/apt/lists/*
fi

run_as_user() {
  if [ "$USER_NAME" = "root" ]; then
    bash -c "$1"
  else
    su - "$USER_NAME" -c "$1"
  fi
}

run_as_user "curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh | PROFILE=/dev/null bash"

NVM_INIT='export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"; [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"'

for rc in "$USER_HOME/.bashrc" "$USER_HOME/.zshrc" "$USER_HOME/.profile"; do
  [ -f "$rc" ] || continue
  if ! grep -q 'NVM_DIR="$HOME/.nvm"' "$rc"; then
    printf '\n# nvm\n%s\n' "$NVM_INIT" >>"$rc"
    chown "$USER_NAME:$(id -gn "$USER_NAME")" "$rc" 2>/dev/null || true
  fi
done

if [ "$NODE_VERSION" != "none" ]; then
  if [ "$NODE_VERSION" = "lts" ]; then
    NVM_INSTALL_ARG="--lts"
    NVM_ALIAS_TARGET="lts/*"
  else
    NVM_INSTALL_ARG="$NODE_VERSION"
    NVM_ALIAS_TARGET="$NODE_VERSION"
  fi
  run_as_user "$NVM_INIT && nvm install $NVM_INSTALL_ARG && nvm alias default '$NVM_ALIAS_TARGET'"
fi
