#!/usr/bin/env python3
"""Verify embedded CLI/MCP helpers can load from their app's own frameworks."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess


def validate(app):
    environment = {key: value for key, value in os.environ.items() if not key.startswith("DYLD_")}
    environment["HEALTHMD_MCP_BASE_URL"] = "http://127.0.0.1:1"
    # Diagnostic only: never override library resolution for this qualification.
    environment["DYLD_PRINT_LIBRARIES"] = "1"
    for name in ("healthmd", "healthmd-mcp"):
        helper = app / "Contents" / "Helpers" / name
        commands = subprocess.check_output(["otool", "-l", str(helper)], text=True)
        paths = re.findall(r"cmd LC_RPATH\s+cmdsize \d+\s+path (.*?) \(offset", commands)
        if "@loader_path/../Frameworks" not in paths:
            raise ValueError(f"{name}: missing app-relative framework search path")
        if any(Path(path).is_absolute() and Path(path).name == "PackageFrameworks" for path in paths):
            raise ValueError(f"{name}: embedded helper retains a build-only framework search path")
        required = set()
        libraries = subprocess.check_output(["otool", "-L", str(helper)], text=True)
        for line in libraries.splitlines()[1:]:
            dependency = line.strip().split(" (", 1)[0]
            if dependency.startswith("@rpath/"):
                relative = dependency.removeprefix("@rpath/")
                required.add((app / "Contents" / "Frameworks" / relative).resolve())
                if not (app / "Contents" / "Frameworks" / relative).is_file():
                    raise ValueError(f"{name}: framework absent from bundle: {relative}")
        if name == "healthmd":
            result = subprocess.run([str(helper), "--help"], env=environment, capture_output=True, text=True, timeout=15, check=True)
            if "usage: healthmd" not in result.stdout:
                raise ValueError("CLI did not render its help")
        else:
            request = {"jsonrpc": "2.0", "id": "packaging-smoke", "method": "initialize", "params": {"protocolVersion": "2025-11-25"}}
            result = subprocess.run([str(helper)], input=json.dumps(request) + "\n", env=environment, capture_output=True, text=True, timeout=15, check=True)
            replies = [json.loads(line) for line in result.stdout.splitlines() if line.strip()]
            if len(replies) != 1 or replies[0].get("id") != "packaging-smoke" or replies[0].get("result", {}).get("protocolVersion") != "2025-11-25":
                raise ValueError("MCP helper did not complete its local initialize handshake")
        loaded = {Path(path).resolve() for path in re.findall(r"^dyld\[\d+\]: (?:<[^>]+> )?(/.+)$", result.stderr, re.MULTILINE)}
        if not required.issubset(loaded):
            raise ValueError(f"{name}: dependencies outside app or absent from loader trace: {sorted(str(path) for path in required - loaded)}; loaded package frameworks: {sorted(str(path) for path in loaded if '_PackageProduct.framework' in str(path))}")
        frameworks = (app / "Contents" / "Frameworks").resolve()
        for path in loaded:
            if "_PackageProduct.framework" in str(path) and not path.is_relative_to(frameworks):
                raise ValueError(f"{name}: loaded a build-directory package framework: {path}")
        print(f"Verified embedded {name}: bundled frameworks and startup")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    validate(parser.parse_args().app.resolve(strict=True))
