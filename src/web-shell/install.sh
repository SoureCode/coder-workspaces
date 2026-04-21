#!/usr/bin/env bash
# web-shell feature installer.
# https://github.com/SoureCode/web-shell
#
# Installs the release tarball globally via npm against the Node toolchain
# provided by the `nvm` feature (required via `dependsOn`). The binary ends up
# inside the nvm prefix, so we also symlink it into /usr/local/bin for a stable
# path that systemd, sudo, and non-login shells can resolve without sourcing
# nvm.
#
# Supervision: a real systemd unit if PID 1 is systemd (sysbox workspaces), a
# /etc/profile.d login-shell fallback otherwise. Starting is never done here —
# systemd isn't up during image build, and fallback starts happen on user
# login.
set -e

WS_VERSION_OPT="${VERSION:-latest}"
WS_PORT="${PORT:-4000}"
WS_HOST="${HOST:-127.0.0.1}"
WS_AUTH_TOKEN="${AUTHTOKEN:-}"

# 1. OS deps: dtach as the detachable session backend, build-essential + python3
# because node-pty compiles native bindings, plus curl/jq for release lookup.
APT_PKGS=""
for pkg in dtach build-essential python3 ca-certificates curl jq; do
  if ! dpkg -s "$pkg" >/dev/null 2>&1; then
    APT_PKGS="$APT_PKGS $pkg"
  fi
done
if [ -n "$APT_PKGS" ]; then
  apt-get update
  # shellcheck disable=SC2086
  apt-get install -y --no-install-recommends $APT_PKGS
  rm -rf /var/lib/apt/lists/*
fi

# 2. Activate nvm so `npm` and `npm config get prefix` resolve against the
# default Node alias the nvm feature set up.
export NVM_DIR="${NVM_DIR:-/usr/local/share/nvm}"
if [ -s "$NVM_DIR/nvm.sh" ]; then
  # shellcheck disable=SC1091
  . "$NVM_DIR/nvm.sh"
  nvm use default >/dev/null
fi

if ! command -v npm >/dev/null 2>&1; then
  echo "web-shell feature: npm not on PATH. Add ghcr.io/sourecode/devcontainer-features/nvm:2 to your features." >&2
  exit 1
fi

# 3. Resolve target version. `latest` → newest tag via GitHub API. Otherwise
# normalize `vX.Y.Z` / `X.Y.Z` → `X.Y.Z`.
if [ "$WS_VERSION_OPT" = "latest" ]; then
  WS_VERSION="$(curl -fsSL https://api.github.com/repos/SoureCode/web-shell/releases/latest | jq -r .tag_name)"
else
  WS_VERSION="$WS_VERSION_OPT"
fi
WS_VERSION="${WS_VERSION#v}"
if [ -z "$WS_VERSION" ] || [ "$WS_VERSION" = "null" ]; then
  echo "web-shell feature: failed to resolve release version (got '$WS_VERSION_OPT')." >&2
  exit 1
fi

# 4. Download + global install.
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT
TARBALL_URL="https://github.com/SoureCode/web-shell/releases/download/v${WS_VERSION}/web-shell-${WS_VERSION}.tgz"
curl -fsSL -o "$TMPDIR/web-shell.tgz" "$TARBALL_URL"

npm install -g "$TMPDIR/web-shell.tgz"

# 5. Stable symlink at /usr/local/bin/web-shell — the nvm prefix isn't on the
# systemd service PATH.
NPM_PREFIX="$(npm config get prefix)"
WS_BIN="$NPM_PREFIX/bin/web-shell"
if [ ! -x "$WS_BIN" ]; then
  echo "web-shell feature: $WS_BIN missing after npm install." >&2
  exit 1
fi
if [ "$WS_BIN" != "/usr/local/bin/web-shell" ]; then
  ln -sf "$WS_BIN" /usr/local/bin/web-shell
fi

# 6. Systemd unit. We always write it — even when systemd isn't PID 1 right
# now, a later rebase onto a systemd base won't need to reinstall.
install -d -m 0755 /etc/systemd/system
cat >/etc/systemd/system/web-shell.service <<EOF
[Unit]
Description=web-shell
After=network.target

[Service]
Type=simple
Environment=HOST=${WS_HOST}
Environment=PORT=${WS_PORT}
Environment=AUTH_TOKEN=${WS_AUTH_TOKEN}
ExecStart=/usr/local/bin/web-shell
Restart=on-failure
RestartSec=1

[Install]
WantedBy=multi-user.target
EOF
chmod 0644 /etc/systemd/system/web-shell.service

INIT_COMM="$(ps -p 1 -o comm= 2>/dev/null | tr -d '[:space:]' || true)"
if [ "$INIT_COMM" = "systemd" ]; then
  systemctl daemon-reload
  systemctl enable web-shell.service
else
  if command -v systemctl >/dev/null 2>&1; then
    systemctl enable web-shell.service >/dev/null 2>&1 || true
  fi

  # Login-shell fallback for non-systemd bases. pgrep guard avoids spawning
  # duplicate supervisors on repeat logins. The inner while-loop restarts
  # web-shell if it exits, mirroring `Restart=on-failure`.
  cat >/etc/profile.d/web-shell.sh <<EOF
# web-shell feature fallback: systemd wasn't PID 1 at feature install time,
# so a login-shell supervisor is used instead.
if ! pgrep -u "\$(id -u)" -f '/usr/local/bin/web-shell' >/dev/null 2>&1; then
  HOST='${WS_HOST}' PORT='${WS_PORT}' AUTH_TOKEN='${WS_AUTH_TOKEN}' \\
    nohup sh -c 'while true; do /usr/local/bin/web-shell; sleep 1; done' \\
    > /tmp/web-shell.log 2>&1 &
  disown >/dev/null 2>&1 || true
fi
EOF
  chmod 0644 /etc/profile.d/web-shell.sh

  echo "web-shell feature: PID 1 is '${INIT_COMM:-unknown}' (not systemd). Installed /etc/profile.d/web-shell.sh as a login-shell fallback; use a systemd-enabled base (e.g. Coder + sysbox) for proper supervision." >&2
fi
