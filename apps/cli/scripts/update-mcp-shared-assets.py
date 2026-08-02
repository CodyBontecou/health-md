#!/usr/bin/env python3
"""Refresh portable MCP assets shared with the Apple implementation."""

from __future__ import annotations

import argparse
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
MCP_ASSETS = ROOT / "cli" / "crates" / "healthmd-mcp" / "assets"
APPLE_MCP_APP = (
    ROOT
    / "apple"
    / "HealthMdCLI"
    / "Sources"
    / "HealthMdMCPCore"
    / "HealthMdMCPApp.swift"
)
REGISTRY = (
    ROOT.parent
    / "packages"
    / "healthmd-core-rust"
    / "crates"
    / "healthmd-core"
    / "registry"
    / "metric-registry-v1.json"
)


def generated_assets() -> dict[Path, bytes]:
    source = APPLE_MCP_APP.read_text()
    marker = 'static let html = #"""'
    start = source.index(marker) + len(marker)
    end = source.index('"""#', start)
    html = source[start:end].strip()

    # The runtime response projects only non-sensitive catalog fields; keeping the reviewed
    # registry byte-for-byte avoids a second generated contract.
    catalog = subprocess.check_output(
        [
            "cargo",
            "run",
            "--quiet",
            "--manifest-path",
            str(ROOT / "cli" / "Cargo.toml"),
            "-p",
            "healthmd-operations",
            "--example",
            "generate_mcp_catalog",
        ],
        cwd=ROOT.parent,
    )
    return {
        MCP_ASSETS / "mcp-tools-v1.json": catalog,
        MCP_ASSETS / "query-visualization-v1.html": html.encode(),
        MCP_ASSETS / "metric-registry-v1.json": REGISTRY.read_bytes(),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    arguments = parser.parse_args()
    stale: list[Path] = []
    for path, content in generated_assets().items():
        if arguments.check:
            if not path.exists() or path.read_bytes() != content:
                stale.append(path)
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
            print(path.relative_to(ROOT.parent))
    if stale:
        for path in stale:
            print(f"stale generated MCP asset: {path.relative_to(ROOT.parent)}", file=sys.stderr)
        print("run apps/cli/scripts/update-mcp-shared-assets.py", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
