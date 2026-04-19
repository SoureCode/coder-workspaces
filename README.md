# SoureCode Devcontainer Features

A small collection of [Dev Container Features](https://containers.dev/implementors/features/)
for Claude Code and friends, plus a lightweight `nvm` feature.

Published to GHCR under the `sourecode/devcontainer-features` namespace.

## Features

| Feature | OCI reference | Summary |
|---|---|---|
| `claude-code` | `ghcr.io/sourecode/devcontainer-features/claude-code:2` | Installs the Claude Code CLI via the official native installer into `/usr/local/bin`, so the binary survives home-directory volume mounts. Requires Node.js — automatically pulls in the `nvm` feature via `dependsOn`. |
| `rtk` | `ghcr.io/sourecode/devcontainer-features/rtk:2` | Installs [rtk](https://github.com/rtk-ai/rtk), an LLM token-reducing CLI proxy, into `/usr/local/bin`. Auto-patches Claude Code via `postCreateCommand` so the hook is written against the mounted home, not the image. |
| `context-mode` | `ghcr.io/sourecode/devcontainer-features/context-mode:1` | Installs the [`context-mode`](https://github.com/mksglu/context-mode) Claude Code plugin. |
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
    "ghcr.io/sourecode/devcontainer-features/context-mode:1": {}
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

No options. Fails if the `claude` CLI is not on the user's PATH — add a
claude-code feature as well (the `installsAfter` hint then makes the CLI
resolve the correct install order automatically).

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
