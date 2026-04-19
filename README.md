# SoureCode Devcontainer Features

A small collection of [Dev Container Features](https://containers.dev/implementors/features/)
that extend the official [`anthropics/devcontainer-features/claude-code`](https://github.com/anthropics/devcontainer-features/tree/main/src/claude-code)
feature, plus a lightweight `nvm` feature.

Published to GHCR under the `sourecode/devcontainer-features` namespace.

## Features

| Feature | OCI reference | Summary |
|---|---|---|
| `nvm` | `ghcr.io/sourecode/devcontainer-features/nvm:1` | Installs [nvm](https://github.com/nvm-sh/nvm) and optionally a Node version (defaults to LTS). No yarn. |
| `rtk` | `ghcr.io/sourecode/devcontainer-features/rtk:1` | Installs [rtk](https://github.com/rtk-ai/rtk), an LLM token-reducing CLI proxy; auto-patches Claude Code if present. |
| `context-mode` | `ghcr.io/sourecode/devcontainer-features/context-mode:1` | Installs the [`context-mode`](https://github.com/mksglu/context-mode) Claude Code plugin. |

`rtk` and `context-mode` depend on the Claude Code CLI, which they declare via
`installsAfter: ghcr.io/anthropics/devcontainer-features/claude-code` so the
runtime orders installations automatically when Anthropic's feature is also
requested.

## Using the features

Add them to any `.devcontainer/devcontainer.json`, on top of whatever base
image you already use:

```jsonc
{
  "image": "debian:trixie-slim",
  "features": {
    "ghcr.io/sourecode/devcontainer-features/nvm:1": {
      "node": "lts"
    },
    "ghcr.io/anthropics/devcontainer-features/claude-code:1": {},
    "ghcr.io/sourecode/devcontainer-features/rtk:1": {
      "autoPatchClaude": true
    },
    "ghcr.io/sourecode/devcontainer-features/context-mode:1": {}
  }
}
```

Features run inside the image during build (as root), installing into the
container's `remoteUser` home. After rebuild, the tools are available on the
user's `PATH`.

### Feature options

#### `nvm`

| Option | Type | Default | Purpose |
|---|---|---|---|
| `version` | string | `0.40.4` | nvm release tag to install (without the leading `v`). |
| `node` | string | `lts` | Node version to install via nvm. `lts` uses `nvm install --lts`. `none` skips node install. Anything else is passed as-is to `nvm install`. |

#### `rtk`

| Option | Type | Default | Purpose |
|---|---|---|---|
| `autoPatchClaude` | boolean | `true` | Run `rtk init -g --auto-patch` to wire rtk's hook into Claude Code. No-op if the `claude` CLI is not on the user's PATH. |

#### `context-mode`

No options. Fails if the `claude` CLI is not on the user's PATH — add the
official `ghcr.io/anthropics/devcontainer-features/claude-code` feature as
well (the `installsAfter` hint then makes the CLI resolve the correct install
order automatically).

### Persisting Claude Code state

Claude login (`~/.claude/.credentials.json`) and chat history (`projects/`,
`sessions/`, `session-env/`) are not persisted across rebuilds by default. See
[`docs/persistence.md`](docs/persistence.md) for mount strategies (host login
bind mount, per-project credentials, or a shared named volume).

## Developing on this repo

### Repository layout

```
.github/workflows/
  publish-features.yml            # publishes every src/<id>/ to GHCR
src/
  nvm/
    devcontainer-feature.json
    install.sh
  rtk/
    devcontainer-feature.json
    install.sh
  context-mode/
    devcontainer-feature.json
    install.sh
docs/
  persistence.md
```

Each feature directory follows the [Dev Container Features spec](https://containers.dev/implementors/features/):
a `devcontainer-feature.json` with metadata and `options`, plus an `install.sh`
that runs as `root` inside the container during the build.

### Writing an install.sh

- `install.sh` starts as `root`. To land files in the remote user's home,
  resolve the user via `_REMOTE_USER` / `_REMOTE_USER_HOME` (set by the
  devcontainer runtime) and `su - "$USER"` for user-scoped steps.
- Feature options are exposed as **uppercased** environment variables (e.g.
  option `autoPatchClaude` → `$AUTOPATCHCLAUDE`). Always apply a default:
  `"${FOO:-true}"`.
- The working directory when `install.sh` runs is the extracted feature folder,
  so sibling files are accessible via `"$(dirname "$0")/..."`.
- Don't assume the base image has any particular tools — install `curl`,
  `ca-certificates`, etc. from `apt-get` if absent. Keep installs idempotent
  where reasonable.
- Declare dependencies with `installsAfter` so the runtime orders features
  correctly (e.g. `rtk` and `context-mode` both list
  `ghcr.io/anthropics/devcontainer-features/claude-code`).

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
