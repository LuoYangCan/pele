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
assert "PostToolUse" not in settings["hooks"]
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

hook_repo="$tmp/hook fixture"
git init -q -b main "$hook_repo"
read_output="$(printf '%s' "{\"cwd\":\"$hook_repo\",\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"README.md\"}}" | "$codex_home/hooks/protected-branch.sh")"
test -z "$read_output"
write_output="$(printf '%s' "{\"cwd\":\"$hook_repo\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"README.md\"}}" | "$codex_home/hooks/protected-branch.sh")"
printf '%s' "$write_output" | grep -Fq 'protected branch main'

codex_migration="$tmp/codex migration"
claude_migration="$tmp/claude migration"
mkdir -p "$codex_migration" "$claude_migration"
"$PYTHON_BIN" - "$codex_migration" "$claude_migration" <<'PY'
import base64, hashlib, json, shlex, sys
from pathlib import Path

codex_target, claude_target = map(Path, sys.argv[1:])
legacy = json.loads(base64.b64decode(
    "eyJ0eXBlIjoiY29tbWFuZCIsImNvbW1hbmQiOiJDTUQ9JChqcSAtciAnLnRvb2xfaW5wdXQuY29tbWFuZCAvLyBlbXB0eScpOyBpZiBlY2hvIFwiJENNRFwiIHwgZ3JlcCAtRXEgJ2NvZGV4LWNvbXBhbmlvblxcLm1qc1tcIidcIidcIidbOnNwYWNlOl1dKyhyZXZpZXd8YWR2ZXJzYXJpYWwtcmV2aWV3KVxcYic7IHRoZW4gcHJpbnRmICclcycgJ3tcImhvb2tTcGVjaWZpY091dHB1dFwiOntcImhvb2tFdmVudE5hbWVcIjpcIlBvc3RUb29sVXNlXCIsXCJhZGRpdGlvbmFsQ29udGV4dFwiOlwiQSBDb2RleCByZXZpZXcganVzdCBmaW5pc2hlZC4gSW4geW91ciBuZXh0IHJlcGx5LCBkbyB0d28gdGhpbmdzOiAoMSkgQnJpZWZseSBldmFsdWF0ZSB0aGlzIHJldmlldyBpbiAzLTUgc2VudGVuY2VzIFx1MjAxNCB3aGljaCBhcmUgcmVhbCBpc3N1ZXMsIHdoaWNoIGFyZSBuaXRwaWNrcyBvciBmYWxzZSBwb3NpdGl2ZXMsIHdoZXRoZXIgY2hhbmdlcyBhcmUgbWFuZGF0b3J5IG92ZXJhbGw7ICgyKSBUaGVuIHVzZSB0aGUgQXNrVXNlclF1ZXN0aW9uIHRvb2wgdG8gYXNrIHRoZSB1c2VyIHdoZXRoZXIgdG8gYXBwbHkgdGhlIHJldmlldyBzdWdnZXN0aW9ucywgd2l0aCAzIG9wdGlvbnMgKGUuZy4gYXBwbHkgYWxsIC8gYXBwbHkgb25seSBjcml0aWNhbCBvbmVzIC8gc2tpcCBmb3Igbm93LCBJIHdpbGwgZGVjaWRlIG15c2VsZikuIERvIG5vdCBzdGFydCBlZGl0aW5nIGNvZGUgZmlyc3Q7IHdhaXQgZm9yIHRoZSB1c2VyIGNob2ljZS5cIn19JzsgZmkifQ=="
).decode())
modified_legacy = dict(legacy, command=legacy["command"] + " user-modified")
desired = {
    "type": "command",
    "command": f"bash {shlex.quote(str(codex_target / 'hooks' / 'protected-branch.sh'))} # pele:protected-branch",
}
digest = lambda value: hashlib.sha256(
    json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
).hexdigest()
assert digest(legacy) == "9d0b9a673a5d524cc57d9d41028b2db27da0d73060ad00c256240c11ed2a7622"

(codex_target / "hooks.json").write_text(json.dumps({
    "hooks": {
        "PreToolUse": [
            {"matcher": "", "metadata": "single", "hooks": [desired]},
            {"matcher": "", "metadata": "mixed", "hooks": [desired, {"type": "command", "command": "third-party-hook"}]},
            {"matcher": "Bash", "metadata": "empty", "hooks": []},
        ]
    }
}))
(codex_target / ".pele-managed.json").write_text(json.dumps({
    "version": 1,
    "hooks": {},
    "codex_hooks": {"protected-branch": digest(desired)},
}))

custom_target = codex_target.parent / "custom matcher"
modified_target = codex_target.parent / "modified handler"
mixed_custom_target = codex_target.parent / "mixed custom"
mixed_desired_target = codex_target.parent / "mixed desired"
custom_target.mkdir()
modified_target.mkdir()
mixed_custom_target.mkdir()
mixed_desired_target.mkdir()
custom_desired = {
    "type": "command",
    "command": f"bash {shlex.quote(str(custom_target / 'hooks' / 'protected-branch.sh'))} # pele:protected-branch",
}
modified_desired = {
    "type": "command",
    "command": f"bash {shlex.quote(str(modified_target / 'hooks' / 'protected-branch.sh'))} # pele:protected-branch",
}
(custom_target / "hooks.json").write_text(json.dumps({"hooks": {"PreToolUse": [
    {"matcher": "Bash", "metadata": "custom", "hooks": [custom_desired]},
]}}))
(custom_target / ".pele-managed.json").write_text(json.dumps({
    "version": 1, "hooks": {}, "codex_hooks": {"protected-branch": digest(custom_desired)},
}))
modified_handler = dict(modified_desired, command=modified_desired["command"] + " user-modified")
(modified_target / "hooks.json").write_text(json.dumps({"hooks": {"PreToolUse": [
    {"matcher": "", "metadata": "modified", "hooks": [modified_handler]},
]}}))
(modified_target / ".pele-managed.json").write_text(json.dumps({
    "version": 1, "hooks": {}, "codex_hooks": {"protected-branch": digest(modified_desired)},
}))
mixed_custom_desired = {
    "type": "command",
    "command": f"bash {shlex.quote(str(mixed_custom_target / 'hooks' / 'protected-branch.sh'))} # pele:protected-branch",
}
(mixed_custom_target / "hooks.json").write_text(json.dumps({"hooks": {"PreToolUse": [
    {"matcher": "", "metadata": "old-mixed", "hooks": [mixed_custom_desired, {"type": "command", "command": "third-party-hook"}]},
    {"matcher": "Bash", "metadata": "custom", "hooks": [mixed_custom_desired]},
]}}))
(mixed_custom_target / ".pele-managed.json").write_text(json.dumps({
    "version": 1, "hooks": {}, "codex_hooks": {"protected-branch": digest(mixed_custom_desired)},
}))
mixed_desired_handler = {
    "type": "command",
    "command": f"bash {shlex.quote(str(mixed_desired_target / 'hooks' / 'protected-branch.sh'))} # pele:protected-branch",
}
(mixed_desired_target / "hooks.json").write_text(json.dumps({"hooks": {"PreToolUse": [
    {"matcher": "", "metadata": "old-mixed", "hooks": [mixed_desired_handler, {"type": "command", "command": "third-party-hook"}]},
    {"matcher": "^apply_patch$", "metadata": "desired", "hooks": [mixed_desired_handler]},
]}}))
(mixed_desired_target / ".pele-managed.json").write_text(json.dumps({
    "version": 1, "hooks": {}, "codex_hooks": {"protected-branch": digest(mixed_desired_handler)},
}))

claude_settings = {
    "hooks": {
        "PostToolUse": [
            {"matcher": "Bash", "metadata": "keep", "hooks": [legacy, {"type": "command", "command": "third-party-hook"}]},
            {"matcher": "Bash", "hooks": [modified_legacy]},
            {"matcher": "Read", "hooks": [legacy]},
        ]
    }
}
(claude_target / "settings.json").write_text(json.dumps(claude_settings))
PY

custom_only_before="$(snapshot_tree "$codex_migration/../custom matcher")"
modified_only_before="$(snapshot_tree "$codex_migration/../modified handler")"
"$PYTHON_BIN" "$ROOT/scripts/harness-doctor.py" codex-hooks --target "$codex_migration"
"$PYTHON_BIN" "$ROOT/scripts/harness-doctor.py" codex-hooks --target "$codex_migration/../custom matcher"
"$PYTHON_BIN" "$ROOT/scripts/harness-doctor.py" codex-hooks --target "$codex_migration/../modified handler"
"$PYTHON_BIN" "$ROOT/scripts/harness-doctor.py" codex-hooks --target "$codex_migration/../mixed custom"
"$PYTHON_BIN" "$ROOT/scripts/harness-doctor.py" codex-hooks --target "$codex_migration/../mixed desired"
"$PYTHON_BIN" "$ROOT/scripts/harness-doctor.py" merge-hooks --target "$claude_migration" --settings "$claude_migration/settings.json" --source "$ROOT/core/hooks/settings.hooks.json" --root "$ROOT"
test "$custom_only_before" = "$(snapshot_tree "$codex_migration/../custom matcher")"
test "$modified_only_before" = "$(snapshot_tree "$codex_migration/../modified handler")"

"$PYTHON_BIN" - "$codex_migration/hooks.json" "$codex_migration/../custom matcher/hooks.json" "$codex_migration/../modified handler/hooks.json" "$codex_migration/../mixed custom/hooks.json" "$codex_migration/../mixed desired/hooks.json" "$claude_migration/settings.json" <<'PY'
import json, sys
from pathlib import Path

codex = json.loads(Path(sys.argv[1]).read_text())
groups = codex["hooks"]["PreToolUse"]
assert groups[0]["matcher"] == "^apply_patch$" and groups[0]["metadata"] == "single"
assert "pele:protected-branch" in groups[0]["hooks"][0]["command"]
assert groups[1] == {"matcher": "", "metadata": "mixed", "hooks": [{"type": "command", "command": "third-party-hook"}]}
assert groups[2] == {"matcher": "Bash", "metadata": "empty", "hooks": []}
assert len(groups) == 3
custom = json.loads(Path(sys.argv[2]).read_text())["hooks"]["PreToolUse"]
assert custom[0]["matcher"] == "Bash" and custom[0]["metadata"] == "custom"
assert "pele:protected-branch" in custom[0]["hooks"][0]["command"]
modified = json.loads(Path(sys.argv[3]).read_text())["hooks"]["PreToolUse"]
assert modified[0]["matcher"] == "" and modified[0]["metadata"] == "modified"
assert modified[0]["hooks"][0]["command"].endswith("user-modified")
mixed_custom = json.loads(Path(sys.argv[4]).read_text())["hooks"]["PreToolUse"]
assert mixed_custom[0] == {"matcher": "", "metadata": "old-mixed", "hooks": [{"type": "command", "command": "third-party-hook"}]}
assert mixed_custom[1]["matcher"] == "Bash" and mixed_custom[1]["metadata"] == "custom"
assert mixed_custom[2]["matcher"] == "^apply_patch$"
mixed_desired = json.loads(Path(sys.argv[5]).read_text())["hooks"]["PreToolUse"]
assert mixed_desired[0] == {"matcher": "", "metadata": "old-mixed", "hooks": [{"type": "command", "command": "third-party-hook"}]}
assert mixed_desired[1]["matcher"] == "^apply_patch$" and mixed_desired[1]["metadata"] == "desired"
assert len(mixed_desired) == 2

settings = json.loads(Path(sys.argv[6]).read_text())
post = settings["hooks"]["PostToolUse"]
assert post[0]["metadata"] == "keep"
assert post[0]["hooks"] == [{"type": "command", "command": "third-party-hook"}]
assert post[1]["hooks"][0]["command"].endswith("user-modified")
assert "codex-companion\\.mjs" in post[2]["hooks"][0]["command"]
PY

migration_before="$(snapshot_tree "$codex_migration")$(snapshot_tree "$codex_migration/../custom matcher")$(snapshot_tree "$codex_migration/../modified handler")$(snapshot_tree "$codex_migration/../mixed custom")$(snapshot_tree "$codex_migration/../mixed desired")$(snapshot_tree "$claude_migration")"
"$PYTHON_BIN" "$ROOT/scripts/harness-doctor.py" codex-hooks --target "$codex_migration"
"$PYTHON_BIN" "$ROOT/scripts/harness-doctor.py" codex-hooks --target "$codex_migration/../custom matcher"
"$PYTHON_BIN" "$ROOT/scripts/harness-doctor.py" codex-hooks --target "$codex_migration/../modified handler"
"$PYTHON_BIN" "$ROOT/scripts/harness-doctor.py" codex-hooks --target "$codex_migration/../mixed custom"
"$PYTHON_BIN" "$ROOT/scripts/harness-doctor.py" codex-hooks --target "$codex_migration/../mixed desired"
"$PYTHON_BIN" "$ROOT/scripts/harness-doctor.py" merge-hooks --target "$claude_migration" --settings "$claude_migration/settings.json" --source "$ROOT/core/hooks/settings.hooks.json" --root "$ROOT"
migration_after="$(snapshot_tree "$codex_migration")$(snapshot_tree "$codex_migration/../custom matcher")$(snapshot_tree "$codex_migration/../modified handler")$(snapshot_tree "$codex_migration/../mixed custom")$(snapshot_tree "$codex_migration/../mixed desired")$(snapshot_tree "$claude_migration")"
test "$migration_before" = "$migration_after"

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
