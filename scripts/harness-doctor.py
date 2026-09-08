#!/usr/bin/env python3
"""Validate and maintain Pele's host-specific installation boundaries."""

from __future__ import annotations

import argparse
import hashlib
import json
import shlex
import shutil
import sys
import tempfile
import tomllib
from pathlib import Path
from typing import Any


STATE_NAME = ".pele-managed.json"
MARKER_BEGIN = "<!-- pele:managed-index -->"
MARKER_END = "<!-- /pele:managed-index -->"
LEGACY_RELEASE_POST_TOOL_USE_HANDLER_DIGEST = "9d0b9a673a5d524cc57d9d41028b2db27da0d73060ad00c256240c11ed2a7622"


def fail(message: str) -> None:
    print(f"[pele] error: {message}", file=sys.stderr)
    raise SystemExit(2)


def canonical(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def digest(value: Any) -> str:
    return hashlib.sha256(canonical(value).encode()).hexdigest()


def load_json(path: Path, required: bool = True) -> dict[str, Any]:
    if not path.exists():
        if required:
            fail(f"required JSON file is missing: {path}")
        return {}
    try:
        result = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        fail(f"invalid JSON in {path}: {error}")
    if not isinstance(result, dict):
        fail(f"JSON root must be an object: {path}")
    return result


def load_state(target: Path) -> dict[str, Any]:
    state = load_json(target / STATE_NAME, required=False)
    if state and state.get("version") != 1:
        fail(f"unsupported or malformed managed state: {target / STATE_NAME}")
    return state or {"version": 1, "hooks": {}}


def write_json(path: Path, value: dict[str, Any], dry_run: bool) -> None:
    if dry_run:
        print(f"[pele] would write: {path}")
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", dir=path.parent, delete=False) as temporary:
        temporary.write(json.dumps(value, indent=2) + "\n")
        temporary_path = Path(temporary.name)
    temporary_path.replace(path)


def backup_file(path: Path, backup_dir: str | None, dry_run: bool) -> None:
    if not backup_dir or not path.exists():
        return
    destination = Path(backup_dir) / path.name
    if destination.exists():
        fail(f"refusing to overwrite backup: {destination}")
    if dry_run:
        print(f"[pele] would back up: {path} -> {destination}")
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(path, destination)


def write_state(target: Path, state: dict[str, Any], dry_run: bool) -> None:
    path = target / STATE_NAME
    empty = (
        set(state).issubset({"version", "hooks", "codex_hooks"})
        and not state.get("hooks")
        and not state.get("codex_hooks")
    )
    if empty:
        if path.exists():
            if dry_run:
                print(f"[pele] would remove: {path}")
            else:
                path.unlink()
        return
    write_json(path, state, dry_run)


def source_hooks(path: Path, root: Path) -> dict[str, list[dict[str, Any]]]:
    source = load_json(path)
    hooks = source.get("hooks")
    if not isinstance(hooks, dict):
        fail(f"hook source lacks an object hooks key: {path}")
    rendered: dict[str, list[dict[str, Any]]] = {}
    for event, entries in hooks.items():
        if not isinstance(event, str) or not isinstance(entries, list):
            fail(f"invalid hook event in {path}: {event!r}")
        rendered[event] = []
        for entry in entries:
            if not isinstance(entry, dict) or not isinstance(entry.get("_pele_id"), str):
                fail(f"each Pele hook requires string _pele_id: {path}")
            rendered[event].append(render_hook_entry(entry, root))
    return rendered


def render_hook_entry(value: Any, root: Path) -> Any:
    if isinstance(value, list):
        return [render_hook_entry(item, root) for item in value]
    if not isinstance(value, dict):
        return value
    rendered: dict[str, Any] = {}
    for key, item in value.items():
        if key == "command" and isinstance(item, str) and "@HARNESS_ROOT@" in item:
            prefix, suffix = item.split("@HARNESS_ROOT@", 1)
            if prefix or "@HARNESS_ROOT@" in suffix:
                fail("hook command must contain one bare @HARNESS_ROOT@ placeholder")
            rendered[key] = shlex.quote(str(root) + suffix)
        else:
            rendered[key] = render_hook_entry(item, root)
    return rendered


def managed_hooks(args: argparse.Namespace) -> None:
    target = Path(args.target)
    settings = Path(args.settings)
    source = source_hooks(Path(args.source), Path(args.root).resolve())
    state = load_state(target)
    known = state.setdefault("hooks", {})
    existing = load_json(settings, required=False)
    hooks = existing.setdefault("hooks", {})
    if not isinstance(hooks, dict):
        fail(f"settings hooks must be an object: {settings}")

    settings_changed = False
    state_changed = False
    if "PostToolUse" in hooks:
        post_tool_use = hooks["PostToolUse"]
        if not isinstance(post_tool_use, list):
            fail(f"settings hook event must be an array: {settings}#PostToolUse")
        retained_post_tool_use = []
        for entry in post_tool_use:
            commands = entry.get("hooks") if isinstance(entry, dict) else None
            if isinstance(entry, dict) and entry.get("matcher") == "Bash" and isinstance(commands, list):
                retained_commands = []
                for command in commands:
                    if digest(command) == LEGACY_RELEASE_POST_TOOL_USE_HANDLER_DIGEST:
                        print("[pele] removing legacy Pele Codex-review confirmation hook")
                        settings_changed = True
                        continue
                    retained_commands.append(command)
                retained_post_tool_use.append(dict(entry, hooks=retained_commands))
            else:
                retained_post_tool_use.append(entry)
        if settings_changed:
            hooks["PostToolUse"] = retained_post_tool_use
    for event, desired_entries in source.items():
        current_entries = hooks.setdefault(event, [])
        if not isinstance(current_entries, list):
            fail(f"settings hook event must be an array: {settings}#{event}")
        for desired in desired_entries:
            identifier = desired["_pele_id"]
            locations = [index for index, item in enumerate(current_entries)
                         if isinstance(item, dict) and item.get("_pele_id") == identifier]
            recorded = known.get(identifier)
            if not locations:
                current_entries.append(desired)
                known[identifier] = digest(desired)
                settings_changed = True
                state_changed = True
            elif len(locations) == 1 and recorded and digest(current_entries[locations[0]]) == recorded:
                if canonical(current_entries[locations[0]]) != canonical(desired):
                    current_entries[locations[0]] = desired
                    settings_changed = True
                if known[identifier] != digest(desired):
                    known[identifier] = digest(desired)
                    state_changed = True
            elif len(locations) == 1 and recorded is None and digest(current_entries[locations[0]]) == digest(desired):
                known[identifier] = digest(desired)
                state_changed = True
            else:
                print(f"[pele] preserving non-owned hook: {event}/{identifier}")

    if settings_changed:
        backup_file(settings, args.backup_dir, args.dry_run)
        write_json(settings, existing, args.dry_run)
    if settings_changed or state_changed:
        write_state(target, state, args.dry_run)
    else:
        print("[pele] hooks already installed or preserved")


def remove_hooks(args: argparse.Namespace) -> None:
    target = Path(args.target)
    settings = Path(args.settings)
    state = load_state(target)
    known = state.get("hooks", {})
    if not settings.exists() or not known:
        return
    existing = load_json(settings)
    hooks = existing.get("hooks", {})
    if not isinstance(hooks, dict):
        fail(f"settings hooks must be an object: {settings}")
    changed = False
    for event, entries in hooks.items():
        if not isinstance(entries, list):
            fail(f"settings hook event must be an array: {settings}#{event}")
        retained = []
        for entry in entries:
            identifier = entry.get("_pele_id") if isinstance(entry, dict) else None
            if identifier in known and digest(entry) == known[identifier]:
                print(f"[pele] removing managed hook: {event}/{identifier}")
                changed = True
                continue
            retained.append(entry)
        hooks[event] = retained
    if changed:
        backup_file(settings, args.backup_dir, args.dry_run)
        write_json(settings, existing, args.dry_run)
    state["hooks"] = {}
    write_state(target, state, args.dry_run)


def codex_hook_owned(handler: Any) -> bool:
    return isinstance(handler, dict) and "# pele:protected-branch" in handler.get("command", "")


def codex_hooks(args: argparse.Namespace) -> None:
    target = Path(args.target)
    path = target / "hooks.json"
    state = load_state(target)
    known = state.setdefault("codex_hooks", {})
    document = load_json(path, required=False)
    hooks = document.setdefault("hooks", {})
    if not isinstance(hooks, dict):
        fail(f"hooks.json hooks must be an object: {path}")
    groups = hooks.setdefault("PreToolUse", [])
    if not isinstance(groups, list):
        fail(f"hooks.json PreToolUse must be an array: {path}")
    desired = {
        "type": "command",
        "command": f"bash {shlex.quote(str(target / 'hooks' / 'protected-branch.sh'))} # pele:protected-branch",
    }
    desired_hash = digest(desired)
    desired_matcher = "^apply_patch$"
    settings_changed = False
    state_changed = False
    retained_groups = []
    owned_present = False
    desired_present = False
    migration_required = False
    for group in groups:
        if not isinstance(group, dict) or not isinstance(group.get("hooks", []), list):
            fail(f"invalid Codex hook group: {path}")
        retained_handlers = []
        matcher = group.get("matcher")
        if not args.remove and matcher == "" and len(group["hooks"]) == 1:
            handler = group["hooks"][0]
            if codex_hook_owned(handler) and known.get("protected-branch") == digest(handler):
                print("[pele] migrating managed Codex protected-branch hook")
                retained_groups.append(dict(group, matcher=desired_matcher))
                settings_changed = True
                desired_present = True
                migration_required = True
                continue
        for handler in group["hooks"]:
            if codex_hook_owned(handler):
                recorded = known.get("protected-branch")
                if args.remove:
                    if recorded == digest(handler):
                        print("[pele] removing managed Codex protected-branch hook")
                        settings_changed = True
                        continue
                    print("[pele] preserving modified Codex protected-branch hook")
                    owned_present = True
                elif recorded == digest(handler):
                    if matcher == desired_matcher:
                        retained_handlers.append(handler)
                        owned_present = True
                        desired_present = True
                        continue
                    if matcher == "":
                        print("[pele] migrating managed Codex protected-branch hook")
                        settings_changed = True
                        migration_required = True
                        continue
                    print("[pele] preserving custom Codex protected-branch matcher")
                    owned_present = True
                else:
                    print("[pele] preserving modified Codex protected-branch hook")
                    owned_present = True
            retained_handlers.append(handler)
        if retained_handlers or not group["hooks"]:
            retained_groups.append(dict(group, hooks=retained_handlers))
    if not args.remove and not desired_present and (migration_required or not owned_present):
        retained_groups.append({"matcher": desired_matcher, "hooks": [desired]})
        if known.get("protected-branch") != desired_hash:
            known["protected-branch"] = desired_hash
            state_changed = True
        settings_changed = True
    if args.remove:
        if "protected-branch" in known:
            known.pop("protected-branch")
            state_changed = True
    hooks["PreToolUse"] = retained_groups
    if settings_changed:
        backup_file(path, args.backup_dir, args.dry_run)
        write_json(path, document, args.dry_run)
    if settings_changed or state_changed:
        write_state(target, state, args.dry_run)
    else:
        print("[pele] Codex hooks already installed or preserved")


def index_text(entry: str) -> str:
    return f"\n{MARKER_BEGIN}\n{entry}\n{MARKER_END}\n"


def manage_index(args: argparse.Namespace) -> None:
    path = Path(args.path)
    if path.is_symlink() and not path.exists():
        fail(f"refusing to follow dangling managed index symlink: {path}")
    content = path.read_text() if path.exists() else ""
    if args.action == "remove" and path.is_symlink():
        print(f"[pele] preserving non-owned index symlink: {path}")
        return
    begin = content.find(MARKER_BEGIN)
    end = content.find(MARKER_END)
    if args.action == "install":
        replacement = f"{MARKER_BEGIN}\n{args.entry}\n{MARKER_END}"
        if begin >= 0 and end >= begin:
            end += len(MARKER_END)
            updated = content[:begin] + replacement + content[end:]
        elif begin >= 0 or end >= 0:
            fail(f"incomplete managed index marker: {path}")
        else:
            updated = content.rstrip() + "\n" + replacement + "\n"
        if updated != content:
            if args.dry_run:
                print(f"[pele] would update managed index: {path}")
            else:
                if path.is_symlink():
                    backup_index_symlink(path, args.backup_dir)
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(updated)
        return
    if begin < 0 and end < 0:
        return
    if begin < 0 or end < begin:
        print(f"[pele] preserving modified index with incomplete marker: {path}")
        return
    end += len(MARKER_END)
    updated = (content[:begin] + content[end:]).strip()
    if args.dry_run:
        print(f"[pele] would remove managed index: {path}")
    elif updated:
        path.write_text(updated + "\n")
    else:
        path.unlink()


def backup_index_symlink(path: Path, backup_dir: str | None) -> None:
    if not backup_dir:
        fail(f"managed index symlink requires a backup directory: {path}")
    destination = Path(backup_dir) / path.name
    if destination.exists() or destination.is_symlink():
        fail(f"refusing to overwrite index symlink backup: {destination}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    path.rename(destination)
    print(f"[pele] backed up index symlink: {path} -> {destination}")


def codex_hook_active(args: argparse.Namespace) -> None:
    path = Path(args.target) / "hooks.json"
    if not path.exists():
        raise SystemExit(1)
    document = load_json(path)
    hooks = document.get("hooks")
    if not isinstance(hooks, dict):
        fail(f"hooks.json hooks must be an object: {path}")
    script = str(Path(args.target) / "hooks" / "protected-branch.sh")
    if any(
        isinstance(handler, dict) and script in handler.get("command", "")
        for groups in hooks.values() if isinstance(groups, list)
        for group in groups if isinstance(group, dict) and isinstance(group.get("hooks"), list)
        for handler in group["hooks"]
    ):
        print(f"[pele] preserved Codex hook still references: {script}")
        return
    raise SystemExit(1)


def doctor(args: argparse.Namespace) -> None:
    requested_root = Path(args.root).resolve()
    script_root = Path(__file__).resolve().parent.parent
    root = requested_root if (requested_root / "core").is_dir() else script_root
    target = Path(args.target)
    required = [root / "core" / "CLAUDE.md", root / "scripts" / "harness-root.sh"]
    missing = [str(path) for path in required if not path.is_file()]
    if missing:
        fail("missing required source: " + ", ".join(missing))
    if not target.exists():
        fail(f"installation target does not exist: {target}")
    dangling = []
    for path in target.rglob("*"):
        if path.is_symlink() and not path.exists():
            dangling.append(str(path))
    if dangling:
        fail("dangling links: " + ", ".join(dangling))
    if args.host == "codex":
        for relative in ("agents", "skills", "scripts", "hooks", "hooks.json"):
            if not (target / relative).exists():
                fail(f"Codex installation lacks {relative}: {target}")
        hook_document = load_json(target / "hooks.json")
        hook_events = hook_document.get("hooks")
        if not isinstance(hook_events, dict):
            fail(f"hooks.json hooks must be an object: {target / 'hooks.json'}")
        for agent in (target / "agents").glob("*.toml"):
            try:
                tomllib.loads(agent.read_text())
            except (OSError, tomllib.TOMLDecodeError) as error:
                fail(f"invalid generated agent TOML {agent}: {error}")
        handlers = hook_events.get("PreToolUse", [])
        if not isinstance(handlers, list):
            fail(f"hooks.json PreToolUse must be an array: {target / 'hooks.json'}")
        if not any(
            codex_hook_owned(handler)
            for group in handlers if isinstance(group, dict)
            for handler in group.get("hooks", []) if isinstance(group.get("hooks", []), list)
        ):
            fail(f"Codex installation lacks the managed protected-branch hook: {target}")
    else:
        settings = target / "settings.json"
        if settings.exists():
            load_json(settings)
        if not (target / "hooks" / "protected-branch.sh").exists():
            fail(f"Claude installation lacks the protected-branch script: {target}")
    if not (target / "scripts" / "harness-root.sh").exists():
        fail(f"installation lacks harness-root helper: {target}")
    print(f"[pele] doctor passed: {args.host} {target}")


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser()
    sub = result.add_subparsers(dest="command", required=True)
    merge = sub.add_parser("merge-hooks")
    merge.add_argument("--target", required=True)
    merge.add_argument("--settings", required=True)
    merge.add_argument("--source", required=True)
    merge.add_argument("--root", required=True)
    merge.add_argument("--backup-dir")
    merge.add_argument("--dry-run", action="store_true")
    merge.set_defaults(func=managed_hooks)
    remove = sub.add_parser("remove-hooks")
    remove.add_argument("--target", required=True)
    remove.add_argument("--settings", required=True)
    remove.add_argument("--backup-dir")
    remove.add_argument("--dry-run", action="store_true")
    remove.set_defaults(func=remove_hooks)
    codex = sub.add_parser("codex-hooks")
    codex.add_argument("--target", required=True)
    codex.add_argument("--backup-dir")
    codex.add_argument("--dry-run", action="store_true")
    codex.add_argument("--remove", action="store_true")
    codex.set_defaults(func=codex_hooks)
    index = sub.add_parser("index")
    index.add_argument("action", choices=("install", "remove"))
    index.add_argument("--path", required=True)
    index.add_argument("--entry", default="")
    index.add_argument("--backup-dir")
    index.add_argument("--dry-run", action="store_true")
    index.set_defaults(func=manage_index)
    check = sub.add_parser("doctor")
    check.add_argument("--root", required=True)
    check.add_argument("--target", required=True)
    check.add_argument("--host", choices=("claude", "codex"), required=True)
    check.set_defaults(func=doctor)
    active = sub.add_parser("codex-hook-active")
    active.add_argument("--target", required=True)
    active.set_defaults(func=codex_hook_active)
    return result


if __name__ == "__main__":
    if sys.version_info < (3, 11):
        fail("Python 3.11 or newer is required")
    arguments = parser().parse_args()
    arguments.func(arguments)
