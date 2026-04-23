#!/usr/bin/env bash
# home-persist installer.
#
# Installs the resolver script to /usr/local/bin and creates the manifest
# directory. Per-tool manifests land in /etc/home-persist.d/*.json at image
# build time; the workspace template optionally drops
# /etc/home-persist.d/user.json at agent start from the home_persist_paths
# Coder parameter.
set -e

if ! command -v jq >/dev/null 2>&1; then
  apt-get update
  apt-get install -y --no-install-recommends jq ca-certificates
  rm -rf /var/lib/apt/lists/*
fi

mkdir -p /etc/home-persist.d
install -m 0755 "$(dirname "$0")/resolve.sh" /usr/local/bin/home-persist-resolve
