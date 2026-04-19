# Persisting Claude Code data across container rebuilds

Claude Code stores runtime state under `~/.claude/` in the remote user's home.
Nothing in this state is preserved when a devcontainer is rebuilt, so a rebuild
forces you to re-run `claude /login` and loses your chat history. The paths
worth persisting are:

| Path                                  | Contents                             |
| ------------------------------------- | ------------------------------------ |
| `~/.claude/.credentials.json`         | OAuth tokens (after `claude /login`) |
| `~/.claude/projects/`                 | per-project chat / session history   |
| `~/.claude/sessions/`                 | session snapshots                    |
| `~/.claude/session-env/`              | per-session env captures             |
| `~/.claude/<plugin-id>/`              | per-plugin runtime data (e.g. `context-mode/` keeps its FTS5 index here) |

> All examples below assume `/home/<user>/` as the remote home. Replace `<user>`
> with whatever your base image / feature uses (often `vscode`, `node`, or
> `dev`).

> **Never** mount a volume or bind mount at `~/.claude/` itself — doing so
> shadows anything a feature (e.g. `anthropics/claude-code`, our `rtk`, our
> `context-mode`) installed into that directory at build time, including
> `settings.json`, the plugin cache, and the `claude` CLI's own baked state.

## Directories: named volumes

Named volumes only work for **directory** targets. If you point a `type=volume`
mount at a file path, Docker silently creates an empty **directory** there and
Claude will then fail to read the file.

```jsonc
{
  "mounts": [
    "source=claude-projects,target=/home/<user>/.claude/projects,type=volume",
    "source=claude-sessions,target=/home/<user>/.claude/sessions,type=volume",
    "source=claude-session-env,target=/home/<user>/.claude/session-env,type=volume"
  ]
}
```

If you use `context-mode` and want its knowledge index to survive rebuilds,
add its plugin directory too:

```jsonc
"source=claude-context-mode,target=/home/<user>/.claude/context-mode,type=volume"
```

## Credentials (`.credentials.json`): bind mount

`.credentials.json` is a single file, so it must be persisted via `type=bind`
(not `type=volume`). Three options, from easiest to most isolated:

### 1. Share the host's login (recommended if you use Claude on the host too)

```jsonc
{
  "mounts": [
    "source=${localEnv:HOME}/.claude/.credentials.json,target=/home/<user>/.claude/.credentials.json,type=bind,consistency=cached"
  ]
}
```

The file must exist on the host before the container starts — run
`claude /login` on the host once. Every container mounting the file is then
authenticated as you.

### 2. Container-only login (per-project credentials file on host)

If you want the container to manage its own login independent of the host,
create the file yourself and bind-mount it:

```sh
mkdir -p .devcontainer/claude-state
touch .devcontainer/claude-state/.credentials.json
chmod 600 .devcontainer/claude-state/.credentials.json
echo "claude-state/" >> .devcontainer/.gitignore
```

Then in `.devcontainer/devcontainer.json`:

```jsonc
{
  "mounts": [
    "source=${localWorkspaceFolder}/.devcontainer/claude-state/.credentials.json,target=/home/<user>/.claude/.credentials.json,type=bind"
  ]
}
```

Run `claude /login` inside the container once; the token is written to the
bind-mounted file and survives rebuilds.

### 3. Named-volume login, host-independent (shared across projects)

`type=volume` cannot target a single file, but it can target a directory.
Combine a named volume with a symlink inside the image to redirect
`.credentials.json` into the mounted directory. Add the following to a custom
Dockerfile or a feature that runs before `anthropics/claude-code`:

```dockerfile
# The symlink is created dangling and resolves on first write, so the normal
# ~/.claude/.credentials.json path continues to behave as Claude expects.
RUN install -d -o <user> -g <user> /home/<user>/.claude-shared && \
    ln -s /home/<user>/.claude-shared/.credentials.json \
          /home/<user>/.claude/.credentials.json
```

Then in every `.devcontainer/devcontainer.json` that should share the login:

```jsonc
{
  "mounts": [
    "source=claude-shared,target=/home/<user>/.claude-shared,type=volume"
  ]
}
```

Run `claude /login` in any container once; the token lands in the
`claude-shared` named volume, and every other container mounting that same
volume resolves the symlink to the same file. No host dependency.

## Comparing the credential strategies

| Approach                                              | Host needs Claude? | Shared across container instances?                       |
| ----------------------------------------------------- | ------------------ | -------------------------------------------------------- |
| Bind-mount the host's `~/.claude/.credentials.json`   | yes                | **yes** — same file, any number of containers            |
| Bind-mount a dedicated host path                      | no                 | **yes** — any container mounting the same host path      |
| Project-local `.devcontainer/claude-state/`           | no                 | no — each project has its own file                       |
| Named-volume + symlink                                | no                 | **yes** — any container mounting the same named volume   |

## Notes

- `CLAUDE_CONFIG_DIR` can redirect Claude Code's config root to a completely
  different path. If you set it, all of the mount targets above need to move
  accordingly.
- `settings.json.bak` (created by `rtk init`'s `--auto-patch`) does not need
  to be persisted.
- If you want to pin specific `settings.json` content into the image, do it in
  a feature's `install.sh` (`install -m 0644 settings.json $USER_HOME/.claude/`),
  not via a mount — settings that have to match the build are a build-time
  concern, not a runtime one.
