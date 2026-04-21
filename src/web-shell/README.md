# web-shell devcontainer feature

Installs [web-shell](https://github.com/SoureCode/web-shell) — a persistent
browser terminal backed by `tmux` — inside a devcontainer and registers it
as a Coder workspace app.

`web-shell` is a Node.js + xterm.js service. Every session is a `tmux` session
on the server, so shells survive Node restarts. This feature:

- Installs OS deps (`tmux`, `build-essential`, `python3`, `curl`, `jq`).
- Downloads the release tarball from `SoureCode/web-shell` and `npm install -g`s
  it against the Node toolchain provided by the
  [`nvm`](../nvm) feature (`dependsOn`).
- Symlinks the binary into `/usr/local/bin/web-shell`.
- Writes and enables a systemd unit at `/etc/systemd/system/web-shell.service`.
  Starting is left to container boot — systemd isn't running during image
  build.
- Falls back to a `/etc/profile.d/web-shell.sh` login-shell supervisor when
  PID 1 is not `systemd`.

## OCI reference

```
ghcr.io/sourecode/devcontainer-features/web-shell:1
```

## Options

| Option | Type | Default | Purpose |
|---|---|---|---|
| `version` | string | `latest` | Release to install. `latest` resolves via the GitHub API; otherwise `X.Y.Z` or `vX.Y.Z`. |
| `port` | string | `4000` | Port `web-shell` binds on. Baked into the systemd unit as `$PORT`. |
| `host` | string | `127.0.0.1` | Bind address. Baked into the systemd unit as `$HOST`. Use `0.0.0.0` to listen on all interfaces. |
| `authToken` | string | `""` | Bearer token required on incoming connections. Baked into the systemd unit as `$AUTH_TOKEN`. Empty disables auth. |

## Usage

```jsonc
{
  "image": "debian:trixie-slim",
  "features": {
    "ghcr.io/sourecode/devcontainer-features/nvm:2": {},
    "ghcr.io/sourecode/devcontainer-features/web-shell:1": {}
  }
}
```

`nvm` is pulled in automatically via `dependsOn`, so listing it is optional.
To expose the service to the workspace's public IP instead of loopback:

```jsonc
"ghcr.io/sourecode/devcontainer-features/web-shell:1": {
  "host": "0.0.0.0",
  "port": "4000",
  "authToken": "replace-me"
}
```

## Coder workspace app

The feature ships a `customizations.coder.apps` entry so that workspaces
running under Coder's Dev Containers integration (sub-agent) automatically
render a **web-shell** button on the workspace page. The button opens the
terminal in the browser — no manual steps.

The app URL uses `${localEnv:PORT:4000}`, so overriding `PORT` in
`devcontainer.json`'s `containerEnv` (or passing it via the feature option and
also exposing it as env) is picked up by the Coder button. Set `PORT` in both
places when customising.

## Supervision

| PID 1 | What runs |
|---|---|
| `systemd` (Coder + sysbox, systemd-on-boot bases) | `web-shell.service` — started on container boot, restarted on failure. |
| Anything else (plain Docker, host-agent runners) | `/etc/profile.d/web-shell.sh` — spawns a background supervisor on first login per user, guarded by `pgrep` so relogins don't duplicate. Logs go to `/tmp/web-shell.log`. |

The systemd unit is always written, even when the fallback is active, so a
later rebase onto a systemd base just works without reinstalling.

## Checks

After the container is up:

```bash
which web-shell                              # /usr/local/bin/web-shell
systemctl is-enabled web-shell.service       # enabled  (on systemd hosts)
curl -fsS http://127.0.0.1:4000/api/sessions # health endpoint
```
