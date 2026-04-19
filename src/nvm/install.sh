#!/usr/bin/env bash
# nvm feature installer.
# https://github.com/nvm-sh/nvm
set -e

NVM_VERSION="${VERSION:-0.40.4}"
NODE_VERSION="${NODE:-lts}"

NVM_DIR=/usr/local/share/nvm
export NVM_DIR

USER_NAME="${_REMOTE_USER:-${USERNAME:-root}}"
if [ "$USER_NAME" = "root" ]; then
  USER_GROUP="root"
else
  USER_GROUP="$(id -gn "$USER_NAME")"
fi

if ! command -v curl >/dev/null 2>&1; then
  apt-get update
  apt-get install -y --no-install-recommends curl ca-certificates
  rm -rf /var/lib/apt/lists/*
fi

mkdir -p "$NVM_DIR"
chown "$USER_NAME:$USER_GROUP" "$NVM_DIR"
chmod g+ws "$NVM_DIR"

curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh" | PROFILE=/dev/null bash

cat >/etc/profile.d/nvm.sh <<EOF
export NVM_DIR="$NVM_DIR"
[ -s "\$NVM_DIR/nvm.sh" ] && \\. "\$NVM_DIR/nvm.sh"
[ -s "\$NVM_DIR/bash_completion" ] && \\. "\$NVM_DIR/bash_completion"
EOF
chmod 644 /etc/profile.d/nvm.sh

# Non-login interactive bash shells (VS Code / code-server terminals) source
# /etc/bash.bashrc, not /etc/profile.d. Without this hook, the `nvm` shell
# function isn't defined in those shells even though `node` / `npm` work via
# the /usr/local/bin symlinks below. Idempotent guard so re-running the
# feature install doesn't duplicate the block.
if [ ! -f /etc/bash.bashrc ] || ! grep -q 'nvm-feature-hook' /etc/bash.bashrc; then
  cat >>/etc/bash.bashrc <<'EOF'

# nvm-feature-hook: sourced by non-login interactive bash shells.
if [ -z "${NVM_DIR:-}" ] && [ -s /etc/profile.d/nvm.sh ]; then
  . /etc/profile.d/nvm.sh
fi
EOF
fi

# Same for zsh if the distro ships /etc/zsh/zshrc.
if [ -f /etc/zsh/zshrc ] && ! grep -q 'nvm-feature-hook' /etc/zsh/zshrc; then
  cat >>/etc/zsh/zshrc <<'EOF'

# nvm-feature-hook: sourced by interactive zsh shells.
if [ -z "${NVM_DIR:-}" ] && [ -s /etc/profile.d/nvm.sh ]; then
  . /etc/profile.d/nvm.sh
fi
EOF
fi

if [ "$NODE_VERSION" != "none" ]; then
  if [ "$NODE_VERSION" = "lts" ]; then
    NVM_INSTALL_ARG="--lts"
    NVM_ALIAS_TARGET="lts/*"
  else
    NVM_INSTALL_ARG="$NODE_VERSION"
    NVM_ALIAS_TARGET="$NODE_VERSION"
  fi

  # shellcheck disable=SC1091
  . "$NVM_DIR/nvm.sh"
  # shellcheck disable=SC2086
  nvm install $NVM_INSTALL_ARG
  nvm alias default "$NVM_ALIAS_TARGET"

  NODE_BIN_DIR="$(dirname "$(nvm which default)")"
  for bin in node npm npx corepack; do
    [ -x "$NODE_BIN_DIR/$bin" ] || continue
    ln -sf "$NODE_BIN_DIR/$bin" "/usr/local/bin/$bin"
  done
fi

chown -R "$USER_NAME:$USER_GROUP" "$NVM_DIR"
