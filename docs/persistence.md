# Persisting state across devcontainer rebuilds

Our convention: mount a single named volume at the user's home directory,
scoped per-Coder-user, shared across every devcontainer that user opens.
Everything that lives under `$HOME` persists automatically — bash history,
git config, SSH keys, tool caches, Claude Code state, sccache cache, pipx
installs, anything.

## The mount

In every `.devcontainer/devcontainer.json`:

```jsonc
{
  "mounts": [
    "source=devhome-${localEnv:OWNER_USERNAME:shared},target=/home/${localEnv:DEVCONTAINER_USERNAME:dev},type=volume"
  ]
}
```

- `OWNER_USERNAME` is injected by the Coder template (`coder_agent.main.env`)
  and resolves to the Coder workspace owner's username.
- `DEVCONTAINER_USERNAME` is the in-container user (also from
  `coder_agent.main.env`; default `dev`).
- Running outside Coder, both fall back to sensible defaults —
  `devhome-shared` mounted at `/home/dev`.

One volume per Coder user. Open three different project devcontainers and
they all see the same home.

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

Nothing extra to configure. `SCCACHE_DIR` and `CLAUDE_CONFIG_DIR` default to
paths under `$HOME`, so the env vars the old pattern used to override those
are unnecessary and should be removed.

## What doesn't persist

- Anything **outside** `$HOME` — `/usr/local/...`, `/opt/...`, etc. These come
  from the image, the Dockerfile, or feature installs. Rebuild the image to
  change them.
- The workspace folder itself (usually `/workspace`). This is bind-mounted
  from the outer Coder workspace container's `/home/<coder>/<repo>`, which
  has its own persistence (via the outer `docker_volume.home_volume` in the
  Coder template). Your git working tree survives outer-workspace restarts;
  inside the devcontainer it's the same filesystem surface.

## First-create seeding

When Docker mounts an empty named volume over a non-empty directory, it
copies the image's directory contents into the volume. So the first time a
user opens any devcontainer, the image's `/home/<user>` (skeleton dotfiles,
defaults from `/etc/skel`) seeds the volume.

After that, the volume wins. Subsequent rebuilds of the image will **not**
propagate changes to the image's `$HOME` into the existing volume.

Consequence: don't put long-lived shell config in `~/.bashrc` in the
Dockerfile — it'd be stuck at whatever got seeded on first-create. Use
`/etc/bash.bashrc` instead (system-wide, sourced by non-login interactive
bashes on Debian/Ubuntu, image-owned, always authoritative).

## Cross-project side effects

One home for every devcontainer means:

- Pros: universal `~/.gitconfig`, `~/.ssh/*`, one Claude Code login, one
  bash history, shared sccache/`~/.cargo` caches.
- Cons: tools that write env-specific state to `$HOME` (some pyenv / nvm
  layouts, project-specific `~/.config/*` files) will leak between
  projects. For most dotfile-level state this is exactly what you want.
  If a specific tool misbehaves, override its config dir via `containerEnv`
  to point at a project-scoped path under the repo.

## Resetting a home

If the shared home gets into a bad state, nuke the volume from the host:

```bash
docker volume rm devhome-<owner-username>
```

Next devcontainer start re-seeds it from the image. You'll need to
re-login to Claude Code, re-set any interactive state, etc.
