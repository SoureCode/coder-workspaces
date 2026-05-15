#!/bin/bash
# Container entrypoint. Runs as root before systemd (PID 1) starts.
#
# Fresh Docker named volumes mount as root:root the first time they're
# attached, even though the underlying image path is owned by the workspace
# user. Claim the mountpoints here so coder-agent.service — which starts
# later under systemd — sees correctly-owned mounts. Idempotent: chown/chmod
# are no-ops when values already match.
set -eo pipefail

USERNAME="${USERNAME:-coder}"

for path in "/home/${USERNAME}/projects" /mnt/home-persist; do
  [ -d "$path" ] || continue
  chown "${USERNAME}:${USERNAME}" "$path"
  chmod 0755 "$path"
done

# Deployment-wide share: every workspace runs as the same uid, so full 0777
# gives all workspaces unrestricted read/write/delete on everything inside.
if [ -d /mnt/shared ]; then
  chown "${USERNAME}:${USERNAME}" /mnt/shared
  chmod 0777 /mnt/shared
fi

exec "$@"
