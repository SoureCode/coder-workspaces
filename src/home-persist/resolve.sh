#!/usr/bin/env bash
# home-persist resolver.
#
# Reads JSON manifests from /etc/devcontainer-persist.d/*.json and, for each
# listed path, symlinks $HOME/<path> → /mnt/home-persist/<path>. First-run
# seeding moves existing $HOME content into the volume; on every subsequent
# run the volume wins. Idempotent.
#
# Manifest shape:
#   { "source": "<label>", "paths": ["<rel-to-$HOME>", ...] }
#
# Path convention:
#   - Trailing slash ("/") means the path is a directory. The target is
#     pre-created so the symlink is never dangling — avoids `mkdir -p` on
#     a dangling symlink failing with EEXIST in consumer scripts.
#   - No trailing slash means the path is a file (or left dangling until
#     a writer creates it).
set -euo pipefail

STATE="${HOME_PERSIST_STATE:-/mnt/home-persist}"
MANIFEST_DIR="${HOME_PERSIST_MANIFEST_DIR:-/etc/devcontainer-persist.d}"

log() { echo "home-persist: $*" >&2; }

if [ ! -d "$STATE" ]; then
  log "state dir $STATE missing; skipping (did you bind-mount it in devcontainer.json?)"
  exit 0
fi
if [ ! -w "$STATE" ]; then
  log "state dir $STATE not writable by $(id -un); skipping"
  exit 0
fi
if [ ! -d "$MANIFEST_DIR" ]; then
  exit 0
fi

shopt -s nullglob
manifests=("$MANIFEST_DIR"/*.json)
shopt -u nullglob

if [ ${#manifests[@]} -eq 0 ]; then
  exit 0
fi

declare -A owner=()

for mf in "${manifests[@]}"; do
  if ! jq -e . "$mf" >/dev/null 2>&1; then
    log "skipping unreadable manifest $mf"
    continue
  fi
  source=$(jq -r '.source // "unknown"' "$mf")

  while IFS= read -r raw; do
    [ -z "$raw" ] && continue
    rel="${raw#\~/}"
    rel="${rel#/}"
    is_dir=0
    case "$rel" in
      */) is_dir=1; rel="${rel%/}" ;;
    esac
    case "$rel" in
      *..*|"") log "rejecting invalid path in $mf: $raw"; continue ;;
    esac

    if [ -n "${owner[$rel]+x}" ]; then
      log "collision on $rel: ${owner[$rel]} vs $source ($mf)"
      continue
    fi
    owner[$rel]="$source"

    link="$HOME/$rel"
    target="$STATE/$rel"
    mkdir -p "$(dirname "$target")" "$(dirname "$link")"

    if [ -e "$link" ] && [ ! -L "$link" ]; then
      # Auto-repair the <1.2.0 artifact: if $link is still a real directory
      # and contains a dangling-style symlink named after rel's basename
      # pointing at $target, that's the nested symlink the old code produced
      # (e.g. $HOME/.claude/.claude → /mnt/home-persist/.claude). Drop it
      # before the merge so it isn't copied into the volume as a self-loop.
      stale="$link/$(basename "$rel")"
      if [ -L "$stale" ]; then
        stale_resolved="$(readlink -f "$stale" 2>/dev/null || true)"
        target_resolved="$(readlink -f "$target" 2>/dev/null || true)"
        if [ -n "$stale_resolved" ] && [ "$stale_resolved" = "$target_resolved" ]; then
          log "repairing legacy nested symlink $stale"
          rm -f "$stale"
        fi
      fi

      if [ ! -e "$target" ]; then
        mv "$link" "$target"
      elif [ -d "$link" ] && [ -d "$target" ]; then
        # Both sides are directories and the volume is already populated. Merge
        # home into the volume without clobbering (volume wins, per the stated
        # model), then drop the now-redundant home dir so `ln -sfn` below
        # replaces it with the symlink. Without this branch, `ln -sfn` against
        # a real directory creates the link *inside* it — that's how we ended
        # up with $HOME/.claude/.claude.
        cp -an "$link"/. "$target"/
        rm -rf "$link"
      fi
    fi

    # Pre-create directory targets so the symlink isn't dangling — consumer
    # scripts running `mkdir -p ~/<path>` would otherwise hit EEXIST.
    if [ "$is_dir" = 1 ] && [ ! -e "$target" ]; then
      mkdir -p "$target"
    fi

    ln -sfn "$target" "$link"
  done < <(jq -r '.paths[]?' "$mf")
done
