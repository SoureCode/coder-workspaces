#!/usr/bin/env bash
# rtk installer. Runs as the workspace user — binary lands in $HOME/.local/bin.
# https://github.com/rtk-ai/rtk
set -e

curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh

if [ ! -x "$HOME/.local/bin/rtk" ]; then
  echo "rtk: expected $HOME/.local/bin/rtk after install, but it was not found." >&2
  exit 1
fi

mkdir -p "$HOME/.local/share/rtk"
cat >"$HOME/.local/share/rtk/post-create.sh" <<'EOF'
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
chmod 0755 "$HOME/.local/share/rtk/post-create.sh"
