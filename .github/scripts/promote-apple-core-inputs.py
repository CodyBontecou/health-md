#!/usr/bin/env python3
"""Promote a complete compiled-input download without importing old receipts."""
import argparse
from pathlib import Path
import shutil


def promote(staging, destination, outcome):
    try:
        if outcome == "failure":
            return False
        if outcome != "success":
            raise ValueError("unexpected download outcome")
        expected = {"HealthmdCore.xcframework", ".healthmd-core-source.sha256"}
        if {path.name for path in staging.iterdir()} != expected:
            raise ValueError("compiled-input artifact has unexpected or missing members")
        framework = staging / "HealthmdCore.xcframework"
        digest = staging / ".healthmd-core-source.sha256"
        if framework.is_symlink() or not framework.is_dir() or digest.is_symlink() or not digest.is_file():
            raise ValueError("compiled-input artifact has invalid roots")
        destination.mkdir(parents=True, exist_ok=True)
        # Never overwrite a current SDK receipt or merge an incomplete framework.
        shutil.copytree(framework, destination / framework.name, symlinks=True)
        shutil.copy2(digest, destination / digest.name)
        return True
    finally:
        if staging.exists():
            shutil.rmtree(staging)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("staging", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument("outcome", choices=("success", "failure"))
    args = parser.parse_args()
    ready = promote(args.staging, args.destination, args.outcome)
    print("Compiled-input download staged for fresh validation." if ready else
          "Compiled-input download unavailable; retaining cold preparation.")


if __name__ == "__main__":
    main()
