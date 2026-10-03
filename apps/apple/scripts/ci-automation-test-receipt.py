#!/usr/bin/env python3
"""Hosted-only bounded named-test evidence; does not select or rerun tests."""
import argparse
import json
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("tree")
parser.add_argument("output")
parser.add_argument("--head", required=True)
parser.add_argument("--platform", required=True)
args = parser.parse_args()
data = json.loads(Path(args.tree).read_text())
records = []


def visit(value, in_suite=False):
    if isinstance(value, dict):
        name = str(value.get("name", ""))
        identifier = str(value.get("nodeIdentifier", value.get("testIdentifier", "")))
        owned = in_suite or "AppleContextAutomationTests" in name or "AppleContextAutomationTests" in identifier
        if owned and value.get("nodeType") == "Test Case":
            records.append({"name": name, "identifier": identifier, "result": value.get("result", "Unknown")})
        for child in value.values():
            if isinstance(child, (dict, list)):
                visit(child, owned)
    elif isinstance(value, list):
        for child in value:
            visit(child, in_suite)


visit(data)
output = Path(args.output)
output.parent.mkdir(parents=True, exist_ok=True)
lines = [f"head: {args.head}", f"platform: {args.platform}", "source: xcresulttool get test-results tests (executed full suite)", f"named cases: {len(records)}"]
lines.extend(json.dumps(record, sort_keys=True) for record in records)
output.write_text("\n".join(lines) + "\n")
print(output.read_text(), end="")
if not records:
    raise SystemExit("No named automation test execution in native result; not a passing receipt")
