#!/usr/bin/env bash
# GitHub CLI installer. Runs as root. Adds cli.github.com's apt repo and
# installs gh system-wide — the upstream-recommended path on Debian.
# https://github.com/cli/cli/blob/trunk/docs/install_linux.md
set -e

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  -o /etc/apt/keyrings/githubcli-archive-keyring.gpg
chmod a+r /etc/apt/keyrings/githubcli-archive-keyring.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
  > /etc/apt/sources.list.d/github-cli.list

apt-get update
apt-get install -y --no-install-recommends --no-install-suggests gh
rm -rf /var/lib/apt/lists/*

# Persist gh config + extensions across workspace rebuilds. ~/.config/gh
# holds config.yml and hosts.yml (auth tokens); ~/.local/share/gh holds
# anything installed via `gh extension install`.
mkdir -p /etc/home-persist.d
cat > /etc/home-persist.d/gh.json <<'EOF'
{
  "source": "gh",
  "paths": [".config/gh/", ".local/share/gh/"]
}
EOF
