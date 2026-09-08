#!/usr/bin/env python3
"""Resolve and install the shared Codex model policy without TOML dependencies."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import shlex
import sys
import tempfile
import time


VALID_EFFORTS = {"none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra"}
POLICY_FILE = "model-policy.json"
MANIFEST_FILE = ".harness-models.json"


class PolicyError(Exception):
    pass


def fail(message):
    print("model-policy: {}".format(message), file=sys.stderr)
    return 2


def harness_root():
    root = Path(__file__).resolve().parent.parent
    if (root / "config" / POLICY_FILE).is_file() or (root / "core" / "config" / POLICY_FILE).is_file():
        return root
    raise PolicyError("cannot find config/{} relative to {}".format(POLICY_FILE, root))


def source_path(root, relative):
    direct = root / relative
    if direct.exists():
        return direct
    core = root / "core" / relative
    if core.exists():
        return core
    return direct


def read_json(path, label):
    try:
        with path.open(encoding="utf-8") as handle:
            value = json.load(handle)
    except OSError as error:
        raise PolicyError("cannot read {} {}: {}".format(label, path, error))
    except json.JSONDecodeError as error:
        raise PolicyError("invalid JSON in {} {}: {}".format(label, path, error))
    if not isinstance(value, dict):
        raise PolicyError("{} {} must be a JSON object".format(label, path))
    return value


def validate_roles(value, label, known_roles=None, partial=False):
    if set(value) != {"roles"} or not isinstance(value["roles"], dict):
        raise PolicyError("{} must contain only a roles object".format(label))
    roles = {}
    for role, entry in value["roles"].items():
        if not isinstance(role, str) or not role:
            raise PolicyError("{} has an empty or invalid role name".format(label))
        if known_roles is not None and role not in known_roles:
            raise PolicyError("{} names unknown role {}".format(label, role))
        if not isinstance(entry, dict) or not entry or set(entry) - {"model", "effort"}:
            raise PolicyError("{} role {} may contain only model and effort".format(label, role))
        if not partial and set(entry) != {"model", "effort"}:
            raise PolicyError("{} role {} must define model and effort".format(label, role))
        checked = {}
        if "model" in entry:
            if not isinstance(entry["model"], str) or not entry["model"].strip():
                raise PolicyError("{} role {} has an empty model".format(label, role))
            checked["model"] = entry["model"]
        if "effort" in entry:
            if entry["effort"] not in VALID_EFFORTS:
                raise PolicyError("{} role {} has invalid effort {}".format(label, role, entry["effort"]))
            checked["effort"] = entry["effort"]
        roles[role] = checked
    return roles


def local_policy_path():
    codex_home = Path(os.environ.get("CODEX_HOME", Path.home() / ".codex")).expanduser()
    return codex_home / "model-policy.local.json"


def resolve_policy(repo=None):
    root = harness_root()
    default_path = source_path(root, Path("config") / POLICY_FILE)
    defaults = validate_roles(read_json(default_path, "default policy"), "default policy")
    known = set(defaults)
    resolved = {role: dict(value) for role, value in defaults.items()}
    sources = {role: {"model": str(default_path), "effort": str(default_path)} for role in defaults}
    overlays = [(local_policy_path(), "local policy")]
    if repo is not None:
        overlays.append((Path(repo).expanduser().resolve() / ".codex" / POLICY_FILE, "repository policy"))
    for path, label in overlays:
        if not path.exists():
            continue
        overlay = validate_roles(read_json(path, label), label, known, partial=True)
        for role, entry in overlay.items():
            for key, value in entry.items():
                resolved[role][key] = value
                sources[role][key] = str(path)
    return resolved, sources, root


def policy_for(role, repo=None, model=None, effort=None):
    resolved, sources, root = resolve_policy(repo)
    if role not in resolved:
        raise PolicyError("unknown role {}".format(role))
    result = dict(resolved[role])
    result_sources = dict(sources[role])
    if model is not None:
        if not model.strip():
            raise PolicyError("CLI model must not be empty")
        result["model"] = model
        result_sources["model"] = "CLI"
    if effort is not None:
        if effort not in VALID_EFFORTS:
            raise PolicyError("CLI effort has invalid value {}".format(effort))
        result["effort"] = effort
        result_sources["effort"] = "CLI"
    return result, result_sources, root


def render_template(template, policy, root):
    root_value = shlex.quote(str(root)).replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\r", "\\r")
    rendered = template.read_text(encoding="utf-8").replace("@HARNESS_ROOT@", root_value)
    lines = rendered.splitlines(keepends=True)
    for index, line in enumerate(lines):
        if line.startswith("description = "):
            lines[index + 1:index + 1] = [
                "model = {}\n".format(json.dumps(policy["model"], ensure_ascii=False)),
                "model_reasoning_effort = {}\n".format(json.dumps(policy["effort"], ensure_ascii=False)),
            ]
            return "".join(lines)
    raise PolicyError("template {} has no description field".format(template))


def backup_agents(path, backup_dir, dry_run):
    timestamp = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
    destination = Path(backup_dir).expanduser().resolve() if backup_dir else path.parent / ".model-policy-backups" / timestamp
    backup = destination / "agents"
    if dry_run:
        print("would back up symlink {} -> {}".format(path, backup))
        return
    backup.parent.mkdir(parents=True, exist_ok=True)
    if backup.exists() or backup.is_symlink():
        raise PolicyError("backup destination already exists: {}".format(backup))
    shutil.move(str(path), str(backup))
    path.mkdir()
    print("backed up symlink {} -> {}".format(path, backup))


def unknown_agent_files(path, managed_names):
    if not path.exists():
        return {}
    preserved = {}
    for entry in path.glob("*.toml"):
        if entry.name not in managed_names:
            try:
                preserved[entry.name] = entry.read_bytes()
            except OSError as error:
                raise PolicyError("cannot preserve {}: {}".format(entry, error))
    return preserved


def atomic_write(path, contents):
    if not path.is_symlink() and path.is_file() and path.read_bytes() == contents:
        return
    with tempfile.NamedTemporaryFile("wb", dir=str(path.parent), delete=False) as handle:
        handle.write(contents)
        temporary = Path(handle.name)
    temporary.replace(path)


def digest(path):
    hasher = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            hasher.update(chunk)
    return hasher.hexdigest()


def load_manifest(path, managed_roles):
    if not path.exists():
        return {}
    value = read_json(path, "generated-role manifest")
    if set(value) != {"version", "roles"} or value["version"] != 1 or not isinstance(value["roles"], dict):
        raise PolicyError("generated-role manifest {} has an invalid schema".format(path))
    roles = {}
    for role, entry in value["roles"].items():
        expected_path = "agents/{}.toml".format(role)
        if role not in managed_roles or not isinstance(entry, dict) or set(entry) != {"path", "sha256"}:
            raise PolicyError("generated-role manifest {} has an invalid role {}".format(path, role))
        if entry["path"] != expected_path or not re_full_sha256(entry["sha256"]):
            raise PolicyError("generated-role manifest {} has invalid ownership for {}".format(path, role))
        roles[role] = dict(entry)
    return roles


def re_full_sha256(value):
    return isinstance(value, str) and len(value) == 64 and all(character in "0123456789abcdef" for character in value)


def backup_generated(path, target, backup_dir, dry_run):
    timestamp = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
    root = Path(backup_dir).expanduser().resolve() if backup_dir else target / ".model-policy-backups" / timestamp
    relative = path.relative_to(target)
    destination = root / "generated" / relative
    if dry_run:
        print("would back up modified {} -> {}".format(path, destination))
        return
    if destination.exists() or destination.is_symlink():
        raise PolicyError("backup destination already exists: {}".format(destination))
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(path), str(destination))
    print("backed up modified {} -> {}".format(path, destination))


def install(target, repo=None, dry_run=False, backup_dir=None):
    resolved, _, root = resolve_policy(repo)
    templates = source_path(root, Path("agents"))
    if not templates.is_dir():
        raise PolicyError("cannot find agent templates at {}".format(templates))
    target_path = Path(target).expanduser().resolve()
    if repo is not None and target_path != (Path(repo).expanduser().resolve() / ".codex"):
        raise PolicyError("project install target must be {}".format(Path(repo).expanduser().resolve() / ".codex"))
    agents_path = target_path / "agents"
    selected = []
    for template in sorted(templates.glob("*.toml")):
        role = template.stem
        if role in resolved:
            selected.append((template, render_template(template, resolved[role], root)))
    if not selected:
        raise PolicyError("no policy roles have TOML templates")
    managed_names = {template.name for template, _ in selected}
    managed_roles = {template.stem for template, _ in selected}
    manifest_path = target_path / MANIFEST_FILE
    previous_roles = load_manifest(manifest_path, managed_roles)
    preserved = unknown_agent_files(agents_path, managed_names) if agents_path.is_symlink() else {}
    if agents_path.is_symlink():
        backup_agents(agents_path, backup_dir, dry_run)
    elif dry_run:
        print("would create directory {}".format(agents_path))
    else:
        agents_path.mkdir(parents=True, exist_ok=True)
    for name, contents in preserved.items():
        destination = agents_path / name
        if dry_run:
            print("would preserve {}".format(destination))
        elif agents_path.is_symlink():
            raise PolicyError("agents path remains a symlink after backup: {}".format(agents_path))
        else:
            atomic_write(destination, contents)
    generated_roles = {}
    for template, rendered in selected:
        role = template.stem
        destination = agents_path / template.name
        contents = rendered.encode("utf-8")
        previous = previous_roles.get(role)
        if destination.exists() or destination.is_symlink():
            unchanged = (
                previous is not None
                and not destination.is_symlink()
                and destination.is_file()
                and digest(destination) == previous["sha256"]
            )
            if not unchanged:
                backup_generated(destination, target_path, backup_dir, dry_run)
        if dry_run:
            print("would write {}".format(destination))
        else:
            atomic_write(destination, contents)
            print("wrote {}".format(destination))
        generated_roles[role] = {"path": "agents/{}".format(template.name), "sha256": hashlib.sha256(contents).hexdigest()}
    manifest = json.dumps({"version": 1, "roles": generated_roles}, ensure_ascii=False, indent=2, sort_keys=True).encode("utf-8") + b"\n"
    if dry_run:
        print("would write {}".format(manifest_path))
    else:
        target_path.mkdir(parents=True, exist_ok=True)
        atomic_write(manifest_path, manifest)
        print("wrote {}".format(manifest_path))


def uninstall(target, dry_run=False):
    root = harness_root()
    templates = source_path(root, Path("agents"))
    default_path = source_path(root, Path("config") / POLICY_FILE)
    policy_roles = set(validate_roles(read_json(default_path, "default policy"), "default policy"))
    managed_roles = {template.stem for template in templates.glob("*.toml") if template.stem in policy_roles}
    target_path = Path(target).expanduser().resolve()
    manifest_path = target_path / MANIFEST_FILE
    roles = load_manifest(manifest_path, managed_roles)
    if not manifest_path.exists():
        print("no generated-role manifest at {}".format(manifest_path))
        return
    remaining = {}
    for role, entry in sorted(roles.items()):
        destination = target_path / entry["path"]
        if destination.is_symlink() or not destination.is_file():
            print("retained {}: missing or not a generated regular file".format(destination))
            continue
        if digest(destination) != entry["sha256"]:
            print("retained {}: hash differs from manifest".format(destination))
            remaining[role] = entry
            continue
        if dry_run:
            print("would remove {}".format(destination))
        else:
            destination.unlink()
            print("removed {}".format(destination))
    if remaining:
        contents = json.dumps({"version": 1, "roles": remaining}, ensure_ascii=False, indent=2, sort_keys=True).encode("utf-8") + b"\n"
        if dry_run:
            print("would retain manifest {} for modified roles".format(manifest_path))
        else:
            atomic_write(manifest_path, contents)
            print("retained manifest {} for modified roles".format(manifest_path))
    elif dry_run:
        print("would remove {}".format(manifest_path))
    else:
        manifest_path.unlink()
        print("removed {}".format(manifest_path))


def command_show(args):
    policy, sources, _ = policy_for(args.role, args.repo, args.model, args.effort)
    print(json.dumps({"role": args.role, "model": policy["model"], "effort": policy["effort"], "sources": sources}, ensure_ascii=False, sort_keys=True))


def command_codex(args):
    if not args.command:
        raise PolicyError("codex requires arguments after --")
    policy, _, _ = policy_for(args.role, args.repo, args.model, args.effort)
    command = ["codex", "-m", policy["model"], "-c", "model_reasoning_effort={}".format(policy["effort"])]
    command.extend(args.command)
    try:
        os.execvp(command[0], command)
    except OSError as error:
        raise PolicyError("cannot start Codex: {}".format(error))


def parser():
    result = argparse.ArgumentParser(description=__doc__)
    subcommands = result.add_subparsers(dest="action", required=True)
    def role_options(item):
        item.add_argument("role")
        item.add_argument("--repo")
        item.add_argument("--model")
        item.add_argument("--effort")
    show = subcommands.add_parser("show", help="print resolved JSON for a role")
    role_options(show)
    show.set_defaults(handler=command_show)
    install_parser = subcommands.add_parser("install", help="materialize policy-managed agents")
    install_parser.add_argument("--target", required=True)
    install_parser.add_argument("--repo")
    install_parser.add_argument("--dry-run", action="store_true")
    install_parser.add_argument("--backup-dir")
    install_parser.set_defaults(handler=lambda args: install(args.target, args.repo, args.dry_run, args.backup_dir))
    uninstall_parser = subcommands.add_parser("uninstall", help="remove unchanged policy-generated agents")
    uninstall_parser.add_argument("--target", required=True)
    uninstall_parser.add_argument("--dry-run", action="store_true")
    uninstall_parser.set_defaults(handler=lambda args: uninstall(args.target, args.dry_run))
    codex = subcommands.add_parser("codex", help="start Codex with the resolved role policy")
    role_options(codex)
    codex.set_defaults(handler=command_codex)
    return result


def main():
    command_parser = parser()
    args, remainder = command_parser.parse_known_args()
    if args.action == "codex":
        if not remainder or remainder[0] != "--":
            return fail("codex arguments must follow --")
        args.command = remainder[1:]
    elif remainder:
        command_parser.error("unrecognized arguments: {}".format(" ".join(remainder)))
    try:
        args.handler(args)
    except PolicyError as error:
        return fail(str(error))
    return 0


if __name__ == "__main__":
    sys.exit(main())
