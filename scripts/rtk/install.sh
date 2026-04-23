#!/usr/bin/env bash
# rtk installer.
# https://github.com/rtk-ai/rtk
#
# Our workspaces mount $HOME as a named volume (see docs/persistence.md),
# so anything written to the user's home at build time is hidden on runs
# where the volume already has contents. Install the binary system-wide to
# /usr/local/bin, and defer the `rtk init` auto-patch to a post-create hook
# (run via coder_script at workspace start) so it runs against the real home.
set -e

if ! command -v curl >/dev/null 2>&1; then
  apt-get update
  apt-get install -y --no-install-recommends curl ca-certificates
  rm -rf /var/lib/apt/lists/*
fi

curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh |
  RTK_INSTALL_DIR=/usr/local/bin sh

if [ ! -x /usr/local/bin/rtk ]; then
  echo "rtk: expected /usr/local/bin/rtk after install, but it was not found." >&2
  exit 1
fi

mkdir -p /usr/local/share/rtk
cat >/usr/local/share/rtk/post-create.sh <<'EOF'
#!/usr/bin/env bash
# Runs as the remote user via a coder_script at workspace start.
set -e

if ! command -v claude >/dev/null 2>&1; then
  echo "rtk: claude CLI not on PATH, skipping auto-patch. Claude Code must be installed in the workspace image." >&2
  exit 0
fi

mkdir -p "$HOME/.claude"
rtk init -g --auto-patch
EOF
chmod 0755 /usr/local/share/rtk/post-create.sh
