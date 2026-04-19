# SoureCode Devcontainer Features

A small collection of [Dev Container Features](https://containers.dev/implementors/features/)
for Claude Code and friends, plus a lightweight `nvm` feature.

Published to GHCR under the `sourecode/devcontainer-features` namespace.

This repo also contains the Coder workspace template
([`Dockerfile.workspace`](Dockerfile.workspace) and [`main.tf`](main.tf))
that hosts the devcontainers these features get installed into — see
[Coder workspace template](#coder-workspace-template).

## Features

| Feature | OCI reference | Summary |
|---|---|---|
| `claude-code` | `ghcr.io/sourecode/devcontainer-features/claude-code:2` | Installs the Claude Code CLI via the official native installer into `/usr/local/bin`, so the binary survives home-directory volume mounts. Requires Node.js — automatically pulls in the `nvm` feature via `dependsOn`. |
| `rtk` | `ghcr.io/sourecode/devcontainer-features/rtk:2` | Installs [rtk](https://github.com/rtk-ai/rtk), an LLM token-reducing CLI proxy, into `/usr/local/bin`. Auto-patches Claude Code via `postCreateCommand` so the hook is written against the mounted home, not the image. |
| `context-mode` | `ghcr.io/sourecode/devcontainer-features/context-mode:2` | Installs the [`context-mode`](https://github.com/mksglu/context-mode) Claude Code plugin via `postCreateCommand`, so the plugin lands in the mounted `~/.claude` rather than the image. |
| `nvm` | `ghcr.io/sourecode/devcontainer-features/nvm:2` | Installs [nvm](https://github.com/nvm-sh/nvm) system-wide at `/usr/local/share/nvm` and optionally a Node version (defaults to LTS), with `node`/`npm`/`npx` symlinked into `/usr/local/bin`. No yarn. |

All binaries land in `/usr/local/bin` (or `/usr/local/share/...`) rather than the user's home, so they survive the shared home-volume pattern described in [`docs/persistence.md`](docs/persistence.md). `rtk` and `context-mode` declare `installsAfter` for both `ghcr.io/sourecode/devcontainer-features/claude-code` and `ghcr.io/anthropics/devcontainer-features/claude-code`, so the runtime orders them after whichever claude-code feature is present.

## Using the features

Add them to any `.devcontainer/devcontainer.json`, on top of whatever base
image you already use:

```jsonc
{
  "image": "debian:trixie-slim",
  "features": {
    "ghcr.io/sourecode/devcontainer-features/claude-code:2": {},
    "ghcr.io/sourecode/devcontainer-features/rtk:2": {
      "autoPatchClaude": true
    },
    "ghcr.io/sourecode/devcontainer-features/context-mode:2": {}
  }
}
```

Features run inside the image during build (as root) and install system-wide
under `/usr/local/`. After rebuild, the tools are available on every user's
`PATH` with no home-directory footprint.

### Feature options

#### `claude-code`

No options. Always installs the latest release. Declares `dependsOn` for
`ghcr.io/sourecode/devcontainer-features/nvm:2`, so adding `claude-code` to a
devcontainer automatically pulls in `nvm` (and therefore Node.js) even if you
don't list `nvm` yourself.

#### `rtk`

| Option | Type | Default | Purpose |
|---|---|---|---|
| `autoPatchClaude` | boolean | `true` | Run `rtk init -g --auto-patch` to wire rtk's hook into Claude Code. No-op if the `claude` CLI is not on the user's PATH. |

#### `context-mode`

No options. Runs via `postCreateCommand`, so it no-ops (with a warning) if
the `claude` CLI isn't on PATH when the container is created — add a
claude-code feature as well. `installsAfter` handles ordering for either
`sourecode/` or `anthropics/` claude-code.

#### `nvm`

| Option | Type | Default | Purpose |
|---|---|---|---|
| `version` | string | `0.40.4` | nvm release tag to install (without the leading `v`). |
| `node` | string | `lts` | Node version to install via nvm. `lts` uses `nvm install --lts`. `none` skips node install. Anything else is passed as-is to `nvm install`. |

### Persisting Claude Code state

Claude login (`~/.claude/.credentials.json`) and chat history (`projects/`,
`sessions/`, `session-env/`) live in the user's home. Persist them by mounting
`$HOME` as a named volume — see [`docs/persistence.md`](docs/persistence.md)
for the shared-home pattern we use across every devcontainer.

## Coder workspace template

`Dockerfile.workspace` builds a Coder workspace image and `main.tf` is the
Coder template that launches it. The workspace container runs its own
`dockerd` under the [sysbox](https://github.com/nestybox/sysbox) runtime
(`runtime = "sysbox-runc"` in `main.tf`), so `@devcontainers/cli` inside the
workspace talks to a local daemon and bind-mount paths resolve against the
same filesystem the daemon sees.

### Architecture

```
 host docker daemon
 └── workspace container  (sourecode/coder-workspace:latest, runtime=sysbox-runc)
     ├── systemd (PID 1)
     ├── dockerd
     ├── coder-agent.service          (main agent)
     └── @devcontainers/cli up
         └── devcontainer container(s)   (compose, features, lifecycle all work)
             └── coder sub-agent         (runs code-server / jetbrains here)
```

Editors run **inside the devcontainer** via Coder's Dev Containers integration
(`coder_devcontainer.subagent_id`). When you click "Open in code-server" in the
Coder UI, you land in the devcontainer's filesystem with its tools, not the
outer workspace.

One extra container over plain Coder workspaces. No DooD path translation.

### Template files

- `Dockerfile.workspace` — builds the workspace image. Ubuntu + systemd +
  docker-ce + Node LTS + `@devcontainers/cli` + a `coder` user at UID 1000.
- `main.tf` — Coder template. Launches the workspace container under
  `runtime = "sysbox-runc"`, injects `CODER_AGENT_TOKEN` via env, and uploads
  the agent init script to `/etc/coder/agent-init.sh`. The
  `coder-agent.service` systemd unit (baked into the image, see
  `Dockerfile.workspace`) runs that script on boot.

### Prerequisites (on the Docker host)

1. Linux kernel >= 5.12 (>= 6.3 ideal, avoids shiftfs entirely)
2. Native Docker (not the snap) at `/usr/bin/docker`
3. Sysbox installed (see below)
4. Your existing Coder server (this template was developed against a
   docker-compose-deployed Coder)

### Install sysbox

Zero-container-deletion install, tolerates a single `dockerd` restart.

```bash
# 1. pre-populate /etc/docker/daemon.json so sysbox's post-install step
#    doesn't need to touch the network config itself
sudo tee /etc/docker/daemon.json >/dev/null <<'JSON'
{
  "bip": "172.24.0.1/16",
  "default-address-pools": [
    { "base": "172.31.0.0/16", "size": 24 }
  ]
}
JSON

# Pick CIDRs free of your existing networks:
#   docker network inspect $(docker network ls -q) | grep -i subnet

# 2. one controlled restart so dockerd loads the keys
sudo systemctl restart docker

# 3. install sysbox (Ubuntu/Debian amd64)
wget https://downloads.nestybox.com/sysbox/releases/v0.7.0/sysbox-ce_0.7.0-0.linux_amd64.deb
sudo apt-get install -y jq fuse3 ./sysbox-ce_0.7.0-0.linux_amd64.deb

# 4. verify
docker info | grep -i runtime                # should list sysbox-runc
systemctl status sysbox --no-pager
```

Smoke test that nested Docker works under sysbox:

```bash
CID=$(docker run -d --rm --runtime=sysbox-runc nestybox/ubuntu-noble-systemd-docker)
sleep 15
docker exec "$CID" docker run --rm hello-world   # should print the hello-world greeting
docker stop "$CID"
```

### Build the workspace image

```bash
docker build -f Dockerfile.workspace -t sourecode/coder-workspace:latest .
```

The image must exist in the host's local image store (or in a registry the
host can pull from). It is referenced by `var.workspace_image` in `main.tf`.

### Push the template to Coder

If your Coder runs inside a docker-compose stack and you prefer not to install
`coder` on the host, use the CLI that's baked into the Coder server image:

```bash
# copy the template files into the Coder container
docker exec coder-coder-1 mkdir -p /tmp/tpl
docker cp ./main.tf              coder-coder-1:/tmp/tpl/main.tf
docker cp ./Dockerfile.workspace coder-coder-1:/tmp/tpl/Dockerfile.workspace

# login once
docker exec -it coder-coder-1 /opt/coder login http://localhost:7080

# push
docker exec -it coder-coder-1 /opt/coder templates push coder-template -d /tmp/tpl --yes
```

Or install the `coder` CLI locally and push from the repo dir directly.

#### Important: template variables

If you push a newer version of the template but workspaces still launch from
an old image, check **Templates → Settings → Variables** in the Coder UI.
A persisted override for `workspace_image` wins over the `default` in `main.tf`
across version bumps. Clear it or set it to `sourecode/coder-workspace:latest`.

### Create / update workspaces

A workspace pinned to an older template version does not auto-upgrade. After
pushing a new version, either:

- Click **Update** on the workspace in the UI, or
- `coder update <workspace-name>` (from wherever you have the CLI)

### Troubleshooting

- **"Agent is taking longer than expected to connect"** — the workspace
  container exited instead of running systemd. Check:
  ```bash
  CID=$(docker ps -a --filter "name=coder-" -q | head -1)
  docker inspect "$CID" --format '{{.HostConfig.Runtime}} {{.Config.Image}} {{.State.Status}}'
  docker logs "$CID" | tail -50
  ```
  Runtime must be `sysbox-runc` (hardcoded in `main.tf`); image should match
  whatever `var.workspace_image` resolves to (default
  `sourecode/coder-workspace:latest`). If either is wrong, fix the template /
  variable override and recreate.

- **Agent up but nothing connects** — inspect systemd and the agent unit:
  ```bash
  docker exec "$CID" systemctl is-system-running
  docker exec "$CID" systemctl status docker coder-agent --no-pager
  docker exec "$CID" journalctl -u coder-agent --no-pager -n 100
  docker exec "$CID" ls -la /etc/coder/           # expect agent-init.sh present and executable
  docker exec "$CID" bash -lc "tr '\0' '\n' < /proc/1/environ | grep CODER_AGENT_TOKEN"
  ```

- **Inner `@devcontainers/cli up` hangs / errors** — run it by hand inside the
  workspace as the `coder` user to see the real output:
  ```bash
  docker exec -u coder -it "$CID" bash -lc "cd ~/<repo> && devcontainer up --workspace-folder ."
  ```

### Why this shape

`@devcontainers/cli` assumes the CLI and the Docker daemon share a filesystem.
When Coder launches a workspace container and mounts the host socket in, the
CLI (inside the workspace) and the daemon (on the host) see different
filesystems — every bind-mount path the CLI emits is wrong from the daemon's
point of view. That's the root cause of the
`bind source path does not exist` failures.

The principled fixes are: path alignment (fragile), DinD (insecure),
sysbox (safe DinD), envbuilder (collapse into one container), or CI pre-build
(move work out of runtime). This template uses sysbox so the workspace's own
`dockerd` runs safely inside it, paths resolve naturally, and compose-based
devcontainers work unchanged.

## Developing on this repo

### Repository layout

```
.github/workflows/
  publish-features.yml            # publishes every src/<id>/ to GHCR
src/
  claude-code/
    devcontainer-feature.json
    install.sh
  context-mode/
    devcontainer-feature.json
    install.sh
  nvm/
    devcontainer-feature.json
    install.sh
  rtk/
    devcontainer-feature.json
    install.sh
docs/
  migration-guide.md
  persistence.md
Dockerfile.workspace              # Coder workspace image (Ubuntu + systemd + dockerd + @devcontainers/cli)
main.tf                           # Coder template that launches the workspace under sysbox-runc
```

Each feature directory follows the [Dev Container Features spec](https://containers.dev/implementors/features/):
a `devcontainer-feature.json` with metadata and `options`, plus an `install.sh`
that runs as `root` inside the container during the build.

### Writing an install.sh

- `install.sh` starts as `root`. **Prefer system-wide install paths**
  (`/usr/local/bin`, `/usr/local/share/<id>`, `/etc/profile.d`) over anything
  under the remote user's home. The shared-home volume pattern
  ([`docs/persistence.md`](docs/persistence.md)) means writes into
  `/home/<user>` at build time only appear on first-create and then get
  shadowed by the named volume on every subsequent run.
- If a tool's upstream installer insists on writing to `$HOME`, run it under
  a scratch `HOME` (`mktemp -d`) and relocate the resulting binary to
  `/usr/local/bin` (see `src/claude-code/install.sh`). If the tool supports
  an override env var (e.g. `RTK_INSTALL_DIR`), pass it directly.
- For anything that genuinely needs to live in the user's real home
  (credentials, plugin state, shell-rc tweaks), emit a script to
  `/usr/local/share/<id>/post-create.sh` and wire it via `postCreateCommand`
  in `devcontainer-feature.json` so it runs against the mounted home, not
  the image.
- Feature options are exposed as **uppercased** environment variables (e.g.
  option `autoPatchClaude` → `$AUTOPATCHCLAUDE`). Always apply a default:
  `"${FOO:-true}"`.
- The working directory when `install.sh` runs is the extracted feature folder,
  so sibling files are accessible via `"$(dirname "$0")/..."`.
- Don't assume the base image has any particular tools — install `curl`,
  `ca-certificates`, etc. from `apt-get` if absent. Keep installs idempotent
  where reasonable.
- Use `installsAfter` for soft ordering (e.g. `rtk` lists both the `sourecode`
  and `anthropics` claude-code IDs), and `dependsOn` for hard requirements
  that should auto-pull another feature (e.g. `claude-code` → `nvm`).

### Testing a feature locally

Using the [`@devcontainers/cli`](https://github.com/devcontainers/cli):

```sh
npm i -g @devcontainers/cli

# Test a feature in isolation against a chosen base image:
devcontainer features test \
  --features rtk \
  --base-image debian:trixie-slim \
  .
```

### Adding a new feature

1. `mkdir -p src/<id>`
2. Write `src/<id>/devcontainer-feature.json` with `id`, `version`, `name`,
   `description`, `options`, and optional `installsAfter`.
3. Write `src/<id>/install.sh` (make it executable: `chmod +x install.sh`).
4. Bump the `version` for every change (`MAJOR.MINOR.PATCH`). The publish
   workflow pushes each declared version plus rolling `MAJOR`, `MAJOR.MINOR`,
   and `latest` tags.
5. Commit to `master` — the `Publish Features` workflow runs on push and pushes
   to `ghcr.io/sourecode/devcontainer-features/<id>:<tags>`.

### Publishing

The `Publish Features` workflow (`.github/workflows/publish-features.yml`)
uses the official `devcontainers/action@v1` with `publish-features: true`
and targets GHCR:

- `oci-registry: ghcr.io`
- `features-namespace: sourecode/devcontainer-features`

GHCR supports nested paths natively, so each feature publishes to
`ghcr.io/sourecode/devcontainer-features/<feature-id>`, and the collection
metadata publishes cleanly at the namespace root — unlike Docker Hub, which
rejects artifacts at the namespace level.

Authentication uses the built-in `GITHUB_TOKEN` (with `packages: write`), so
there are no additional repository secrets to manage. The packages published
this way attach to the repo on GitHub Packages; to make them public, set the
package visibility to Public in the package settings.

The workflow triggers on pushes to `master` that touch `src/**` or the workflow
file, and can also be run manually via **Run workflow** in the Actions tab.

### Bumping versions

Update `version` in `devcontainer-feature.json`. Each push that lands in `master`
publishes:

- `ghcr.io/sourecode/devcontainer-features/<id>:<MAJOR>.<MINOR>.<PATCH>`
- `ghcr.io/sourecode/devcontainer-features/<id>:<MAJOR>.<MINOR>`
- `ghcr.io/sourecode/devcontainer-features/<id>:<MAJOR>`
- `ghcr.io/sourecode/devcontainer-features/<id>:latest`

## License

MIT — see [`LICENSE`](LICENSE).
