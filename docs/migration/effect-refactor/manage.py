#!/usr/bin/env python3
"""Inspect the refactor plan. Read-only: no claims, builds, agents or state writes."""

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
DEFAULT_PLAN = Path(__file__).with_name("plan.json")
TASK_STATES = {"not_started", "in_progress", "blocked", "review", "done"}
ROLLUP_STATES = {"not_started", "in_progress", "blocked", "qualified", "retired"}
PROOF_CLASSES = {
    "planning", "portable_synthetic", "host_integration", "physical_device",
    "signed_distribution", "external_client", "deployed_operational",
}
MINIMUM_GATE_PROOFS = {
    "V01": {"portable_synthetic"}, "V02": {"portable_synthetic"},
    "V03": {"host_integration"}, "V04": {"physical_device"},
    "V05": {"host_integration"}, "V06": {"host_integration", "signed_distribution"},
    "V07": {"portable_synthetic"}, "V08": {"host_integration"},
    "V09": {"signed_distribution", "host_integration"},
    "V10": {"physical_device", "signed_distribution"},
    "V11": {"portable_synthetic", "deployed_operational"},
    "V12": {"external_client"}, "V13": {"deployed_operational"},
}


def digest(value):
    encoded = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(encoded.encode()).hexdigest()


def fingerprint(value):
    return isinstance(value, str) and re.fullmatch(r"[0-9a-f]{40}(?:\+[0-9a-f]{64})?", value) is not None


def read_receipt(path):
    if not safe_path(path) or not path.endswith(".json"):
        raise ValueError("receipt must be a repository-relative JSON file")
    value = json.loads((ROOT / path).read_text())
    if not isinstance(value, dict):
        raise ValueError("receipt must be a JSON object")
    return value


def source_review_errors(receipt):
    errors = []
    source = receipt.get("source_sha")
    patch = receipt.get("patch_digest")
    if not isinstance(source, str) or re.fullmatch(r"[0-9a-f]{40}", source) is None:
        errors.append("source_sha must be a 40-character revision")
    if patch is not None and (not isinstance(patch, str) or re.fullmatch(r"[0-9a-f]{64}", patch) is None):
        errors.append("patch_digest must be null or a 64-character SHA-256")
    review = receipt.get("review", {})
    expected = str(source) + ("+" + str(patch) if patch else "")
    if (not isinstance(review, dict) or review.get("status") != "accepted"
            or not isinstance(review.get("reviewer"), str) or not review["reviewer"].strip()
            or not fingerprint(review.get("fingerprint")) or review.get("fingerprint") != expected):
        errors.append("accepted review must name its exact source[+patch] fingerprint")
    return errors


def slug(value):
    return re.sub(r"[^\w -]", "", value.lower()).replace(" ", "-")


def reference_index(path):
    """Extract design IDs without copying their normative contents into the plan."""
    lines = path.read_text().splitlines()
    result = {}
    heading = ""
    for index, line in enumerate(lines):
        if re.match(r"^#{1,6} ", line):
            heading = slug(re.sub(r"^#+ ", "", line))
        match = re.match(r"^\| ([DCHOPLSUVMF]\d{2})(?:\s|:)", line)
        if match:
            result[match.group(1)] = {"anchor": heading, "text": line}
        match = re.match(r"^### (K\d{2}): ", line)
        if match:
            end = index + 1
            while end < len(lines) and not re.match(r"^#{1,3} ", lines[end]):
                end += 1
            result[match.group(1)] = {"anchor": heading, "text": "\n".join(lines[index:end]).rstrip()}
    return result


def safe_path(value, allow_glob=False):
    if not isinstance(value, str) or not value or "\\" in value:
        return False
    path = Path(value)
    return (not path.is_absolute() and ".." not in path.parts
            and (allow_glob or not any(char in value for char in "*?[]")))


def matches_scope(path, pattern):
    # Each * matches one path component. ** permits a declared recursive scope.
    expression = re.escape(pattern).replace(r"\*\*", ".*").replace(r"\*", "[^/]*")
    return re.fullmatch(expression, path) is not None


def overlap(left, right):
    return (left == right or left.startswith(right.rstrip("/") + "/")
            or right.startswith(left.rstrip("/") + "/"))


def keyed(items, label, errors):
    result = {}
    if not isinstance(items, list):
        errors.append(label + " must be an array")
        return result
    for item in items:
        if not isinstance(item, dict) or not isinstance(item.get("id"), str):
            errors.append(label + " contains an item without a string id")
            continue
        if item["id"] in result:
            errors.append("duplicate " + label + " id: " + item["id"])
        result[item["id"]] = item
    return result


def reference_exists(value):
    if not isinstance(value, str):
        return False
    raw, _, anchor = value.partition("#")
    if not safe_path(raw):
        return False
    path = ROOT / raw
    if not path.is_file():
        return False
    if anchor:
        headings = {slug(re.sub(r"^#+ ", "", line)) for line in path.read_text().splitlines()
                    if re.match(r"^#{1,6} ", line)}
        return anchor in headings
    return True


def receipt_errors(task):
    errors = []
    prefix = task["id"] + " receipt: "
    try:
        receipt = read_receipt(task["receipt_path"])
    except (ValueError, OSError) as error:
        return [task["id"] + " invalid receipt: " + str(error)]
    if receipt.get("task_id") != task["id"] or receipt.get("result") != "passed":
        errors.append(prefix + "must identify the task and a passed bounded result")
    if receipt.get("proof_class") != task["qualification"]["proof_class"]:
        errors.append(prefix + "proof class disagrees with task")
    errors.extend(prefix + error for error in source_review_errors(receipt))
    if receipt.get("review") != task["review"]:
        errors.append(prefix + "review differs from the coordinator's accepted review")
    if receipt.get("target") != task["target"]:
        errors.append(prefix + "target differs from the bounded task target")
    if task.get("claim") and receipt.get("review", {}).get("reviewer") == task["claim"].get("agent"):
        errors.append(prefix + "reviewer must be independent of the claimed writer")
    outcomes = receipt.get("acceptance_results", [])
    passed = {item.get("criterion") for item in outcomes
              if isinstance(item, dict) and item.get("result") == "passed" and item.get("evidence")}
    if any(criterion not in passed for criterion in task["acceptance"]):
        errors.append(prefix + "every exact acceptance item needs passed evidence")
    for field in ("inputs", "target", "checks", "limitations", "remaining_qualification", "rollback"):
        if field not in receipt:
            errors.append(prefix + "missing " + field)
    if not isinstance(receipt.get("inputs"), dict) or not receipt.get("inputs"):
        errors.append(prefix + "inputs must record the pinned inventory/digests")
    for field in ("changed_paths", "checks", "limitations", "remaining_qualification"):
        if not isinstance(receipt.get(field), list):
            errors.append(prefix + field + " must be an array")
    if not isinstance(receipt.get("rollback"), str) or not receipt.get("rollback", "").strip():
        errors.append(prefix + "concrete rollback required")
    checks = receipt.get("checks", [])
    checks = checks if isinstance(checks, list) else []
    for required in task["verification"]:
        if not any(isinstance(check, dict) and check.get("cwd") == required["cwd"]
                   and check.get("argv") == required["argv"] and check.get("result") == "passed"
                   and check.get("evidence") for check in checks):
            errors.append(prefix + "required command lacks a passed check: " + json.dumps(required["argv"]))
    if any(not isinstance(check, dict) or check.get("result") not in {"passed", "not_applicable"}
           or not check.get("evidence") or (check.get("result") == "not_applicable" and not check.get("reason"))
           for check in checks):
        errors.append(prefix + "passed receipt contains a failed, partial or unexplained check")
    executed = [check for check in checks if isinstance(check, dict) and check.get("result") == "passed"
                and safe_path(check.get("cwd")) and isinstance(check.get("argv"), list)
                and check["argv"] and all(isinstance(arg, str) for arg in check["argv"]) and check.get("evidence")]
    if len(executed) != sum(isinstance(check, dict) and check.get("result") == "passed" for check in checks):
        errors.append(prefix + "executed check needs working directory, arguments and evidence")
    observations = receipt.get("observations", [])
    if not isinstance(observations, list):
        errors.append(prefix + "observations must be an array")
        observations = []
    observed = [case for case in observations if isinstance(case, dict) and case.get("result") == "passed"
                and all(case.get(field) for field in ("case_id", "procedure", "expected", "observed", "evidence"))]
    if len(observed) != len(observations):
        errors.append(prefix + "observational proof needs passed cases with procedure, expected/observed outcome and evidence")
    if task["qualification"]["proof_class"] != "planning" and not executed and not observed:
        errors.append(prefix + "behavior proof requires executed checks or actual observational cases")
    if (task["qualification"]["proof_class"] == "planning" and not task["verification"]
            and not checks and not receipt.get("inspection_summary")):
        errors.append(prefix + "planning receipt needs inspection evidence or executed checks")
    for changed in receipt.get("changed_paths", []):
        if (not safe_path(changed) or not any(matches_scope(changed, allowed)
                                             for allowed in task["allowed_paths"])):
            errors.append(prefix + "out-of-scope changed path: " + str(changed))
    return errors


def rollup_errors(item, design, tasks):
    """Require a reviewed full-scope matrix; never infer closure from a child count."""
    prefix = item["id"] + " qualification: "
    errors = []
    matrix = item.get("qualification_matrix")
    matrix_review = item.get("matrix_review", {})
    design_digest = hashlib.sha256(design[item["id"]]["text"].encode()).hexdigest()
    if not isinstance(matrix, list) or not matrix:
        return [prefix + "closed rollup needs a complete explicit qualification matrix"]
    matrix_digest = digest(matrix)
    if (matrix_review.get("status") != "accepted" or not matrix_review.get("reviewer")
            or matrix_review.get("fingerprint") != matrix_digest
            or matrix_review.get("design_digest") != design_digest
            or matrix_review.get("scope_complete") is not True):
        errors.append(prefix + "full design scope/matrix needs current independent review")
    rows = {}
    for row in matrix:
        if (not isinstance(row, dict) or not isinstance(row.get("case_id"), str)
                or not row.get("requirement") or not isinstance(row.get("target"), dict)
                or not row["target"] or row.get("proof_class") not in PROOF_CLASSES
                or not row.get("required_tasks")):
            errors.append(prefix + "incomplete matrix row")
            continue
        if row["case_id"] in rows:
            errors.append(prefix + "duplicate matrix case " + row["case_id"])
        rows[row["case_id"]] = row
        if any(tasks.get(key, {}).get("status") != "done" for key in row["required_tasks"]):
            errors.append(prefix + "matrix row requires accepted completed tasks: " + row["case_id"])
    classes = {row.get("proof_class") for row in rows.values()}
    if not MINIMUM_GATE_PROOFS.get(item["id"], set()) <= classes:
        errors.append(prefix + "matrix omits required gate proof classes")
    covered = set()
    qualified_revisions = set()
    for path in item.get("qualification_receipts", []):
        try:
            receipt = read_receipt(path)
        except (ValueError, OSError) as error:
            errors.append(prefix + str(error))
            continue
        errors.extend(prefix + error for error in source_review_errors(receipt))
        qualified_revisions.add(receipt.get("source_sha"))
        if (receipt.get("rollup_id") != item["id"] or receipt.get("result") != "passed"
                or receipt.get("matrix_digest") != matrix_digest
                or receipt.get("design_digest") != design_digest or receipt.get("patch_digest")):
            errors.append(prefix + "receipt must qualify this exact design/matrix at committed source")
        for case in receipt.get("cases", []):
            row = rows.get(case.get("case_id")) if isinstance(case, dict) else None
            if not row or case.get("result") != "passed" or not case.get("proof_receipts"):
                errors.append(prefix + "invalid or unproved matrix case")
                continue
            for proof_path in case["proof_receipts"]:
                try:
                    proof = read_receipt(proof_path)
                except (ValueError, OSError) as error:
                    errors.append(prefix + str(error))
                    continue
                task = tasks.get(proof.get("task_id"), {})
                if (proof.get("result") != "passed" or task.get("status") != "done"
                        or proof.get("task_id") not in row["required_tasks"]
                        or proof_path not in task.get("qualification", {}).get("receipts", [])
                        or proof.get("source_sha") != receipt.get("source_sha") or proof.get("patch_digest")
                        or proof.get("proof_class") != row["proof_class"] or proof.get("target") != row["target"]):
                    errors.append(prefix + "case proof differs from current accepted source/target/class")
                else:
                    errors.extend(receipt_errors(dict(task, receipt_path=proof_path)))
                    covered.add(case["case_id"])
    if set(rows) != covered:
        errors.append(prefix + "every matrix case needs current passed proof")
    if len(qualified_revisions) != 1:
        errors.append(prefix + "all matrix cases must qualify one integrated source revision")
    return errors


def validate(plan):
    errors = []
    if plan.get("schema_version") != 1:
        errors.append("unsupported schema_version")
    for key in ("entrypoint", "design_reference"):
        if not reference_exists(plan.get(key)):
            errors.append("invalid " + key)
    if errors:
        return errors
    design = reference_index(ROOT / plan["design_reference"])
    families = keyed(plan.get("families"), "family", errors)
    tasks = keyed(plan.get("tasks"), "task", errors)
    choices = keyed(plan.get("decisions"), "choice", errors)
    expected_families = {key for key in design if key[0] in "CKOUPLSH"}
    if set(families) != expected_families:
        errors.append("family coverage mismatch: " + str(sorted(set(families) ^ expected_families)))
    for group, prefix in (("decision_constraints", "D"), ("risk_obligations", "F"),
                          ("validation_gates", "V"), ("phases", "M")):
        records = keyed(plan.get(group), group, errors)
        expected = {key for key in design if key.startswith(prefix)}
        if set(records) != expected:
            errors.append(group + " coverage mismatch")
        for key, item in records.items():
            if key in design and item.get("reference") != plan["design_reference"] + "#" + design[key]["anchor"]:
                errors.append("stale design pointer: " + key)
            if not reference_exists(item.get("reference")):
                errors.append("invalid reference: " + key)
            if "status" in item and item["status"] not in ROLLUP_STATES:
                errors.append("invalid rollup state: " + key)
            if item.get("status") in {"qualified", "retired"} and not item.get("qualification_receipts"):
                errors.append("closed rollup without evidence: " + key)
    for key, family in families.items():
        if key in design and family.get("reference") != plan["design_reference"] + "#" + design[key]["anchor"]:
            errors.append("stale family pointer: " + key)
        if family.get("status") not in ROLLUP_STATES or family.get("expansion") not in {"needs_decomposition", "expanded"}:
            errors.append("invalid family state: " + key)
        if not family.get("remaining_scope") and family.get("status") not in {"qualified", "retired"}:
            errors.append("open family without remaining scope: " + key)
        if family.get("status") in {"qualified", "retired"}:
            if (family.get("expansion") != "expanded" or family.get("review_status") != "accepted"
                    or family.get("remaining_scope") or not family.get("qualification_receipts")):
                errors.append("family closed without expanded/reviewed evidence: " + key)
    for key, choice in choices.items():
        if choice.get("status") not in {"open", "accepted", "deferred"}:
            errors.append("invalid choice state: " + key)
        if any(item not in families for item in choice.get("affected_families", [])):
            errors.append("unknown choice family: " + key)
        if choice.get("resolver_task") and choice["resolver_task"] not in tasks:
            errors.append("unknown resolver task: " + key)
        if choice.get("status") == "accepted":
            if (not choice.get("resolution") or not choice.get("evidence")
                    or not reference_exists(choice.get("record_path"))):
                errors.append("accepted choice without resolution/evidence/record: " + key)
    phases = {item["id"] for item in plan["phases"]}
    for key, task in tasks.items():
        needed = {"title", "stream", "phase", "kind", "outcome", "prerequisites", "required_decisions",
                  "coverage", "risk_ids", "read_required", "allowed_paths", "shared_resources", "acceptance",
                  "verification", "fixture_inputs", "consumers", "target", "rollback", "deletion_gate",
                  "receipt_path", "reviewer_role", "priority", "status", "claim", "blocker", "review", "qualification"}
        missing = needed - task.keys()
        if missing:
            errors.append(key + " missing fields: " + ", ".join(sorted(missing)))
            continue
        if task["status"] not in TASK_STATES or task["phase"] not in phases:
            errors.append("invalid task/phase state: " + key)
        if not task["outcome"] or not task["allowed_paths"] or not task["acceptance"] or not task["coverage"]:
            errors.append("incomplete bounded card: " + key)
        if any(item not in tasks for item in task["prerequisites"]):
            errors.append("unknown prerequisite: " + key)
        if any(item not in choices for item in task["required_decisions"]):
            errors.append("unknown required choice: " + key)
        if any(item not in families for item in task["coverage"]):
            errors.append("unknown coverage family: " + key)
        if any(item not in design or not item.startswith("F") for item in task["risk_ids"]):
            errors.append("unknown risk: " + key)
        if any(not reference_exists(item) for item in task["read_required"]):
            errors.append("missing required read: " + key)
        if any(not safe_path(item, allow_glob=True) for item in task["allowed_paths"]):
            errors.append("unsafe allowed path: " + key)
        if (not safe_path(task["receipt_path"]) or task["receipt_path"] not in task["allowed_paths"]):
            errors.append("receipt outside claimable scope: " + key)
        for command in task["verification"]:
            if (command.get("availability") not in {"existing", "created_by_this_task", "created_by_prerequisite"}
                    or not safe_path(command.get("cwd")) or not command.get("argv")
                    or not all(isinstance(arg, str) for arg in command["argv"])):
                errors.append("invalid verification command: " + key)
            if command.get("availability") == "created_by_prerequisite" and command.get("introduced_by") not in tasks:
                errors.append("unknown command introducer: " + key)
        proof = task["qualification"]
        if proof.get("proof_class") not in PROOF_CLASSES or proof.get("status") not in {"pending", "passed", "failed", "stale", "not_applicable"}:
            errors.append("invalid proof state: " + key)
        review = task["review"]
        if review.get("status") not in {"pending", "changes_requested", "accepted"}:
            errors.append("invalid review state: " + key)
        if proof.get("status") == "passed" and (not proof.get("receipts")
                or any(not reference_exists(path) for path in proof["receipts"])):
            errors.append("passed proof without referenced evidence: " + key)
        if proof.get("status") == "passed":
            if task["status"] not in {"review", "done"}:
                errors.append("passed proof before review/completion state: " + key)
            for path in proof.get("receipts", []):
                errors.extend(receipt_errors(dict(task, receipt_path=path)))
        if task["status"] == "blocked" and not task["blocker"]:
            errors.append("blocked task without unblock condition: " + key)
        if task["status"] == "done":
            if (review.get("status") != "accepted" or not review.get("reviewer")
                    or not review.get("fingerprint") or proof.get("status") != "passed"
                    or task["receipt_path"] not in proof.get("receipts", [])):
                errors.append("task done without accepted review/passed bounded proof: " + key)
            if proof.get("status") != "passed":
                errors.extend(receipt_errors(task))
        if task["status"] in {"in_progress", "review", "done"}:
            if any(tasks.get(dep, {}).get("status") != "done" for dep in task["prerequisites"]):
                errors.append("active/done task before accepted dependencies: " + key)
            if any(choices.get(dep, {}).get("status") != "accepted" for dep in task["required_decisions"]):
                errors.append("active/done task before accepted choice: " + key)
        claim = task["claim"]
        if task["status"] in {"in_progress", "review"} and not claim:
            errors.append("active task without claim: " + key)
        if claim:
            if (not all(isinstance(claim.get(field), str) and claim[field].strip()
                        for field in ("agent", "base_revision", "worktree"))
                    or not isinstance(claim.get("write_paths"), list) or not claim.get("write_paths")):
                errors.append("incomplete claim: " + key)
            if not re.fullmatch(r"[0-9a-f]{40}", str(claim.get("base_revision", ""))):
                errors.append("claim needs pinned 40-character base revision: " + key)
            for path in claim.get("write_paths", []):
                if not safe_path(path) or not any(matches_scope(path, item) for item in task["allowed_paths"]):
                    errors.append("claimed path outside allowed scope: " + key + " " + str(path))
            if any(item not in task["shared_resources"] for item in claim.get("reserved_resources", [])):
                errors.append("claimed undeclared resource: " + key)
            if not set(task["shared_resources"]) <= set(claim.get("reserved_resources", [])):
                errors.append("claim must reserve every declared shared resource: " + key)
    visiting, visited = set(), set()

    def visit(key):
        if key in visiting:
            errors.append("dependency cycle at " + key)
            return
        if key in visited or key not in tasks:
            return
        visiting.add(key)
        for dependency in tasks[key].get("prerequisites", []):
            visit(dependency)
        visiting.remove(key)
        visited.add(key)

    for key in tasks:
        visit(key)

    def ancestors(key, seen=None):
        seen = set() if seen is None else seen
        for dependency in tasks.get(key, {}).get("prerequisites", []):
            if dependency not in seen:
                seen.add(dependency)
                ancestors(dependency, seen)
        return seen

    for key, task in tasks.items():
        for command in task.get("verification", []):
            if (command.get("availability") == "created_by_prerequisite"
                    and command.get("introduced_by") not in ancestors(key)):
                errors.append("command introducer is not a task prerequisite: " + key)
    active = [item for item in tasks.values() if item.get("status") in {"in_progress", "review"} and item.get("claim")]
    if len(active) > plan["dispatch_policy"]["max_parallel_writers"]:
        errors.append("configured concurrent-writer limit exceeded")
    for index, left in enumerate(active):
        for right in active[index + 1:]:
            a, b = left["claim"], right["claim"]
            # Reserve resources across worktrees too: separate checkouts do not prevent integration conflicts.
            if set(a.get("reserved_resources", [])) & set(b.get("reserved_resources", [])):
                errors.append("shared resource conflict: " + left["id"] + " / " + right["id"])
            if any(overlap(x, y) for x in a.get("write_paths", []) for y in b.get("write_paths", [])):
                errors.append("write claim conflict: " + left["id"] + " / " + right["id"])
    for field in ("families", "phases", "validation_gates"):
        for item in plan[field]:
            for path in item.get("qualification_receipts", []):
                if not reference_exists(path):
                    errors.append("missing rollup evidence: " + item["id"] + " " + str(path))
            if item.get("status") in {"qualified", "retired"} and item["id"] in design:
                errors.extend(rollup_errors(item, design, tasks))
    return errors


def blockers(task, tasks, choices):
    result = ["task " + key for key in task["prerequisites"] if tasks[key]["status"] != "done"]
    result += ["choice " + key for key in task["required_decisions"] if choices[key]["status"] != "accepted"]
    if task.get("blocker"):
        result.append("recorded blocker: " + str(task["blocker"]))
    return result


def show_brief(task, plan, tasks, choices):
    print("# " + task["id"] + ": " + task["title"])
    print("\nOutcome: " + task["outcome"])
    print("State: " + task["status"] + "; phase: " + task["phase"] + "; proof: " + task["qualification"]["proof_class"])
    pending = blockers(task, tasks, choices)
    print("Readiness: " + ("blocked by " + ", ".join(pending) if pending else "dependency-ready; coordinator must claim and pin inputs"))
    print("\nPreferred profile: " + plan["agent_profile"]["model"] + " / " + plan["agent_profile"]["reasoning_effort"])
    for label, values in (("Read first", [plan["entrypoint"]] + task["read_required"]),
                          ("Design IDs (manage.py reference ID)", task["coverage"] + task["risk_ids"]),
                          ("Allowed writes", task["allowed_paths"]), ("Reserve shared resources", task["shared_resources"]),
                          ("Acceptance", task["acceptance"])):
        print("\n" + label + ":")
        for value in values:
            print("- " + value)
    print("\nVerification:")
    if not task["verification"]:
        print("- Planning/source review: record actual inspection commands and evidence; product tests are not implied.")
    for command in task["verification"]:
        print("- cwd=" + command["cwd"] + " argv=" + json.dumps(command["argv"]) + " availability=" + command["availability"]
              + (" introduced_by=" + command["introduced_by"] if command.get("introduced_by") else ""))
    for label, key in (("Fixtures", "fixture_inputs"), ("Consumers", "consumers"), ("Rollback", "rollback"),
                       ("Deletion gate", "deletion_gate"), ("Receipt", "receipt_path"), ("Reviewer", "reviewer_role")):
        value = task[key]
        rendered = value if isinstance(value, str) else json.dumps(value, ensure_ascii=False)
        print("\n" + label + ": " + rendered)
    print("\nUse docs/migration/effect-refactor/templates.md for dispatch/review/receipt. Parent scope remains open.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan", type=Path, default=DEFAULT_PLAN)
    sub = parser.add_subparsers(dest="action", required=True)
    sub.add_parser("check")
    ready = sub.add_parser("ready")
    ready.add_argument("--limit", type=int, default=10)
    brief = sub.add_parser("brief")
    brief.add_argument("id")
    reference = sub.add_parser("reference")
    reference.add_argument("id")
    catalog = sub.add_parser("catalog")
    catalog.add_argument("--stream")
    phase = sub.add_parser("phase")
    phase.add_argument("id")
    matrix = sub.add_parser("matrix")
    matrix.add_argument("id")
    args = parser.parse_args()
    try:
        plan = json.loads(args.plan.read_text())
        errors = validate(plan)
    except (OSError, ValueError, KeyError, TypeError, AttributeError) as error:
        print("Invalid plan: " + str(error), file=sys.stderr)
        return 1
    if errors:
        print("Plan validation failed:\n- " + "\n- ".join(errors), file=sys.stderr)
        return 1
    tasks = {item["id"]: item for item in plan["tasks"]}
    choices = {item["id"]: item for item in plan["decisions"]}
    if args.action == "check":
        print("PASS: %d atomic tasks, %d families, %d choices; graph, pointers, state/evidence and claims valid." %
              (len(tasks), len(plan["families"]), len(choices)))
        print("Structural validation only; no implementation or release qualification asserted.")
    elif args.action == "ready":
        if args.limit < 1:
            parser.error("--limit must be positive")
        available = sorted((item for item in tasks.values() if item["status"] == "not_started"
                            and not blockers(item, tasks, choices)), key=lambda item: (item["priority"], item["id"]))
        for item in available[:args.limit]:
            print(item["id"] + " [" + item["kind"] + ", " + item["stream"] + "]: " + item["title"])
        print("%d dependency-ready; coordinator must assign claims, inputs and environment." % len(available))
    elif args.action == "brief":
        if args.id not in tasks:
            parser.error("unknown task " + args.id)
        show_brief(tasks[args.id], plan, tasks, choices)
    elif args.action == "reference":
        records = reference_index(ROOT / plan["design_reference"])
        if args.id not in records:
            parser.error("unknown design ID " + args.id)
        print("Source: " + plan["design_reference"] + "#" + records[args.id]["anchor"] + "\n")
        print(records[args.id]["text"])
    elif args.action == "catalog":
        families = [item for item in plan["families"] if not args.stream or item["stream"] == args.stream]
        if args.stream and not families:
            parser.error("unknown stream " + args.stream)
        for item in families:
            children = [task["id"] for task in tasks.values() if item["id"] in task["coverage"]]
            print(item["id"] + " [" + item["stream"] + "; " + item["status"] + "; " + item["expansion"] + "] " + item["label"])
            print("  Current children: " + (", ".join(children) or "none; decompose before dispatch"))
            print("  Remaining: " + item["remaining_scope"])
    elif args.action == "phase":
        records = {item["id"]: item for item in plan["phases"]}
        if args.id not in records:
            parser.error("unknown phase " + args.id)
        print(args.id + " [" + records[args.id]["status"] + "] " + records[args.id]["reference"])
        for task in tasks.values():
            if task["phase"] == args.id:
                print("- " + task["id"] + " [" + task["status"] + "] " + task["title"])
        print("Phase closure requires the complete design matrix; task completion alone does not close it.")
    elif args.action == "matrix":
        records = {item["id"]: item for field in ("families", "phases", "validation_gates") for item in plan[field]}
        if args.id not in records:
            parser.error("unknown rollup " + args.id)
        item = records[args.id]
        design = reference_index(ROOT / plan["design_reference"])
        print("Design digest: " + hashlib.sha256(design[args.id]["text"].encode()).hexdigest())
        print("Matrix digest: " + digest(item.get("qualification_matrix", [])))
        print(json.dumps(item.get("qualification_matrix", []), indent=2, ensure_ascii=False))
        print("Matrix review: " + json.dumps(item.get("matrix_review", {})))
        print("Digests identify inputs; empty or incomplete matrices do not qualify a rollup.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
