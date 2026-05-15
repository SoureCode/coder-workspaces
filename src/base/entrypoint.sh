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

# DooD: align the in-image `docker` group GID with the host socket's GID so
# the workspace user (member of `docker` in the image) can talk to the
# bind-mounted host daemon without a chmod 666 on the socket.
if [ -S /host-docker.sock ]; then
  sock_gid=$(stat -c '%g' /host-docker.sock)
  cur_gid=$(getent group docker | cut -d: -f3 || true)
  if [ -n "$sock_gid" ] && [ "$sock_gid" != "$cur_gid" ]; then
    # If another group already owns the target GID, rename it out of the way
    # so groupmod can take it.
    conflict=$(getent group "$sock_gid" | cut -d: -f1 || true)
    if [ -n "$conflict" ] && [ "$conflict" != "docker" ]; then
      groupmod -n "${conflict}-host" "$conflict"
    fi
    groupmod -g "$sock_gid" docker
  fi
fi

exec "$@"
