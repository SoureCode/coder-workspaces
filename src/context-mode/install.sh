#!/usr/bin/env bash
# context-mode Claude Code plugin installer.
# https://github.com/mksglu/context-mode
#
# `claude plugin install` writes to ~/.claude/plugins, which lives on the
# volume-mounted home. Running it at build time only works for the very
# first devcontainer create (during volume seeding) and is invisible on
# every subsequent run. Defer the install to postCreateCommand so it runs
# against the real mounted home every time.
set -e

if ! command -v git >/dev/null 2>&1; then
  apt-get update
  apt-get install -y --no-install-recommends git ca-certificates
  rm -rf /var/lib/apt/lists/*
fi

mkdir -p /usr/local/share/context-mode
cat >/usr/local/share/context-mode/post-create.sh <<'EOF'
#!/usr/bin/env bash
# Written by the context-mode devcontainer feature at build time.
# Runs as the remote user via postCreateCommand so the plugin lands in
# the mounted ~/.claude, not the image.
set -e

if ! command -v claude >/dev/null 2>&1; then
  echo "context-mode feature: claude CLI not on PATH, skipping plugin install. Install a claude-code feature (e.g. ghcr.io/sourecode/devcontainer-features/claude-code) to enable it." >&2
  exit 0
fi

mkdir -p "$HOME/.claude"

# Both commands are idempotent on re-run: `marketplace add` is a no-op if the
# marketplace is already registered, and `plugin install` short-circuits if
# the plugin is already installed at the same version.
claude plugin marketplace add mksglu/context-mode
claude plugin install context-mode@context-mode
EOF
chmod 0755 /usr/local/share/context-mode/post-create.sh
