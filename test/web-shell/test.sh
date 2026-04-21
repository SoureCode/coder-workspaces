#!/usr/bin/env bash
# Feature tests for web-shell. Run via:
#   devcontainer features test --features web-shell --base-image debian:trixie-slim .
set -e

# shellcheck disable=SC1091
source dev-container-features-test-lib

check "dtach installed"               which dtach
check "web-shell binary in /usr/local/bin" test -x /usr/local/bin/web-shell
check "systemd unit present"          test -f /etc/systemd/system/web-shell.service
check "unit contains PORT env"        grep -q '^Environment=PORT=' /etc/systemd/system/web-shell.service
check "unit contains HOST env"        grep -q '^Environment=HOST=' /etc/systemd/system/web-shell.service
check "unit contains ExecStart"       grep -q '^ExecStart=/usr/local/bin/web-shell' /etc/systemd/system/web-shell.service
# On systemd hosts the unit is enabled; on non-systemd bases a profile.d
# fallback is installed instead. Accept either.
check "supervision wired" bash -c "systemctl is-enabled web-shell.service 2>/dev/null || test -f /etc/profile.d/web-shell.sh"

reportResults
