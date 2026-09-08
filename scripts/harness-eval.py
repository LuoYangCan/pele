#!/usr/bin/env python3
"""Replay isolated, read-only Codex model-routing fixtures."""

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent
FIXTURE_ROOT = ROOT / "evals" / "model-routing"
POLICY = ROOT / "scripts" / "model-policy.py"
OUTPUT_SCHEMA = FIXTURE_ROOT / "response.schema.json"
TIMEOUT_SECONDS = 180


def load_case(path):
    with path.open(encoding="utf-8") as handle:
        value = json.load(handle)
    required = {"id", "role", "prompt", "answers", "expected"}
    if not isinstance(value, dict) or set(value) - (required | {"files"}) or not required <= set(value):
        raise ValueError("{} has an invalid fixture schema".format(path))
    expected = value["expected"]
    if not isinstance(expected, dict) or set(expected) != {"answer", "evidence_contains"}:
        raise ValueError("{} expected must contain answer and evidence_contains".format(path))
    if not isinstance(expected["answer"], str) or not isinstance(expected["evidence_contains"], list):
        raise ValueError("{} expected values are invalid".format(path))
    if "files" in value and not isinstance(value["files"], dict):
        raise ValueError("{} files must be an object".format(path))
    return value


def cases(names):
    available = {path.stem: path for path in sorted(FIXTURE_ROOT.glob("*.json")) if path.name != OUTPUT_SCHEMA.name}
    selected = names or list(available)
    missing = [name for name in selected if name not in available]
    if missing:
        raise ValueError("unknown fixture(s): {}".format(", ".join(missing)))
    return [load_case(available[name]) for name in selected]


def policy_options(model, effort):
    options = []
    if model is not None:
        options.extend(["--model", model])
    if effort is not None:
        options.extend(["--effort", effort])
    return options


def command_for(case, repo, message_path, model, effort):
    return [
        sys.executable, str(POLICY), "codex", case["role"], "--repo", str(repo),
        *policy_options(model, effort), "--", "-a", "never", "exec",
        "--ignore-user-config", "--ignore-rules", "--ephemeral",
        "-c", "features.hooks=false", "-c", "project_doc_max_bytes=0", "-c", "agents.enabled=false",
        "--sandbox", "read-only", "--skip-git-repo-check", "--output-schema", str(OUTPUT_SCHEMA),
        "--output-last-message", str(message_path), "--json", "Case ID: " + case["id"] + ". Read only fixture.txt. Do not change state or use network. " + case["prompt"] + " Return JSON with this exact case_id, one answer chosen from " + json.dumps(case["answers"]) + ", and nonempty evidence explaining the decision.",
    ]


def usage_from(events):
    usage = None
    for line in events.splitlines():
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(event, dict) and event.get("usage") is not None:
            usage = event["usage"]
    return usage


def resolved_policy(case, repo, model, effort):
    completed = subprocess.run(
        [sys.executable, str(POLICY), "show", case["role"], "--repo", str(repo), *policy_options(model, effort)],
        text=True,
        capture_output=True,
        env=os.environ.copy(),
    )
    if completed.returncode != 0:
        return None, completed.stderr.strip(), completed.returncode
    try:
        return json.loads(completed.stdout), "", 0
    except json.JSONDecodeError:
        return None, "policy show did not return JSON", 1


def validate_response(response, case):
    if not isinstance(response, dict) or set(response) != {"case_id", "answer", "evidence"}:
        return False, "last message does not match the response object shape"
    if response["case_id"] != case["id"]:
        return False, "case_id does not match fixture"
    if response["answer"] != case["expected"]["answer"]:
        return False, "answer is incorrect"
    if not isinstance(response["evidence"], str) or not response["evidence"].strip() or not all(item in response["evidence"] for item in case["expected"]["evidence_contains"]):
        return False, "evidence does not support the answer"
    return True, None


def run_case(case, model, effort):
    with tempfile.TemporaryDirectory(prefix="model-routing-") as temporary:
        temporary_path = Path(temporary).resolve()
        repo = temporary_path / "repo"
        fixture_home = temporary_path / "home"
        message_path = temporary_path / "last-message.json"
        repo.mkdir()
        fixture_home.mkdir()
        for relative, contents in case.get("files", {}).items():
            destination = (repo / relative).resolve()
            if repo not in destination.parents:
                raise ValueError("fixture path escapes temporary repo: " + relative)
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_text(contents, encoding="utf-8")
        environment = os.environ.copy()
        environment["HOME"] = str(fixture_home)
        environment["CODEX_HOME"] = os.environ.get("CODEX_HOME", str(Path.home() / ".codex"))
        environment["LANG"] = "C.UTF-8"
        subprocess.run(["git", "init", "--quiet", "--template=", str(repo)], check=True, stdout=subprocess.DEVNULL, env=environment)
        policy, policy_error, policy_exit_code = resolved_policy(case, repo, model, effort)
        if policy is None:
            return {"id": case["id"], "role": case["role"], "model": None, "effort": None, "duration_seconds": 0, "exit_code": policy_exit_code, "correct": False, "usage": None, "response": None, "error": policy_error}
        started = time.monotonic()
        try:
            completed = subprocess.run(command_for(case, repo, message_path, model, effort), cwd=str(repo), text=True, capture_output=True, env=environment, timeout=TIMEOUT_SECONDS)
            exit_code = completed.returncode
            events = completed.stdout
            error = completed.stderr.strip() or None
        except subprocess.TimeoutExpired as error:
            exit_code = 124
            events = error.stdout or ""
            error = "timed out after {} seconds".format(TIMEOUT_SECONDS)
        response = None
        valid = False
        validation_error = error
        if exit_code == 0:
            try:
                response = json.loads(message_path.read_text(encoding="utf-8"))
                valid, validation_error = validate_response(response, case)
            except (OSError, json.JSONDecodeError) as error:
                validation_error = "cannot read valid last-message JSON: {}".format(error)
        return {
            "id": case["id"], "role": case["role"], "model": policy["model"], "effort": policy["effort"],
            "duration_seconds": round(time.monotonic() - started, 3), "exit_code": exit_code,
            "correct": exit_code == 0 and valid, "usage": usage_from(events), "response": response,
            "error": validation_error,
        }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true", help="run Codex instead of listing commands")
    parser.add_argument("--case", action="append", dest="cases")
    parser.add_argument("--model")
    parser.add_argument("--effort")
    args = parser.parse_args()
    try:
        selected = cases(args.cases)
        with OUTPUT_SCHEMA.open(encoding="utf-8") as handle:
            json.load(handle)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print("harness-eval: {}".format(error), file=sys.stderr)
        return 2
    if not args.run:
        placeholder = Path("<last-message.json>")
        print(json.dumps([{"id": case["id"], "role": case["role"], "command": command_for(case, Path("<temporary-repo>"), placeholder, args.model, args.effort)} for case in selected], ensure_ascii=False, indent=2))
        return 0
    results = []
    for case in selected:
        result = run_case(case, args.model, args.effort)
        results.append(result)
        print("{}: correct={} duration={}s".format(result["id"], result["correct"], result["duration_seconds"]), file=sys.stderr, flush=True)
    print(json.dumps({
        "results": results,
        "correct_rate": sum(result["correct"] for result in results) / len(results),
    }, ensure_ascii=False, indent=2))
    return 0 if all(result["correct"] for result in results) else 1


if __name__ == "__main__":
    sys.exit(main())
