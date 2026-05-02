#!/usr/bin/env bash
set -eo pipefail

mkdir -p /etc/home-persist.d

tee /etc/home-persist.d/jetbrains.json >/dev/null <<'EOF'
{
  "source": "jetbrains",
  "scope": "owner",
  "paths": [
    ".config/JetBrains/",
    ".local/share/JetBrains/",
    ".java/.userPrefs/jetbrains/"
  ]
}
EOF
