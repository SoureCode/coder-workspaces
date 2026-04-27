#!/usr/bin/env bash
# PHP installer. Runs as root. Adds Sury's PHP repo (packages.sury.org/php),
# installs the default version with a dev-friendly extension set, and drops
# /usr/local/bin/pvm — a user-level switcher for swapping active PHP versions
# via symlinks under $HOME/.local/bin (no sudo needed to switch).
# `pvm install <ver>` adds more versions from Sury on demand.
# https://deb.sury.org/
set -e

PHP_DEFAULT_VERSION="${PHP_VERSION:-8.5}"
# Extensions installed for every version (Sury naming, prefixed at use-site).
# `common` pulls pdo/phar; `mysql`/`pgsql`/`sqlite3` include their pdo drivers.
PHP_EXT_SET="cli common curl mbstring xml intl zip gd bcmath opcache apcu mysql pgsql sqlite3 redis xdebug"

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://packages.sury.org/php/apt.gpg \
  | gpg --dearmor -o /etc/apt/keyrings/sury-php.gpg
chmod a+r /etc/apt/keyrings/sury-php.gpg
echo "deb [signed-by=/etc/apt/keyrings/sury-php.gpg] https://packages.sury.org/php/ $(. /etc/os-release && echo $VERSION_CODENAME) main" \
  > /etc/apt/sources.list.d/sury-php.list

apt-get update

# Filter to extensions Sury actually packages separately for this minor.
# Some extensions move into -common over time (notably opcache became core
# and is bundled in php8.5-common — no separate php8.5-opcache package).
# Install what exists; skip the rest rather than fail the whole install.
pkgs=""
skipped=""
for ext in $PHP_EXT_SET; do
  p="php${PHP_DEFAULT_VERSION}-${ext}"
  if apt-cache show "$p" >/dev/null 2>&1; then
    pkgs="$pkgs $p"
  else
    skipped="$skipped $ext"
  fi
done
if [ -n "$skipped" ]; then
  echo "php: skipped (bundled into -common or not packaged separately by Sury for ${PHP_DEFAULT_VERSION}):${skipped}" >&2
fi

# shellcheck disable=SC2086
apt-get install -y --no-install-recommends --no-install-suggests $pkgs
rm -rf /var/lib/apt/lists/*

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Workspace overrides (dev php.ini + xdebug tuning). Staged at a known
# path so pvm can reuse them when installing additional PHP versions.
install -m 0755 -d /usr/local/share/php-workspace
install -m 0644 "$script_dir/workspace.ini" /usr/local/share/php-workspace/workspace.ini
install -m 0644 "$script_dir/xdebug.ini"    /usr/local/share/php-workspace/xdebug.ini

# Apply to every SAPI (cli, fpm, apache2, ...) of the default version that
# got installed. 99- prefix so they load last and win over Sury defaults.
# xdebug override only lands where xdebug is actually enabled for the SAPI.
for sapi_dir in /etc/php/"$PHP_DEFAULT_VERSION"/*/conf.d; do
  [ -d "$sapi_dir" ] || continue
  install -m 0644 /usr/local/share/php-workspace/workspace.ini "$sapi_dir/99-workspace.ini"
  if ls "$sapi_dir"/*xdebug.ini >/dev/null 2>&1; then
    install -m 0644 /usr/local/share/php-workspace/xdebug.ini "$sapi_dir/99-xdebug-workspace.ini"
  fi
done

# pvm — user-level PHP version switcher. Lives next to this installer; see
# scripts/php/pvm for the script body.
install -m 0755 "$script_dir/pvm" /usr/local/bin/pvm

if ! command -v php >/dev/null 2>&1; then
  echo "php: /usr/bin/php not on PATH after install." >&2
  exit 1
fi
