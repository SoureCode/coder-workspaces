#!/usr/bin/env bash
# context-mode Claude Code plugin installer.
# https://github.com/mksglu/context-mode
#
# `claude plugin install` writes to ~/.claude/plugins. When home-persist is
# active, ~/.claude is a symlink into /mnt/home-persist and the symlink is
# created at workspace start by home-persist-resolve — which runs after this
# install.sh. Defer the plugin install to workspace start (via coder_script)
# so it writes through the symlink into the persistent volume on every start.
set -eo pipefail

mkdir -p /usr/local/share/context-mode
cat >/usr/local/share/context-mode/post-create.sh <<'EOF'
#!/usr/bin/env bash
# Written at image build time. Runs as the remote user via a coder_script at
# workspace start, after home-persist-resolve has symlinked ~/.claude into
# the persistence volume.
set -eo pipefail

if ! command -v claude >/dev/null 2>&1; then
  echo "context-mode: claude CLI not on PATH, skipping plugin install. Claude Code must be installed in the workspace image." >&2
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
