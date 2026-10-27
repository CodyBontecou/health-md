#!/usr/bin/env python3
"""Require every selected native smoke case to execute and pass exactly once."""

import argparse
import json
from pathlib import Path
import subprocess


def verify(document, expected):
    if not expected or len(expected) != len(set(expected)):
        raise ValueError("Expected test identities must be nonempty and unique")
    found = []

    def walk(nodes):
        for node in nodes:
            if node.get("nodeType") == "Test Case":
                found.append((node.get("nodeIdentifier", "").removesuffix("()"), node.get("result")))
            walk(node.get("children", []))

    walk(document.get("testNodes", []))
    if sorted(identity for identity, _ in found) != sorted(expected):
        raise ValueError(f"Native test inventory mismatch: expected {expected!r}; found {[identity for identity, _ in found]!r}")
    failed = [identity for identity, result in found if result != "Passed"]
    if failed:
        raise ValueError(f"Native tests failed, skipped or lacked a passing verdict: {failed!r}")
    return len(found)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bundle", type=Path)
    parser.add_argument("expected", nargs="+")
    args = parser.parse_args()
    document = json.loads(subprocess.check_output(
        ["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", str(args.bundle)],
        text=True, timeout=15,
    ))
    count = verify(document, args.expected)
    print(f"Verified {count} native smoke tests executed and passed exactly once")


if __name__ == "__main__":
    main()
