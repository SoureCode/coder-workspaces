# SoureCode Coder Workspace Template

A Coder workspace template plus a family of workspace images with pre-installed
dev tooling. Each workspace runs its own `dockerd` under
[sysbox](https://github.com/nestybox/sysbox), so you can build and test your
own `Dockerfile`s, run `docker compose` stacks, etc. inside the workspace.

One container per workspace — no nested devcontainer layer. IDEs (VS Code
Desktop, JetBrains, code-server, web-shell) all attach to the single
workspace agent.

Images are published to GHCR under `ghcr.io/sourecode/coder-workspace`.

## Workspace images

| Tag | Base | Adds |
|---|---|---|
| `base` | `debian:trixie-slim` | systemd + dockerd + `nvm` + `claude-code` + `rtk` + `web-shell` + `home-persist` + `jetbrains` |
| `node` | `:base` | named variant for future Node-specific tooling — currently identical to `base` (Node comes from nvm) |
| `cpp`  | `:base` | `llvm` (clang + toolchain), `cmake`, `sccache`, `/etc/profile.d/llvm-env.sh` exporting `CC`/`CXX` |

Pick the image per workspace via the `workspace_image` parameter when creating
the workspace in Coder.

## Pre-installed tools

| Tool | What it is | Notes |
|---|---|---|
| `claude-code` | Anthropic [Claude Code CLI](https://claude.ai/) | `~/.claude` + `~/.claude.json` persisted via `home-persist` |
| `rtk` | [rtk](https://github.com/rtk-ai/rtk), token-reducing Claude proxy | Auto-patches Claude Code via a post-create hook at workspace start |
| `nvm` | [nvm](https://github.com/nvm-sh/nvm) at `/usr/local/share/nvm` | Default Node = LTS, `node`/`npm`/`npx` in `/usr/local/bin` |
| `web-shell` | [web-shell](https://github.com/SoureCode/web-shell), persistent browser terminal | systemd unit, registered as a Coder app |
| `jetbrains` | JetBrains Gateway remote backend persistence | Headless-only: Toolbox/Gateway runs on the user's local machine, opens a `jetbrains-gateway://` URL that SSHes in and runs `remote-dev-server.sh` here. Declares `~/.cache/JetBrains/`, `~/.config/JetBrains/`, `~/.local/share/JetBrains/`, `~/.java/.userPrefs/jetbrains/` to `home-persist` so the downloaded IDE backend, per-IDE settings, plugins, project indexes and JetProfile login survive workspace restarts. |
| `home-persist` | Manifest-driven `$HOME` persistence | Reads `/etc/home-persist.d/*.json`, symlinks declared paths under `/mnt/home-persist` (per-owner volume). Add extra per-workspace paths via the `home_persist_paths` Coder parameter. See [`docs/persistence.md`](docs/persistence.md). |
| `llvm` (cpp) | Clang toolchain via [apt.llvm.org](https://apt.llvm.org/) | `CC=clang`, `CXX=clang++` via `/etc/profile.d/llvm-env.sh` |
| `cmake` (cpp) | CMake from [Kitware's GitHub releases](https://cmake.org/) | latest by default |
| `sccache` (cpp) | Mozilla [sccache](https://github.com/mozilla/sccache) | musl-linked binary in `/usr/local/bin` |

System-wide install paths (`/usr/local/bin`, `/usr/local/share/<name>`,
`/etc/profile.d`). Per-user state that needs to survive workspace restarts
goes through `home-persist`'s manifest system.

## Architecture

```
 host docker daemon  (sysbox-runc runtime registered)
 └── workspace container (ghcr.io/sourecode/coder-workspace:<tag>)
     ├── systemd (PID 1)
     ├── dockerd (for in-workspace docker build / docker compose)
     └── coder-agent.service (runs /etc/coder/agent-init.sh as `coder`)
```

## Template files

- `main.tf` — Coder template. Launches the workspace container under
  `runtime = "sysbox-runc"`, injects `CODER_AGENT_TOKEN` via env, and uploads
  the agent init script to `/etc/coder/agent-init.sh`. The
  `coder-agent.service` systemd unit (baked into the image) runs that script
  on boot.
- `src/base/Dockerfile` — shared base: Debian trixie + systemd + dockerd +
  `coder` user + dev-kit scripts.
- `src/node/Dockerfile`, `src/cpp/Dockerfile` — stack variants (`FROM :base`).
- `scripts/<name>/install.sh` — bound into each Dockerfile at build time via
  `RUN --mount=type=bind,source=scripts,target=/scripts`, so the source never
  enters a layer in the final image.

## Prerequisites (on the Docker host)

1. Linux kernel >= 5.12 (>= 6.3 ideal, avoids shiftfs entirely)
2. Native Docker (not the snap) at `/usr/bin/docker`
3. Sysbox installed (see below)
4. An existing Coder server (this template was developed against a
   docker-compose-deployed Coder)

## Install sysbox

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

## Build the workspace images

Published automatically by `.github/workflows/publish-workspaces.yml` to
`ghcr.io/<owner>/coder-workspace:<tag>` on every push to `master` that
touches `src/**`, `scripts/**`, or the workflow file. The workflow builds
`base` first, then `node` and `cpp` in parallel (both `FROM :base-<sha>`
pinned to the same commit).

To build locally:

```bash
# base first — the stacks FROM this tag
docker build -f src/base/Dockerfile -t ghcr.io/sourecode/coder-workspace:base .

# stacks
docker build -f src/node/Dockerfile -t ghcr.io/sourecode/coder-workspace:node \
    --build-arg BASE_IMAGE=ghcr.io/sourecode/coder-workspace:base .
docker build -f src/cpp/Dockerfile  -t ghcr.io/sourecode/coder-workspace:cpp \
    --build-arg BASE_IMAGE=ghcr.io/sourecode/coder-workspace:base .
```

## Push the template to Coder

If your Coder runs inside a docker-compose stack and you prefer not to install
`coder` on the host:

```bash
docker exec coder-coder-1 mkdir -p /tmp/tpl
docker cp ./main.tf coder-coder-1:/tmp/tpl/main.tf

docker exec -it coder-coder-1 /opt/coder login http://localhost:7080
docker exec -it coder-coder-1 /opt/coder templates push coder-template -d /tmp/tpl --yes
```

Or install the `coder` CLI locally and push from the repo dir directly.

## Create / update workspaces

A workspace pinned to an older template version does not auto-upgrade. After
pushing a new version, either:

- Click **Update** on the workspace in the UI, or
- `coder update <workspace-name>`

## Troubleshooting

- **"Agent is taking longer than expected to connect"** — the workspace
  container exited instead of running systemd. Check:
  ```bash
  CID=$(docker ps -a --filter "name=coder-" -q | head -1)
  docker inspect "$CID" --format '{{.HostConfig.Runtime}} {{.Config.Image}} {{.State.Status}}'
  docker logs "$CID" | tail -50
  ```
  Runtime must be `sysbox-runc`. Image should match whatever the template's
  `workspace_image` parameter resolved to.

- **Agent up but nothing connects** — inspect systemd and the agent unit:
  ```bash
  docker exec "$CID" systemctl is-system-running
  docker exec "$CID" systemctl status docker coder-agent --no-pager
  docker exec "$CID" journalctl -u coder-agent --no-pager -n 100
  docker exec "$CID" ls -la /etc/coder/      # expect agent-init.sh present + executable
  docker exec "$CID" bash -lc "tr '\0' '\n' < /proc/1/environ | grep CODER_AGENT_TOKEN"
  ```

## Why sysbox

The workspace bakes `dockerd` in so you can `docker build`, `docker compose up`,
or run a project's own Dockerfile straight from inside your workspace without
going through the host daemon. Running an inner dockerd safely inside a
container is exactly what sysbox provides — plain `runc` would require
`--privileged` and you'd still fight shared-kernel artefacts. Sysbox handles
it with proper namespace isolation.

## Developing on this repo

### Repository layout

```
.github/workflows/
  publish-workspaces.yml             # builds & pushes coder-workspace:{base,node,cpp}
docs/
  persistence.md                     # home-persist deep dive
scripts/
  claude-code/install.sh
  cmake/install.sh
  home-persist/{install.sh,resolve.sh}
  llvm/install.sh
  nvm/install.sh
  rtk/install.sh
  sccache/install.sh
  web-shell/install.sh
src/
  base/Dockerfile                    # debian-trixie + systemd + dockerd + dev-kit
  cpp/Dockerfile                     # FROM :base + llvm/cmake/sccache
  node/Dockerfile                    # FROM :base
main.tf                              # Coder template
```

### Writing an install.sh

- `install.sh` starts as `root`. **Prefer system-wide install paths**
  (`/usr/local/bin`, `/usr/local/share/<id>`, `/etc/profile.d`) over anything
  under the remote user's home — `$HOME` is volume-mounted in a running
  workspace, so build-time writes there get shadowed by the volume.
- If a tool's upstream installer insists on writing to `$HOME`, relocate
  the resulting binary to `/usr/local/bin` (see `scripts/claude-code/install.sh`).
  If the tool supports an override env var (e.g. `RTK_INSTALL_DIR`), pass
  it directly.
- For anything that genuinely needs to live in the user's real home
  (credentials, plugin state, shell-rc tweaks), emit a script to
  `/usr/local/share/<id>/post-create.sh` and wire it via a `coder_script` in
  `main.tf` that runs at agent start (see how `rtk` does it).
- If your script writes persistent state under `$HOME`, declare those paths
  by dropping a JSON manifest:

  ```bash
  mkdir -p /etc/home-persist.d
  cat > /etc/home-persist.d/<your-tool>.json <<'EOF'
  { "source": "<your-tool>", "paths": [".your-tool/"] }
  EOF
  ```

  `/usr/local/bin/home-persist-resolve` (run by a `coder_script` at workspace
  start) picks it up and symlinks each path into the persistence volume.
  See [`docs/persistence.md`](docs/persistence.md).
- The target user is `$_REMOTE_USER` (set by the base Dockerfile's `ENV`).
  Scripts read it as `USER_NAME="${_REMOTE_USER:-${USERNAME:-root}}"`.
- Keep installs idempotent. Don't assume base packages — install `curl`,
  `ca-certificates`, `jq`, etc. from `apt-get` if absent.

### Adding a new stack

1. Write `src/<stack>/Dockerfile`:
   ```dockerfile
   # syntax=docker/dockerfile:1
   ARG BASE_IMAGE=ghcr.io/sourecode/coder-workspace:base
   FROM ${BASE_IMAGE}

   SHELL ["/bin/bash", "-o", "pipefail", "-c"]
   ENV DEBIAN_FRONTEND=noninteractive

   RUN --mount=type=bind,source=scripts,target=/scripts \
       for s in <script names>; do \
         bash "/scripts/$s/install.sh"; \
       done
   ```
2. Add `<stack>` to `stacks.strategy.matrix.stack` in
   `.github/workflows/publish-workspaces.yml`.
3. Commit to `master` — the workflow publishes
   `ghcr.io/<owner>/coder-workspace:<stack>` (and `<stack>-<sha>`).
4. Add `<stack>` as an option on the `workspace_image` parameter in `main.tf`.

### Publishing

`.github/workflows/publish-workspaces.yml` builds multi-arch
(`linux/amd64,linux/arm64`) images and pushes to GHCR via the built-in
`GITHUB_TOKEN`. Triggers on `master` pushes touching `src/**`, `scripts/**`,
or the workflow file; also runs on `v*` tag pushes and manual dispatch.

## License

MIT — see [`LICENSE`](LICENSE).
