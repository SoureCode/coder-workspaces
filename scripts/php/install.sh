#!/usr/bin/env bash
# PHP installer. Runs as root. Adds Sury's PHP repo (packages.sury.org/php),
# installs the default version with a dev-friendly extension set, and drops
# /usr/local/bin/pvm — a user-level switcher for swapping active PHP versions
# via symlinks under $HOME/.local/bin (no sudo needed to switch).
# `pvm install <ver>` adds more versions from Sury on demand.
# https://deb.sury.org/
set -e

PHP_DEFAULT_VERSION="${VERSION:-8.5}"
# Extensions installed for every version (Sury naming, prefixed at use-site).
# `common` pulls pdo/phar; `mysql`/`pgsql`/`sqlite3` include their pdo drivers.
PHP_EXT_SET="cli common curl mbstring xml intl zip gd bcmath opcache mysql pgsql sqlite3 redis xdebug"

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://packages.sury.org/php/apt.gpg \
  | gpg --dearmor -o /etc/apt/keyrings/sury-php.gpg
chmod a+r /etc/apt/keyrings/sury-php.gpg
echo "deb [signed-by=/etc/apt/keyrings/sury-php.gpg] https://packages.sury.org/php/ $(. /etc/os-release && echo $VERSION_CODENAME) main" \
  > /etc/apt/sources.list.d/sury-php.list

pkgs=""
for ext in $PHP_EXT_SET; do
  pkgs="$pkgs php${PHP_DEFAULT_VERSION}-${ext}"
done

apt-get update
# shellcheck disable=SC2086
apt-get install -y --no-install-recommends --no-install-suggests $pkgs
rm -rf /var/lib/apt/lists/*

# pvm — user-level PHP version switcher. Lives next to this installer; see
# scripts/php/pvm for the script body.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
install -m 0755 "$script_dir/pvm" /usr/local/bin/pvm

if ! command -v php >/dev/null 2>&1; then
  echo "php: /usr/bin/php not on PATH after install." >&2
  exit 1
fi
