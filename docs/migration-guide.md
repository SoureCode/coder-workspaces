# Devcontainer Migration Guide

Guide to migrate an existing `.devcontainer/` setup onto the SoureCode
conventions: manifest-driven `$HOME` persistence via the `home-persist`
feature, dynamic user construct, and toolchain installed via features
instead of inline Dockerfile install steps.

## Goals of the migration

1. Per-user state that must survive rebuilds (Claude login, anything else
   explicitly declared) lives in a single per-owner volume at
   `/mnt/home-persist`. The `home-persist` feature symlinks those paths
   from `$HOME` into the volume on every create. Everything else stays
   image-owned and resets on rebuild.
2. The container user / UID / GID is driven by `DEVCONTAINER_*` env vars so
   the same devcontainer works inside Coder (where the outer template sets
   these) and outside (sensible defaults).
3. Toolchain installs (cmake, LLVM, sccache, Claude Code, RTK, …) come from
   published devcontainer features, not inline Dockerfile commands. The
   Dockerfile shrinks to base OS + common utilities + user creation.

## Input state (what you'll typically see)

An existing devcontainer that:

- Runs as `root` or a user named `vscode` / `ubuntu` / whatever the base
  image ships.
- Has a Dockerfile with long inline installs for cmake / LLVM / sccache /
  Claude Code / RTK.
- Uses ephemeral volumes, `${devcontainerId}`-scoped volumes, or a
  whole-`$HOME` bind mount.
- Hard-codes paths like `/root/.claude`, `/root/.cache/sccache`.

## Output state (what you're producing)

### `.devcontainer/devcontainer.json`

```jsonc
{
  "name": "<project-name>",
  "build": {
    "dockerfile": "Dockerfile",
    "args": {
      "USERNAME": "${localEnv:DEVCONTAINER_USERNAME:dev}",
      "USER_UID": "${localEnv:DEVCONTAINER_USER_UID:1000}",
      "USER_GID": "${localEnv:DEVCONTAINER_USER_GID:1000}"
    }
  },
  "remoteUser": "${localEnv:DEVCONTAINER_USERNAME:dev}",
  "containerUser": "${localEnv:DEVCONTAINER_USERNAME:dev}",
  "mounts": [
    "source=/mnt/home-persist,target=/mnt/home-persist,type=bind"
  ],
  "features": {
    "ghcr.io/sourecode/devcontainer-features/home-persist:1": {},
    // pick from the feature reference below
  },
  "customizations": {
    // keep whatever IDE config the project already has
  }
}
```

Rules:

- `name` — keep the project's existing name.
- Mount **source** and **target** are both `/mnt/home-persist`, mount
  **type** is **bind**. That path is the per-owner persistence volume
  mounted into every outer Coder workspace (see `main.tf`'s
  `docker_volume "home_persist"`). Do **not** introduce per-project volume
  names — the whole point is that every project shares one volume per
  owner.
- The `home-persist` feature is required whenever any feature declares a
  persistence manifest (e.g. `claude-code` declares `.claude` and
  `.claude.json`). Without it, the symlinks are never created and state
  resets on rebuild.
- `remoteUser` and `containerUser` both use `${localEnv:DEVCONTAINER_USERNAME:dev}`.
- Do **not** set `CLAUDE_CONFIG_DIR` in `containerEnv` — `home-persist`
  already routes `~/.claude` through the volume.
- `customizations` — preserve whatever the project had (JetBrains backend,
  VS Code settings/extensions, etc.).

### `.devcontainer/Dockerfile`

```dockerfile
FROM <base-image-and-digest>

ARG USERNAME
ARG USER_UID=1000
ARG USER_GID=${USER_UID}

ENV DEBIAN_FRONTEND=noninteractive
ENV DEVCONTAINER=true

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        <base packages the project actually needs> \
        sudo ca-certificates curl git openssh-client && \
    apt-get clean && rm -rf /var/lib/apt/lists/* && \
    userdel -r ubuntu 2>/dev/null || true && \
    groupadd --gid "${USER_GID}" "${USERNAME}" && \
    useradd --uid "${USER_UID}" --gid "${USER_GID}" --create-home --shell /bin/bash "${USERNAME}" && \
    echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/"${USERNAME}" && \
    chmod 0440 /etc/sudoers.d/"${USERNAME}"

# Project-specific env, shell config, workdir, etc. go here.

USER ${USERNAME}
```

Rules:

- Start with the project's existing `FROM`. Keep the digest pin if present.
- Declare `ARG USERNAME` (no default — required from build.args), plus
  `ARG USER_UID=1000` and `ARG USER_GID=${USER_UID}`.
- Create the user in the same `RUN` that does apt installs (fewer layers).
  `userdel -r ubuntu 2>/dev/null || true` covers Ubuntu base images that
  ship a default user. Use soft-fail on non-Ubuntu bases.
- End with `USER ${USERNAME}`.
- **Remove** any inline installs that are now handled by features
  (see next section). Also remove:
  - Manual `.bashrc` history-persistence hacks tied to `/commandhistory` or
    `/root/.bash_history` — `$HOME` is image-owned, bash history resets on
    rebuild unless you add `.bash_history` to a `home-persist` manifest.
  - Hard-coded `CC=clang-22` / `CXX=clang++-22` — the `llvm` feature sets
    these via `containerEnv`.
  - Hard-coded `CLAUDE_CONFIG_DIR` / `SCCACHE_DIR` — `home-persist` routes
    the paths the declared features need.
- Shell-level config (`HISTSIZE`, `PATH` additions, aliases) goes in the
  Dockerfile (via `/etc/bash.bashrc` or similar) since `$HOME` is now
  image-owned and doesn't drift.

## Available features

Reference: `ghcr.io/sourecode/devcontainer-features/<id>:<major-version>`

| Feature | Purpose | Notable options |
|---|---|---|
| `home-persist` | Manifest-driven `$HOME` persistence into `/mnt/home-persist` | `paths` (comma-separated) |
| `cmake` | CMake from Kitware GitHub releases, distro-agnostic | `version` (default `latest`) |
| `llvm` | Clang/LLVM via `apt.llvm.org`. Sets `CC`/`CXX` in containerEnv. | `version` (default `22`), `all` (default `true`) |
| `sccache` | Mozilla sccache from GitHub releases | `version` (default `latest`) |
| `nvm` | NVM + optional Node install | `version`, `node` (default `lts`) |
| `claude-code` | Anthropic Claude Code CLI. Declares `.claude` + `.claude.json` in the home-persist manifest. | — |
| `rtk` | RTK CLI | — |
| `context-mode` | Context-mode integration | — |

### How to decide which features to add

Scan the original Dockerfile for inline installs and map them:

- `apt install cmake` (from any source) → drop, add `cmake` feature.
- `apt.llvm.org/llvm.sh` / `apt install clang` / `apt install clangd` /
  any llvm-* packages → drop, add `llvm` feature (it installs the full
  toolchain with `all: true`).
- `sccache` tarball install → drop, add `sccache` feature.
- `curl .../claude-code install` → drop, add `claude-code` feature.
- `curl .../rtk install` → drop, add `rtk` feature.
- Anything NOT covered by a feature stays in the Dockerfile.

Typical `features` block for a C++ project:

```jsonc
"features": {
  "ghcr.io/sourecode/devcontainer-features/cmake:1": {},
  "ghcr.io/sourecode/devcontainer-features/llvm:1": {},
  "ghcr.io/sourecode/devcontainer-features/sccache:1": {},
  "ghcr.io/sourecode/devcontainer-features/nvm:2": {},
  "ghcr.io/sourecode/devcontainer-features/claude-code:2": {},
  "ghcr.io/sourecode/devcontainer-features/rtk:2": {},
  "ghcr.io/sourecode/devcontainer-features/context-mode:2": {},
  "ghcr.io/sourecode/devcontainer-features/home-persist:1": {}
}
```

### Adding project-local paths to persistence

If the project has its own `$HOME` state to persist beyond what features
declare, list it on `home-persist`:

```jsonc
"ghcr.io/sourecode/devcontainer-features/home-persist:1": {
  "paths": ".gitconfig,.bash_history,.config/my-tool"
}
```

Paths are relative to `$HOME`. On first create, any existing content at
those paths in the image gets moved into the volume; subsequent creates
volume-win.

## Where env vars come from

- `DEVCONTAINER_USERNAME`, `DEVCONTAINER_USER_UID`, `DEVCONTAINER_USER_GID`,
  `OWNER_USERNAME` are set on the outer Coder workspace agent
  (`coder_agent.main.env` in the Coder template). The `@devcontainers/cli`
  process inherits them, so `${localEnv:*}` in `devcontainer.json` resolves
  at devcontainer startup.
- Running the devcontainer locally on a laptop (no Coder): the `:fallback`
  defaults in each `${localEnv:NAME:fallback}` kick in. User ends up as
  `dev` at 1000:1000. For persistence to work, you'll need `/mnt/home-persist`
  to exist on the host — either create a directory or replace the mount
  source with a local path / named volume.

## Persistence caveats

One volume per Coder *owner*, bind-mounted through every outer workspace
they open. Shared across every devcontainer they open, in every workspace
they open — but only for paths explicitly declared in a manifest.

- `$HOME` itself is image-owned. `~/.bashrc`, `/etc/skel` contents, anything
  not in a manifest resets on rebuild. That's a feature — the image is the
  source of truth for shell config.
- Two workspaces running simultaneously share the same volume for declared
  paths (same as any shared home). Tools that tolerate concurrent writers
  cope fine; tools that don't behave as they would locally. Only declare
  paths where cross-workspace sharing is what you actually want.
- Resetting state: `docker volume rm coder-<owner>-home-persist`. Next
  create starts clean for declared paths; re-login to Claude Code etc.

See [`persistence.md`](persistence.md) for the full model.

## Checklist for the migrating agent

1. Edit `.devcontainer/devcontainer.json` to match the template above.
   Preserve `name` and `customizations` from the original. Add
   `home-persist:1` to `features`.
2. Edit `.devcontainer/Dockerfile`:
   - Add `ARG USERNAME / USER_UID / USER_GID`.
   - Fold user creation into the apt `RUN`.
   - Remove inline installs that are covered by features.
   - Drop any `CLAUDE_CONFIG_DIR` / `SCCACHE_DIR` overrides.
   - End with `USER ${USERNAME}`.
3. Remove obsolete files: standalone `bashrc`-patching scripts,
   `/commandhistory` directory hacks, hard-coded config-dir env vars.
4. Build-test the devcontainer locally:
   `devcontainer up --workspace-folder .` → should succeed, drop into the
   non-root user's shell, and have `cmake`, `clang`, `sccache`, `claude`,
   `rtk` on `$PATH`. `ls -la ~/.claude ~/.claude.json` should show symlinks
   into `/mnt/home-persist`.
5. Commit.
