#!/usr/bin/env bash
# home-persist feature installer.
#
# Installs the resolver script to /usr/local/bin and creates the manifest
# directory. If the `paths` option is set, writes those paths as a user
# manifest so they get symlinked on create.
set -e

if ! command -v jq >/dev/null 2>&1; then
  apt-get update
  apt-get install -y --no-install-recommends jq ca-certificates
  rm -rf /var/lib/apt/lists/*
fi

mkdir -p /etc/devcontainer-persist.d
install -m 0755 "$(dirname "$0")/resolve.sh" /usr/local/bin/home-persist-resolve

# Feature options are exposed as uppercased env vars. `paths` → `$PATHS`
# (comma-separated; the dev container spec doesn't support array options).
raw_paths="${PATHS:-}"
if [ -n "$raw_paths" ]; then
  json_paths='[]'
  IFS=',' read -ra parts <<<"$raw_paths"
  for p in "${parts[@]}"; do
    # trim whitespace
    p="${p#"${p%%[![:space:]]*}"}"
    p="${p%"${p##*[![:space:]]}"}"
    [ -z "$p" ] && continue
    json_paths=$(jq -c --arg p "$p" '. + [$p]' <<<"$json_paths")
  done
  if [ "$json_paths" != "[]" ]; then
    jq -n --argjson paths "$json_paths" \
      '{source:"user", paths:$paths}' \
      > /etc/devcontainer-persist.d/user.json
  fi
fi
