#!/usr/bin/env python3
"""Remove Xcode's build-only package lookup from embedded helper copies."""
import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


def relocate(app, source_helpers=None):
    identity = os.environ.get("EXPANDED_CODE_SIGN_IDENTITY", "") or "-"
    if os.environ.get("CODE_SIGNING_ALLOWED") == "NO":
        identity = "-"
    destination = app / "Contents" / "Helpers"
    source = source_helpers or destination
    with tempfile.TemporaryDirectory(prefix="healthmd-helpers-", dir=os.environ.get("TEMP_DIR")) as temporary:
        for name in ("healthmd", "healthmd-mcp"):
            helper = Path(temporary) / name
            shutil.copy2(source / name, helper)
            commands = subprocess.check_output(["otool", "-l", str(helper)], text=True)
            paths = re.findall(r"cmd LC_RPATH\s+cmdsize \d+\s+path (.*?) \(offset", commands)
            if "@loader_path/../Frameworks" not in paths:
                raise ValueError(f"{name}: missing bundled framework lookup before relocation")
            build_paths = sorted({path for path in paths if Path(path).is_absolute() and Path(path).name == "PackageFrameworks"})
            if build_paths:
                for path in build_paths:
                    subprocess.run(["install_name_tool", "-delete_rpath", path, str(helper)], check=True)
                signing = ["codesign", "--force", "--sign", identity,
                           "--preserve-metadata=identifier,entitlements,requirements,flags,runtime"]
                if identity == "-" or os.environ.get("CONFIGURATION", "").startswith("Debug"):
                    signing.append("--timestamp=none")
                subprocess.run([*signing, str(helper)], check=True)
            subprocess.run(["codesign", "--verify", "--strict", str(helper)], check=True)
            destination.mkdir(parents=True, exist_ok=True)
            if (destination / name).is_symlink():
                raise ValueError(f"{name}: refusing a symlink in the embedded helper destination")
            shutil.copy2(helper, destination / name)
            print(f"Embedded {name}: bundled framework lookup, no build-only package lookup")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--source-helpers", type=Path)
    args = parser.parse_args()
    relocate(args.app.resolve(strict=True), args.source_helpers)
