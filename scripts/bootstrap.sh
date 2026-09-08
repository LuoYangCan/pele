#!/usr/bin/env bash
# Clone or update pele, then install its managed symlinks.

set -euo pipefail

REPO_URL="${PELE_REPO_URL:-https://github.com/LuoYangcan/pele.git}"
DEST="${PELE_INSTALL_DIR:-${HOME}/Developer/pele}"

log() {
  printf '[pele bootstrap] %s\n' "$*"
}

for arg in "$@"; do
  case "$arg" in
    --dry-run)
      log "would clone/update $DEST, then install"
      if [ -f "$DEST/install.sh" ]; then
        exec "$DEST/install.sh" "$@"
      fi
      exit 0
      ;;
    -h|--help)
      printf 'Usage: bootstrap.sh [install options]\n--dry-run previews without fetching, cloning, or updating.\n'
      exit 0
      ;;
  esac
done

if [ -e "$DEST" ] && ! git -C "$DEST" rev-parse --git-dir >/dev/null 2>&1; then
  printf 'Error: %s exists but is not a Git checkout.\n' "$DEST" >&2
  exit 1
fi

if git -C "$DEST" rev-parse --git-dir >/dev/null 2>&1; then
  if [ -n "$(git -C "$DEST" status --porcelain)" ]; then
    printf 'Error: %s has uncommitted changes; refusing to pull over them.\n' "$DEST" >&2
    exit 1
  fi
  log "updating $DEST"
  git -C "$DEST" pull --ff-only
else
  log "cloning $REPO_URL to $DEST"
  mkdir -p "$(dirname "$DEST")"
  git clone "$REPO_URL" "$DEST"
fi

exec "$DEST/install.sh" "$@"
