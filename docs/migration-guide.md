# Devcontainer Migration Guide

Guide to migrate an existing
`.devcontainer/` setup onto the SoureCode conventions: persistent per-user
home, dynamic user construct, and toolchain installed via features instead
of inline Dockerfile install steps.

## Goals of the migration

1. Every devcontainer for the same Coder user shares one named volume mounted
   on the user's home directory. Bash history, git config, shell dotfiles,
   tool caches, Claude config, etc. persist across devcontainer rebuilds
   **and** across different projects.
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
- Uses ephemeral volumes or `${devcontainerId}`-scoped volumes (state dies
  on rebuild).
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
    "source=devhome-${localEnv:OWNER_USERNAME:shared},target=/home/${localEnv:DEVCONTAINER_USERNAME:dev},type=volume"
  ],
  "features": {
    // pick from the feature reference below
  },
  "customizations": {
    // keep whatever IDE config the project already has
  }
}
```

Rules:

- `name` — keep the project's existing name.
- Volume name is **always** `devhome-${localEnv:OWNER_USERNAME:shared}`. Do
  **not** add the project name to the volume — the point is that every
  project shares one home per user. Fallback `:shared` kicks in when running
  the devcontainer locally outside Coder.
- `remoteUser` and `containerUser` both use `${localEnv:DEVCONTAINER_USERNAME:dev}`.
- Do **not** set `CLAUDE_CONFIG_DIR` or `SCCACHE_DIR` in `containerEnv` —
  their defaults (`~/.claude`, `~/.cache/sccache`) already land inside the
  persistent home volume.
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
    `/root/.bash_history` — home is on the volume now, bash history
    persists naturally at `~/.bash_history`.
  - Hard-coded `CC=clang-22` / `CXX=clang++-22` — the `llvm` feature sets
    these via `containerEnv`.
  - Hard-coded `SCCACHE_DIR` — default already works.
- If the project sets shell-level config (`HISTSIZE`, `PATH` additions, etc.)
  put it in `/etc/bash.bashrc` (system-wide, sourced by non-login interactive
  bashes on Debian/Ubuntu) **not** `~/.bashrc`. The home dir is a volume —
  `~/.bashrc` only gets seeded on first-create and diverges from the image
  on rebuilds.

## Available features

Reference: `ghcr.io/sourecode/devcontainer-features/<id>:<major-version>`

| Feature | Purpose | Notable options |
|---|---|---|
| `cmake` | CMake from Kitware GitHub releases, distro-agnostic | `version` (default `latest`) |
| `llvm` | Clang/LLVM via `apt.llvm.org`. Sets `CC`/`CXX` in containerEnv. | `version` (default `22`), `all` (default `true`) |
| `sccache` | Mozilla sccache from GitHub releases | `version` (default `latest`) |
| `nvm` | NVM + optional Node install | `version`, `node` (default `lts`) |
| `claude-code` | Anthropic Claude Code CLI | — |
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
  "ghcr.io/sourecode/devcontainer-features/context-mode:1": {}
}
```

## Where env vars come from

- `DEVCONTAINER_USERNAME`, `DEVCONTAINER_USER_UID`, `DEVCONTAINER_USER_GID`,
  `OWNER_USERNAME` are set on the outer Coder workspace agent
  (`coder_agent.main.env` in the Coder template). The `@devcontainers/cli`
  process inherits them, so `${localEnv:*}` in `devcontainer.json` resolves
  at devcontainer startup.
- Running the devcontainer locally on a laptop (no Coder): the `:fallback`
  defaults in each `${localEnv:NAME:fallback}` kick in. User ends up as
  `dev` at 1000:1000, volume is `devhome-shared`.

## Persistent home caveats

One volume per Coder user, shared across every devcontainer they open. This
is intentional — same bash history, same `~/.gitconfig`, same `~/.claude`
everywhere. Side effects to understand:

- First-time volume creation seeds from the image's `/home/<user>` (Docker
  copies dir contents when an empty named volume is mounted over a
  non-empty target). Subsequent rebuilds use the volume; changes to the
  image's home dir will **not** propagate.
- Put long-lived shell config in `/etc/bash.bashrc` (image-side) so it
  stays authoritative.
- Tools that store env-specific state in `$HOME` (some pyenv/nvm layouts,
  `.cache/` bloat) can collide across projects. Usually fine for dotfiles
  and coarse caches; tune per-project if something misbehaves.

## Checklist for the migrating agent

1. Edit `.devcontainer/devcontainer.json` to match the template above.
   Preserve `name` and `customizations` from the original.
2. Edit `.devcontainer/Dockerfile`:
   - Add `ARG USERNAME / USER_UID / USER_GID`.
   - Fold user creation into the apt `RUN`.
   - Remove inline installs that are covered by features.
   - Move any `.bashrc` shell config to `/etc/bash.bashrc`.
   - End with `USER ${USERNAME}`.
3. Remove obsolete files: standalone `bashrc`-patching scripts,
   `/commandhistory` directory hacks, hard-coded `CLAUDE_CONFIG_DIR` /
   `SCCACHE_DIR` env vars.
4. Build-test the devcontainer locally:
   `devcontainer up --workspace-folder .` → should succeed, drop into the
   non-root user's shell, and have `cmake`, `clang`, `sccache`, `claude`,
   `rtk` on `$PATH`.
5. Commit.
