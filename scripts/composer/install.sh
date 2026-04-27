#!/usr/bin/env bash
# Composer installer. Runs as the workspace user — drops the phar into
# $HOME/.local/bin (on PATH via pipx ensurepath in base). Verified against
# the SHA-384 that the official Composer installer script publishes.
# https://getcomposer.org/
set -eo pipefail

COMPOSER_VERSION="${COMPOSER_VERSION:-}"
INSTALL_DIR="$HOME/.local/bin"
mkdir -p "$INSTALL_DIR"

if ! command -v php >/dev/null 2>&1; then
  echo "composer: php not on PATH. scripts/php/install.sh must run before scripts/composer/install.sh." >&2
  exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

curl -fsSL https://getcomposer.org/installer -o "$tmp/composer-setup.php"
expected=$(curl -fsSL https://composer.github.io/installer.sig)
actual=$(php -r "echo hash_file('sha384', '$tmp/composer-setup.php');")
if [ "$expected" != "$actual" ]; then
  echo "composer: installer signature mismatch (expected=$expected actual=$actual)." >&2
  exit 1
fi

args=(--quiet --install-dir="$INSTALL_DIR" --filename=composer)
[ -n "$COMPOSER_VERSION" ] && args+=(--version="$COMPOSER_VERSION")
php "$tmp/composer-setup.php" "${args[@]}"

if ! "$INSTALL_DIR/composer" --version >/dev/null 2>&1; then
  echo "composer: binary not runnable after install." >&2
  exit 1
fi

mkdir -p "$HOME/.local/share/bash-completion/completions"
"$INSTALL_DIR/composer" completion bash > "$HOME/.local/share/bash-completion/completions/composer"
