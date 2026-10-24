#!/usr/bin/env python3
"""Bind every parallel native archive to the exact CI source and toolchain."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

TARGETS = ("aarch64-apple-ios", "aarch64-apple-ios-sim", "x86_64-apple-ios",
           "aarch64-apple-darwin", "x86_64-apple-darwin")
REPO = Path(__file__).resolve().parents[3]


def digest() -> str:
    return subprocess.run([str(REPO / "packages/healthmd-core-rust/scripts/apple-source-digest.sh")],
                          check=True, capture_output=True, text=True).stdout.strip()


def qualify(path: Path) -> str:
    if path.is_symlink() or not path.is_file():
        raise ValueError("Expected a nonempty regular static archive")
    raw = path.read_bytes()
    if len(raw) <= 8 or not raw.startswith(b"!<arch>\n"):
        raise ValueError("Expected a nonempty regular static archive")
    return hashlib.sha256(raw).hexdigest()


def verify(root: Path, source_sha: str, source_digest: str, toolchain: str) -> None:
    expected = {t + suffix for t in TARGETS for suffix in (".a", ".json")}
    if {p.name for p in root.iterdir()} != expected:
        raise ValueError("All five native slices and receipts are required exactly once")
    for target in TARGETS:
        path = root / (target + ".json")
        if path.is_symlink(): raise ValueError("Unexpected receipt symlink")
        receipt = json.loads(path.read_text())
        if receipt != {"target": target, "source_sha": source_sha, "source_digest": source_digest,
                       "toolchain": toolchain, "archive_sha256": qualify(root / (target + ".a"))}:
            raise ValueError("Native slice source, toolchain, target or bytes mismatch")


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("mode", choices=("receipt", "verify"))
    p.add_argument("--slices", type=Path, required=True)
    p.add_argument("--source-sha", required=True)
    p.add_argument("--toolchain", required=True)
    p.add_argument("--target", choices=TARGETS)
    a = p.parse_args()
    if not re.fullmatch(r"[0-9a-f]{40}", a.source_sha) or not re.fullmatch(r"[0-9a-f]{64}", a.toolchain):
        p.error("Exact source SHA and Xcode toolchain fingerprint required")
    source_digest = digest()
    if a.mode == "receipt":
        if a.target is None: p.error("--target required for receipt")
        value = {"target": a.target, "source_sha": a.source_sha, "source_digest": source_digest,
                 "toolchain": a.toolchain, "archive_sha256": qualify(a.slices / (a.target + ".a"))}
        (a.slices / (a.target + ".json")).write_text(json.dumps(value, indent=2) + "\n")
    else:
        verify(a.slices, a.source_sha, source_digest, a.toolchain)
        print("Verified all five source-bound Apple native slices")


if __name__ == "__main__": main()
