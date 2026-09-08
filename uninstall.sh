#!/usr/bin/env bash
# Remove only entries that still point at this Pele checkout.
set -euo pipefail

HOST="claude"
MODE="global"
MODE_FLAG=""
PROJECT_PATH=""
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage: ./uninstall.sh [--global | --project PATH] [--host claude|codex|both] [--dry-run]
Removes Pele-owned symlinks and unmodified Pele-managed hook/index entries only.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --global) [ "$MODE_FLAG" != project ] || { echo "--global and --project are mutually exclusive" >&2; exit 2; }; MODE="global"; MODE_FLAG="global"; shift ;;
    --project) [ "$MODE_FLAG" != global ] || { echo "--global and --project are mutually exclusive" >&2; exit 2; }; MODE="project"; MODE_FLAG="project"; PROJECT_PATH="${2:-}"; [ -n "$PROJECT_PATH" ] || { echo "--project requires PATH" >&2; exit 2; }; shift 2 ;;
    --host) HOST="${2:-}"; case "$HOST" in claude|codex|both) ;; *) echo "--host must be claude, codex, or both" >&2; exit 2;; esac; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

PELE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CLAUDE_DIR="${HOME}/.claude"
CODEX_DIR="${CODEX_HOME:-${HOME}/.codex}"
if [ "$MODE" = project ]; then
  [ -d "$PROJECT_PATH" ] || { echo "Project path does not exist: $PROJECT_PATH" >&2; exit 2; }
  PROJECT_PATH="$(cd "$PROJECT_PATH" && pwd -P)"
  CLAUDE_DIR="$PROJECT_PATH/.claude"
  CODEX_DIR="$PROJECT_PATH/.codex"
fi

python_bin=""
for candidate in "${PYTHON_BIN:-}" python3.14 python3.13 python3.12 python3.11 python3 python; do
  [ -n "$candidate" ] || continue
  if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)' >/dev/null 2>&1; then
    python_bin="$candidate"
    break
  fi
done
[ -n "$python_bin" ] || { echo "Python 3.11 or newer is required." >&2; exit 2; }
[ -f "$PELE_ROOT/scripts/harness-doctor.py" ] || { echo "Missing required source: scripts/harness-doctor.py" >&2; exit 2; }
[ "$HOST" = claude ] || [ -f "$PELE_ROOT/scripts/model-policy.py" ] || { echo "Missing required source: scripts/model-policy.py" >&2; exit 2; }

log() { printf '[pele-uninstall] %s\n' "$*"; }
remove_link() {
  local path="$1" target
  [ -L "$path" ] || return 0
  target="$(readlink "$path")"
  case "$target" in
    "$PELE_ROOT"/*)
      if [ "$DRY_RUN" = 1 ]; then log "would remove: $path"; else rm "$path"; fi
      ;;
  esac
}
remove_tree_links() {
  local target="$1" preserve="${2:-}"
  [ -d "$target" ] || return 0
  while IFS= read -r -d '' path; do
    [ "$path" = "$preserve" ] || remove_link "$path"
  done < <(find "$target" -type l -print0)
}
remove_host() {
  local host="$1" target="$2"
  [ -d "$target" ] || { log "nothing to remove in $target"; return; }
  if [ "$host" = claude ]; then
    "$python_bin" "$PELE_ROOT/scripts/harness-doctor.py" remove-hooks --target "$target" --settings "$target/settings.json" $([ "$DRY_RUN" = 1 ] && printf '%s' --dry-run)
  else
    local index="$target/AGENTS.md"
    local preserved_hook=""
    [ "$MODE" = project ] && index="$PROJECT_PATH/AGENTS.md"
    "$python_bin" "$PELE_ROOT/scripts/harness-doctor.py" index remove --path "$index" $([ "$DRY_RUN" = 1 ] && printf '%s' --dry-run)
    "$python_bin" "$PELE_ROOT/scripts/harness-doctor.py" codex-hooks --target "$target" --remove $([ "$DRY_RUN" = 1 ] && printf '%s' --dry-run)
    if "$python_bin" "$PELE_ROOT/scripts/harness-doctor.py" codex-hook-active --target "$target" >/dev/null; then
      preserved_hook="$target/hooks/protected-branch.sh"
      log "preserving hook script still referenced by a retained Codex hook: $preserved_hook"
    fi
    "$python_bin" "$PELE_ROOT/scripts/model-policy.py" uninstall --target "$target" $([ "$DRY_RUN" = 1 ] && printf '%s' --dry-run)
    remove_tree_links "$target" "$preserved_hook"
    log "removed $host links from $target"
    return
  fi
  remove_tree_links "$target"
  log "removed $host links from $target"
}

# Refuse redirected targets before touching either host or the project index.
for uninstall_target in "$CLAUDE_DIR" "$CODEX_DIR"; do
  [ "$HOST" != claude ] || [ "$uninstall_target" != "$CODEX_DIR" ] || continue
  [ "$HOST" != codex ] || [ "$uninstall_target" != "$CLAUDE_DIR" ] || continue
  [ ! -L "$uninstall_target" ] || { echo "Host target is a symlink; refusing to uninstall through it: $uninstall_target" >&2; exit 2; }
  if [ "$uninstall_target" = "$CODEX_DIR" ] && [ -L "$uninstall_target/agents" ] && [ -e "$uninstall_target/.harness-models.json" ]; then
    echo "Generated agents directory is a symlink; refusing to uninstall through it: $uninstall_target/agents" >&2
    exit 2
  fi
done

if [ "$HOST" = claude ] || [ "$HOST" = both ]; then remove_host claude "$CLAUDE_DIR"; fi
if [ "$HOST" = codex ] || [ "$HOST" = both ]; then remove_host codex "$CODEX_DIR"; fi
if [ "$MODE" = project ] && { [ "$HOST" = codex ] || [ "$HOST" = both ]; }; then
  remove_tree_links "$PROJECT_PATH/.agents/skills"
fi
