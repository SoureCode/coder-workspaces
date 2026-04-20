# Persisting state across devcontainer rebuilds

Our convention: a single per-owner volume bind-mounted at `/mnt/home-persist`,
plus the `home-persist` feature that symlinks **only declared paths** under
`$HOME` into that volume. Every feature or project lists the paths it needs
persisted; a shared resolver wires them up on every create. Everything
outside the declared set lives in the image and resets on rebuild — same as
any other container.

Compared to a whole-home mount: narrower blast radius, no first-run skeleton
seeding, no drift between the image's `/etc/skel` and the live `$HOME`, no
cross-tool leakage between workspaces.

## The three moving parts

1. **The volume + bind mount.** In `.devcontainer/devcontainer.json`:

   ```jsonc
   {
     "mounts": [
       "source=/mnt/home-persist,target=/mnt/home-persist,type=bind"
     ],
     "features": {
       "ghcr.io/sourecode/devcontainer-features/home-persist:1": {}
     }
   }
   ```

   Source `/mnt/home-persist` is where the Coder template exposes the
   per-owner docker volume (see Topology). Running outside Coder, change the
   source to a local path or a named volume — the target stays the same.

2. **The manifest.** Features drop a JSON file into
   `/etc/devcontainer-persist.d/<name>.json` at build time. Example from
   `claude-code`:

   ```json
   {
     "source": "claude-code",
     "paths": [".claude", ".claude.json"]
   }
   ```

   Users can also declare project-local paths via the `paths` option on the
   `home-persist` feature:

   ```jsonc
   "ghcr.io/sourecode/devcontainer-features/home-persist:1": {
     "paths": ".claude,.claude.json,.gitconfig"
   }
   ```

   That writes `user.json` into the same directory.

3. **The resolver.** `home-persist`'s `onCreateCommand` runs
   `/usr/local/bin/home-persist-resolve` on every create. For each declared
   path:
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
┌───────────────────────────────────────────────────────────────────┐
│ host dockerd                                                      │
│                                                                   │
│   docker volume: coder-<owner>-home-persist   ◄──── one per owner      │
│     │                                                             │
│     ├─► outer workspace A at /mnt/home-persist                    │
│     │     └─► inner devcontainer (bind) /mnt/home-persist         │
│     │            └─► symlinks from $HOME into it                  │
│     │                                                             │
│     ├─► outer workspace B at /mnt/home-persist                    │
│     │     └─► inner devcontainer (bind) /mnt/home-persist         │
│     │                                                             │
│     └─► outer workspace C at /mnt/home-persist                    │
│           └─► inner devcontainer (bind) /mnt/home-persist         │
└───────────────────────────────────────────────────────────────────┘
```

The volume lives in the **host** dockerd, above any individual workspace.
It's defined in the Coder template as `docker_volume "home_persist"`, scoped by
`coder_workspace_owner.me.name`, and bind-mounted into the outer workspace
container at `/mnt/home-persist`. Each inner devcontainer bind-mounts that
same path at the same path, and the resolver creates symlinks from `$HOME`
into it.

Properties that fall out:

- Survives workspace deletion. Blowing away a workspace doesn't touch
  `coder-<owner>-home-persist`.
- Survives `rebuild_no_cache`. That parameter only drops inner dockerd
  state (`vsc-*` images + BuildKit cache) — not the host-level volume.
- Scoped to the owner. Identity is tied to the owner, not the workspace —
  rename a workspace, same volume.

## What's declared today

| Source         | Paths                         | Why                                          |
| -------------- | ----------------------------- | -------------------------------------------- |
| `claude-code`  | `.claude`, `.claude.json`     | Login credentials, sessions, plugins         |
| `user` (opt-in)| whatever you list             | Project-local additions                      |

Anything not in the declared set is image-owned and resets on rebuild — git
config, SSH keys, bash history, caches. Two common patterns for those:

- **Git identity / SSH keys** — injected per-workspace by Coder via
  `coder_script` and `coder_env` in `main.tf`. Regenerated every start, no
  persistence needed.
- **Dotfiles / aliases** — use Coder's dotfiles repo support or bake into
  the devcontainer's Dockerfile / `/etc/skel`.

If a specific tool needs persistence, add it to the manifest — either
ship a feature that declares it, or list the path under the `home-persist`
feature's `paths` option.

## Writing a feature that needs HOME persistence

Any feature can declare paths by writing a manifest at build time. The
resolver finds it and handles the rest. Minimal pattern:

```bash
# in your feature's install.sh
mkdir -p /etc/devcontainer-persist.d
cat > /etc/devcontainer-persist.d/my-feature.json <<'EOF'
{
  "source": "my-feature",
  "paths": [".my-feature", ".config/my-feature"]
}
EOF
```

No ordering required — `home-persist`'s `onCreateCommand` runs after all
features install, so the manifest is always visible by resolve time. Listing
the same path in two manifests is harmless: the second is logged and
skipped.

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
