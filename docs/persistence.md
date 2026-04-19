# Persisting state across devcontainer rebuilds

Our convention: a single per-owner home volume, bind-mounted through the
outer Coder workspace into every devcontainer the owner opens. Everything
under `$HOME` persists automatically — bash history, git config, SSH keys,
tool caches, Claude Code state, sccache cache, pipx installs, anything —
and it persists *across workspaces*, not just across rebuilds of one
workspace.

## The mount

In every `.devcontainer/devcontainer.json`:

```jsonc
{
  "mounts": [
    "source=/mnt/devhome,target=/home/${localEnv:DEVCONTAINER_USERNAME:dev},type=bind"
  ],
  "onCreateCommand": "test -z \"$(ls -A $HOME 2>/dev/null)\" && cp -rT /etc/skel $HOME || true"
}
```

- `/mnt/devhome` is a stable path inside the outer Coder workspace where
  the per-owner home volume is mounted (see Topology below).
- `DEVCONTAINER_USERNAME` is the in-container user (from
  `coder_agent.main.env`; default `dev`).
- `onCreateCommand` seeds the home from `/etc/skel` on first-ever attach.
  Bind mounts don't auto-seed from the image the way named volumes do, so
  the command copies skeleton dotfiles on the first workspace per owner
  and no-ops on every subsequent create.
- Running outside Coder, change the mount `source` to a local path or a
  named volume — the rest of the devcontainer stays the same.

One volume per Coder user. Open three different project devcontainers,
open them from three different workspaces — they all see the same home.

## Topology

```
┌───────────────────────────────────────────────────────────────────┐
│ host dockerd                                                      │
│                                                                   │
│   docker volume: coder-<owner>-devhome   ◄──── one per owner      │
│     │                                                             │
│     ├─► outer workspace A at /mnt/devhome                         │
│     │     └─► inner devcontainer (bind) /home/<dev-user>          │
│     │                                                             │
│     ├─► outer workspace B at /mnt/devhome                         │
│     │     └─► inner devcontainer (bind) /home/<dev-user>          │
│     │                                                             │
│     └─► outer workspace C at /mnt/devhome                         │
│           └─► inner devcontainer (bind) /home/<dev-user>          │
└───────────────────────────────────────────────────────────────────┘
```

The volume lives in the **host** dockerd, above any individual workspace.
It's defined in the Coder template as `docker_volume "devhome"`, scoped
by `coder_workspace_owner.me.name`, and bind-mounted into the outer
workspace container at `/mnt/devhome`. Each inner devcontainer then
bind-mounts that path as its own `/home/<user>`, so the filesystem every
workspace's IDE and shell see is literally the same volume.

Properties that fall out of this layout:

- Survives workspace deletion. Blowing away a workspace doesn't touch
  `coder-<owner>-devhome`.
- Survives `rebuild_no_cache`. That parameter only drops inner dockerd
  state (`vsc-*` images + BuildKit cache) — not the host-level volume.
- Nothing in `docs/migration-guide.md`'s volume name changes when you
  rename a workspace. Identity is tied to the owner, not the workspace.

## What persists automatically

Any path under `$HOME`. A non-exhaustive list that matters for us:

| Path                          | Contents                                           |
| ----------------------------- | -------------------------------------------------- |
| `~/.bash_history`             | Shell history                                      |
| `~/.gitconfig`                | Git identity + signing config                      |
| `~/.ssh/`                     | SSH keys (we auto-populate via Coder sub-agent)    |
| `~/.claude/`                  | Claude Code credentials, sessions, plugin data     |
| `~/.cache/sccache/`           | sccache compilation cache                          |
| `~/.cargo/`, `~/.rustup/`     | Rust toolchain + crate cache (if installed)        |
| `~/.local/`                   | pipx installs, user-local binaries                 |
| `~/.config/`                  | Per-app config                                     |

Nothing extra to configure. `SCCACHE_DIR` and `CLAUDE_CONFIG_DIR` default
to paths under `$HOME`, so the env vars the old pattern used to override
them are unnecessary and should be removed.

## What doesn't persist

- Anything **outside** `$HOME` — `/usr/local/...`, `/opt/...`, etc. These
  come from the image, the Dockerfile, or feature installs. Rebuild the
  image to change them. This is also why our features install to
  `/usr/local/bin` rather than `~/.local/bin`: feature-installed binaries
  need to live outside the home volume.
- The workspace folder itself (usually `/workspaces/<repo>`). That's the
  git clone under the outer workspace's `/home/coder`, persisted by the
  per-workspace `docker_volume.home_volume`. Your working tree survives
  restarts of *its* workspace, but is scoped to that workspace.

## Seeding on first create

Bind mounts don't auto-seed from the image. The first time the per-owner
volume is attached, it's empty, and the devcontainer's image-side
`/home/<user>` (skeleton dotfiles, defaults from `/etc/skel`) is *not*
copied into it automatically.

The `onCreateCommand` above handles seeding explicitly:

```bash
test -z "$(ls -A $HOME 2>/dev/null)" && cp -rT /etc/skel $HOME || true
```

- On the first-ever create for an owner, `$HOME` is empty → copy
  `/etc/skel` in.
- On every subsequent create (any workspace, any rebuild), `$HOME` has
  content → no-op.

After the first create the volume wins on its own. Subsequent rebuilds
of the image will **not** propagate changes to the image's `$HOME` into
the existing volume.

Consequence: don't put long-lived shell config in `~/.bashrc` via the
Dockerfile — it'd be stuck at whatever got seeded on the first create.
Use `/etc/bash.bashrc` instead (system-wide, sourced by non-login
interactive bashes on Debian/Ubuntu, image-owned, always authoritative).

## Cross-workspace side effects

One home for every workspace means:

- Pros: universal `~/.gitconfig`, `~/.ssh/*`, one Claude Code login, one
  shared bash history, shared sccache / `~/.cargo` caches across all
  projects the owner opens.
- Cons: tools that write env-specific state to `$HOME` (some pyenv / nvm
  layouts, project-specific `~/.config/*` files) will leak between
  projects. For most dotfile-level state this is exactly what you want.
  If a specific tool misbehaves, override its config dir via `containerEnv`
  to point at a project-scoped path under the repo's working tree.
- Running two workspaces simultaneously means two processes writing to
  the same home — the same situation as running two terminals on your
  laptop. Tools that support concurrent writers (bash history with
  `histappend`, content-addressed caches, atomic-rename lockfiles) cope
  fine. Tools that don't (single-writer state files) behave as they would
  locally.

## Resetting a home

If the shared home gets into a bad state, nuke the volume from the host:

```bash
docker volume rm coder-<owner-username>-devhome
```

Next devcontainer start sees an empty `/mnt/devhome`, the `onCreateCommand`
re-seeds it from `/etc/skel`, and you're back to a clean home. You'll need
to re-login to Claude Code, re-populate `~/.ssh` (the Coder sub-agent does
this automatically via `coder_script "git_ssh_signing"`), and re-set any
interactive state.
