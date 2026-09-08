#!/usr/bin/env bash
# Exercise Pele installs in temporary homes. It never reads a live host config.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
PYTHON_BIN="${PYTHON_BIN:-python3}"
"$PYTHON_BIN" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)' || {
  echo "Python 3.11 or newer is required." >&2
  exit 2
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fixture_home="$tmp/home"
codex_home="$tmp/custom codex home"
project="$tmp/project with spaces"
dry_project="$tmp/dry project"
project_codex_symlink="$tmp/project codex symlink"
global_target="$tmp/global target"
global_target_symlink="$tmp/global target symlink"
legacy_skills="$tmp/legacy skills"
private_agents="$tmp/private-agents.md"
mkdir -p "$fixture_home/.claude" "$codex_home" "$project/.codex" "$legacy_skills"
printf 'preserve me\n' > "$legacy_skills/legacy.txt"
ln -s "../../$(basename "$legacy_skills")" "$project/.codex/skills"
mkdir -p "$legacy_skills/plan-first-delivery"
printf "original source skill\n" > "$legacy_skills/plan-first-delivery/SKILL.md"

printf '%s\n' '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"printf %s hook-ran >/dev/null"}]}]}}' > "$fixture_home/.claude/settings.json"
printf '%s\n' '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"third-party-hook"}]}]}}' > "$codex_home/hooks.json"
printf 'Private global instructions.\n' > "$private_agents"
ln -s "$private_agents" "$codex_home/AGENTS.md"
printf 'User project instructions.\n' > "$project/AGENTS.md"

snapshot_tree() {
  "$PYTHON_BIN" - "$1" <<'PY'
import hashlib, os, sys
from pathlib import Path

root = Path(sys.argv[1])
for path in sorted(root.rglob("*")):
    relative = path.relative_to(root)
    if path.is_symlink():
        print("link", relative, os.readlink(path))
    elif path.is_file():
        print("file", relative, hashlib.sha256(path.read_bytes()).hexdigest())
    elif path.is_dir():
        print("dir", relative)
PY
}

legacy_before="$(snapshot_tree "$legacy_skills")"
env HOME="$fixture_home" CODEX_HOME="$codex_home" "$ROOT/install.sh" --host claude --force
env HOME="$fixture_home" CODEX_HOME="$codex_home" "$ROOT/install.sh" --host codex --force
repeat_before="$(snapshot_tree "$tmp")"
env HOME="$fixture_home" CODEX_HOME="$codex_home" "$ROOT/install.sh" --host both --force
repeat_after="$(snapshot_tree "$tmp")"
test "$repeat_before" = "$repeat_after"
env HOME="$fixture_home" CODEX_HOME="$codex_home" "$ROOT/install.sh" --host codex --project "$project" --force
env HOME="$fixture_home" CODEX_HOME="$codex_home" "$ROOT/install.sh" --host claude --project "$project" --force

"$PYTHON_BIN" "$ROOT/scripts/harness-doctor.py" doctor --root "$ROOT" --target "$fixture_home/.claude" --host claude
"$PYTHON_BIN" "$ROOT/scripts/harness-doctor.py" doctor --root "$ROOT" --target "$codex_home" --host codex
"$PYTHON_BIN" "$ROOT/scripts/harness-doctor.py" doctor --root "$ROOT" --target "$project/.codex" --host codex

"$PYTHON_BIN" - "$fixture_home/.claude/settings.json" "$codex_home/hooks.json" "$codex_home/agents" <<'PY'
import json, sys, tomllib
from pathlib import Path

settings = json.loads(Path(sys.argv[1]).read_text())
assert settings["hooks"]["PreToolUse"][0]["hooks"][0]["command"] == "printf %s hook-ran >/dev/null"
hooks = json.loads(Path(sys.argv[2]).read_text())
assert hooks["hooks"]["PreToolUse"][0]["hooks"][0]["command"] == "third-party-hook"
for path in Path(sys.argv[3]).glob("*.toml"):
    tomllib.loads(path.read_text())
PY

grep -Fq 'Private global instructions.' "$codex_home/AGENTS.md"
grep -Fq 'pele:managed-index' "$codex_home/AGENTS.md"
grep -Fq 'Private global instructions.' "$private_agents"
grep -Fq 'User project instructions.' "$project/AGENTS.md"
test -e "$project/.codex/agents"
test -e "$project/.codex/hooks/protected-branch.sh"
test -e "$project/.agents/skills"
test -f "$project/.codex/skills/legacy.txt"
test ! -L "$project/.codex/skills"
test "$legacy_before" = "$(snapshot_tree "$legacy_skills")"

dry_before="$(snapshot_tree "$tmp")"
env HOME="$fixture_home" CODEX_HOME="$codex_home" "$ROOT/install.sh" --host codex --project "$dry_project" --dry-run
dry_after="$(snapshot_tree "$tmp")"
test "$dry_before" = "$dry_after"

mkdir -p "$project_codex_symlink"
printf 'Keep this project AGENTS file unchanged.\n' > "$project_codex_symlink/AGENTS.md"
ln -s "$codex_home" "$project_codex_symlink/.codex"
symlink_before="$(snapshot_tree "$tmp")"
if env HOME="$fixture_home" CODEX_HOME="$codex_home" "$ROOT/install.sh" --host codex --project "$project_codex_symlink" --force; then
  echo 'project Codex target symlink installation unexpectedly succeeded' >&2
  exit 1
fi
symlink_after="$(snapshot_tree "$tmp")"
test "$symlink_before" = "$symlink_after"
grep -Fqx 'Keep this project AGENTS file unchanged.' "$project_codex_symlink/AGENTS.md"

mkdir -p "$global_target"
ln -s "$global_target" "$global_target_symlink"
global_symlink_before="$(snapshot_tree "$tmp")"
if env HOME="$fixture_home" CODEX_HOME="$global_target_symlink" "$ROOT/install.sh" --host codex --force; then
  echo 'global-target symlink installation unexpectedly succeeded' >&2
  exit 1
fi
if env HOME="$fixture_home" CODEX_HOME="$global_target_symlink" "$ROOT/uninstall.sh" --host codex; then
  echo 'global-target symlink uninstall unexpectedly succeeded' >&2
  exit 1
fi
global_symlink_after="$(snapshot_tree "$tmp")"
test "$global_symlink_before" = "$global_symlink_after"

perl -0pi -e 's/# pele:protected-branch/# pele:protected-branch user-modified/' "$codex_home/hooks.json"

env HOME="$fixture_home" CODEX_HOME="$codex_home" "$ROOT/uninstall.sh" --host both
env HOME="$fixture_home" CODEX_HOME="$codex_home" "$ROOT/uninstall.sh" --host both --project "$project"

"$PYTHON_BIN" - "$fixture_home/.claude/settings.json" "$codex_home/hooks.json" <<'PY'
import json, sys
settings = json.loads(open(sys.argv[1]).read())
assert settings["hooks"]["PreToolUse"] == [{"matcher": "Bash", "hooks": [{"type": "command", "command": "printf %s hook-ran >/dev/null"}]}]
hooks = json.loads(open(sys.argv[2]).read())
assert hooks["hooks"]["PreToolUse"][0] == {"matcher": "Bash", "hooks": [{"type": "command", "command": "third-party-hook"}]}
assert "user-modified" in hooks["hooks"]["PreToolUse"][1]["hooks"][0]["command"]
PY
test -L "$codex_home/hooks/protected-branch.sh"
grep -Fq 'Private global instructions.' "$codex_home/AGENTS.md"
! grep -Fq 'pele:managed-index' "$codex_home/AGENTS.md"
grep -Fq 'User project instructions.' "$project/AGENTS.md"
! grep -Fq 'pele:managed-index' "$project/AGENTS.md"

echo '[pele] temporary installation matrix passed'
