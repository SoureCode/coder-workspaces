# Persisting state across workspace restarts

Our convention: a single per-owner volume bind-mounted at `/mnt/home-persist`,
plus a resolver that symlinks **only declared paths** under `$HOME` into that
volume. Every install script or project lists the paths it needs persisted; the
resolver wires them up on every agent start. Everything outside the declared
set lives in the image (or the per-workspace `$HOME` volume) and resets on
image rebuild — same as any other container.

Compared to a whole-home mount: narrower blast radius, no drift between the
image and the live `$HOME`, no cross-workspace leakage for paths you didn't
opt in.

> **Not persistence, but related — `/mnt/shared`.** A single deployment-wide
> docker volume (`docker_volume.shared` in `main.tf`) is mounted at
> `/mnt/shared` on every workspace. Sticky-bit 1777 (like `/tmp`) — anyone
> can drop files, only the owner can delete them. Use it as a cross-user
> drop box, not for per-user state.

## The three moving parts

1. **The volume + mount.** `main.tf` declares `docker_volume.home_persist`
   (per-owner, lives in the host dockerd) and mounts it into every workspace
   container at `/mnt/home-persist`:

   ```hcl
   resource "docker_volume" "home_persist" {
     name = "coder-${data.coder_workspace_owner.me.name}-home-persist"
     ...
   }

   resource "docker_container" "workspace" {
     volumes {
       container_path = "/mnt/home-persist"
       volume_name    = docker_volume.home_persist.name
     }
   }
   ```

2. **The manifest.** Install scripts drop a JSON file into
   `/etc/home-persist.d/<name>.json` at image build time. Example
   from `scripts/claude-code/install.sh`:

   ```json
   {
     "source": "claude-code",
     "paths": [".claude/", ".claude.json"]
   }
   ```

   **Trailing-slash convention**: a path ending in `/` is a directory; the
   resolver pre-creates the target so the symlink is never dangling. Use a
   slash for `.claude/` but not for `.claude.json` (a file). Without this,
   the first create on an empty volume leaves `~/.claude` as a dangling
   symlink, and any consumer doing `mkdir -p ~/.claude` fails with EEXIST.

3. **The resolver.** `main.tf`'s `coder_script.lifecycle_init` invokes
   `/usr/local/bin/home-persist-resolve` at agent start, with
   `start_blocks_login = true` so IDEs don't connect before the symlinks are
   in place. For each declared path:

   - If `/mnt/home-persist/<path>` exists → symlink `$HOME/<path>` → it
     (volume wins).
   - Else if `$HOME/<path>` exists (real content from the image) → move it
     into the volume, then symlink (first-run seed for that path).
   - Else → create a dangling symlink; the tool populates it on first write,
     and the file lives in the volume transparently.

   Idempotent. Collisions between two manifests for the same path are
   logged and skipped.

## Topology

```
┌─────────────────────────────────────────────────────────────────┐
│ host dockerd                                                    │
│                                                                 │
│   docker volume: coder-<owner>-home-persist  ◄── one per owner  │
│     │                                                           │
│     ├─► workspace A at /mnt/home-persist                        │
│     │     └─► symlinks from $HOME into it                       │
│     ├─► workspace B at /mnt/home-persist                        │
│     │     └─► symlinks from $HOME into it                       │
│     └─► workspace C at /mnt/home-persist                        │
│           └─► symlinks from $HOME into it                       │
└─────────────────────────────────────────────────────────────────┘
```

The volume lives in the **host** dockerd, above any individual workspace.
Declared in `main.tf` as `docker_volume "home_persist"`, scoped by
`coder_workspace_owner.me.name`, and bind-mounted into the workspace
container at `/mnt/home-persist`.

Properties that fall out:

- Survives workspace deletion. Blowing away a workspace doesn't touch
  `coder-<owner>-home-persist`.
- Scoped to the owner. Identity is tied to the owner, not the workspace —
  rename a workspace, same volume.

## What's declared today

| Source        | Paths                         | Why                                  |
| ------------- | ----------------------------- | ------------------------------------ |
| `claude-code` | `.claude/`, `.claude.json`    | Login credentials, sessions, plugins |
| `jetbrains`   | `.cache/JetBrains/`, `.config/JetBrains/`, `.local/share/JetBrains/`, `.java/.userPrefs/jetbrains/` | The workspace is headless — Toolbox/Gateway runs on the user's local machine. Clicking the IDE button opens a `jetbrains-gateway://` URL; Gateway SSHes in and has `remote-dev-server.sh` download the IDE backend into `~/.cache/JetBrains/RemoteDev/dist/` on first connect (hundreds of MB per IDE). The three JetBrains roots keep the downloaded backend plus per-IDE `RemoteDev-<Code>/` settings, plugins, and project indexes. `.java/.userPrefs/jetbrains/` is the Java `Preferences` store the IDEs use for JetBrains Account / JetProfile login, license activation, and non-commercial-license acceptance — persisting it avoids re-login on every restart. |

Anything not declared is image-owned (or per-workspace-home-volume-owned)
and resets on image rebuild — git config, SSH keys, bash history, caches.
Two common patterns for those:

- **Git identity / SSH keys** — injected per-workspace by Coder via
  `coder_script.git_ssh_signing` and the `coder_env.git_*` resources in
  `main.tf`. Regenerated every start, no persistence needed.
- **Shell config / dotfiles** — use Coder's dotfiles repo support or bake
  into `src/base/Dockerfile` (`/etc/skel`).

If a specific tool needs persistence, drop a manifest under
`/etc/home-persist.d/` from its install script.

## Declaring extra paths at workspace creation

The Coder template exposes a `home_persist_paths` parameter (see `main.tf`).
Set it to a comma-separated list of `$HOME`-relative paths to add on a
per-workspace basis — the template's `coder_script.lifecycle_init` writes
those to `/etc/home-persist.d/user.json` at agent start, before the resolver
runs.

Example value:

```
.gitconfig,.bash_history,.config/my-tool/
```

Trailing `/` marks a directory, same convention as the install-script
manifests. Change the parameter on an existing workspace, restart it, and
the new paths are symlinked on next start.

## Writing an install.sh that needs HOME persistence

Any `scripts/<name>/install.sh` can declare paths by writing a manifest at
image build time. The resolver finds it and handles the rest. Minimal
pattern:

```bash
mkdir -p /etc/home-persist.d
cat > /etc/home-persist.d/my-tool.json <<'EOF'
{
  "source": "my-tool",
  "paths": [".my-tool/", ".config/my-tool/", ".my-tool.conf"]
}
EOF
```

Trailing `/` for directories, no slash for files.

No install ordering required — `home-persist-resolve` runs at agent start,
after the image is already built with every script's manifest in place.
Listing the same path in two manifests is harmless: the second is logged
and skipped.

## Resetting state

If persistence gets into a bad state, nuke the volume from the host:

```bash
docker volume rm coder-<owner>-home-persist
```

Next create sees an empty `/mnt/home-persist`; the resolver's first-run
seeding kicks in per path, or leaves dangling symlinks for paths whose
content didn't exist in the image either. You'll need to re-login to Claude
Code and anything else that held creds.

## Cross-workspace side effects

One volume per owner means:

- One Claude Code login reused across every workspace the owner opens.
- Two workspaces running simultaneously means two processes writing to the
  same files in the volume. For credential files and config this is fine;
  for anything with single-writer semantics, same caveats as any shared
  home. Add the path only if you actually want it shared.
