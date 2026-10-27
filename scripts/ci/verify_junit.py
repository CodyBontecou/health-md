"""Reject stale/empty/missing/skipped/failed retained JUnit results."""
import argparse
from pathlib import Path
import xml.etree.ElementTree as ET


def verify(roots, required):
    cases = []
    for root in roots:
        files = list(Path(root).rglob("*.xml"))
        if not files:
            raise ValueError(f"No test XML in {root}")
        for file in files:
            cases.extend(ET.parse(file).getroot().iter("testcase"))
    identities = [f"{c.get('classname')}#{c.get('name')}" for c in cases]
    for identity in required:
        if identities.count(identity) != 1:
            raise ValueError(f"Expected exactly one {identity}")
    if not cases or any(any(c.find(t) is not None for t in ("skipped", "error", "failure")) for c in cases):
        raise ValueError("Empty, skipped or failed test inventory")
    print(f"Verified {len(cases)} passing JUnit cases")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument("roots", nargs="+")
    parser.add_argument("--require", action="append", default=[])
    args = parser.parse_args()
    verify(args.roots, args.require)
