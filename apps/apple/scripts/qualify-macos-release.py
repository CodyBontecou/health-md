#!/usr/bin/env python3
"""Health-free macOS release qualification harness.

`--plan` prints the immutable check inventory on any host. `--run` requires macOS,
inspects one app bundle, and writes a JSON evidence draft. It never marks physical
or public-build checks passed on their own; an owner-reviewed retained record must
supply those results after the exact candidate is exercised.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import plistlib
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

CHECKS = [
    ("bundle.info", "automated", "Bundle version/build and identifier match the candidate."),
    ("bundle.codesign", "automated", "App and nested code pass strict deep signature verification."),
    ("bundle.gatekeeper", "automated", "Gatekeeper accepts the distributed app bundle."),
    ("helper.cli", "automated", "Bundled healthmd helper exists and reports the app version."),
    ("helper.mcp", "automated", "Bundled healthmd-mcp exists and completes bounded initialize/tools/list."),
    ("helper.tool_catalog", "automated", "Bundled Mac MCP exposes exactly 21 fixed tools."),
    ("readiness.keychain", "runtime", "Doctor reports usable encrypted-context key material without exposing it."),
    ("readiness.bookmark", "runtime", "Configured security-scoped destination bookmark remains healthy."),
    ("readiness.loopback", "runtime", "Loopback API/MCP reaches the running Mac app only on its fixed local boundary."),
    ("readiness.context", "runtime", "Encrypted context write/query/delete and byte accounting pass."),
    ("connect.nearby", "physical", "Exact iPhone build connects over Nearby and refreshes a bounded context scope."),
    ("connect.lan", "physical", "Exact iPhone build connects over LAN and completes/resumes a durable job."),
    ("connect.tailscale", "physical", "Exact iPhone build connects over Tailscale without transport fallback."),
    ("lifecycle.sleep_wake", "physical", "Sleep/wake and closed-lid expectations are truthful; no server guarantee is inferred."),
    ("lifecycle.upgrade", "physical", "Upgrade preserves signing principal, Keychain access, context, and bookmarks."),
    ("os.rc", "physical", "Critical matrix passes on the exact macOS 27 RC build."),
    ("os.public", "physical", "Critical matrix is repeated on the exact public macOS 27 build."),
]


def run(command: list[str], timeout: int = 30, input_text: str | None = None) -> dict:
    try:
        result = subprocess.run(
            command,
            input=input_text,
            text=True,
            capture_output=True,
            timeout=timeout,
            check=False,
            env={**os.environ, "LC_ALL": "C"},
        )
        return {
            "status": "pass" if result.returncode == 0 else "fail",
            "exit_code": result.returncode,
            "detail": (result.stderr or result.stdout).strip()[:1000],
        }
    except (OSError, subprocess.TimeoutExpired) as error:
        return {"status": "fail", "exit_code": None, "detail": type(error).__name__}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def probe_mcp(helper: Path) -> dict:
    messages = [
        {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-11-25", "capabilities": {}}},
        {"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}},
        {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}},
    ]
    framed = "".join(json.dumps(message, separators=(",", ":")) + "\n" for message in messages)
    # MCP stdio implementations in this repository emit one JSON object per line.
    responses = []
    process = subprocess.run(
        [str(helper)], input=framed, text=True, capture_output=True, timeout=15, check=False
    )
    for line in process.stdout.splitlines():
        try:
            responses.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    tools_response = next((value for value in responses if value.get("id") == 2), None)
    tools = (tools_response or {}).get("result", {}).get("tools", [])
    return {
        "status": "pass" if process.returncode == 0 and len(tools) == 21 else "fail",
        "exit_code": process.returncode,
        "tool_count": len(tools),
        "detail": "bounded initialize/tools-list probe",
    }


def evidence(app: Path, expected_version: str | None) -> dict:
    info_path = app / "Contents" / "Info.plist"
    info = {}
    if info_path.exists():
        with info_path.open("rb") as stream:
            info = plistlib.load(stream)
    version = info.get("CFBundleShortVersionString")
    build = info.get("CFBundleVersion")
    identifier = info.get("CFBundleIdentifier")
    helper_dir = app / "Contents" / "Helpers"
    cli = helper_dir / "healthmd"
    mcp = helper_dir / "healthmd-mcp"
    executable = app / "Contents" / "MacOS" / str(info.get("CFBundleExecutable", "HealthMd"))

    checks = {key: {"status": "pending", "class": kind, "detail": description} for key, kind, description in CHECKS}
    info_ok = bool(version and build and identifier and (not expected_version or version == expected_version))
    checks["bundle.info"] = {
        "status": "pass" if info_ok else "fail",
        "class": "automated",
        "detail": f"identifier={identifier!s}; version={version!s}; build={build!s}",
    }
    checks["bundle.codesign"] = {"class": "automated", **run(["codesign", "--verify", "--deep", "--strict", "--verbose=2", str(app)])}
    checks["bundle.gatekeeper"] = {"class": "automated", **run(["spctl", "--assess", "--type", "execute", "--verbose=2", str(app)])}
    checks["helper.cli"] = {
        "class": "automated",
        **(run([str(cli), "--version"]) if cli.is_file() and os.access(cli, os.X_OK) else {"status": "fail", "exit_code": None, "detail": "missing helper"}),
    }
    mcp_probe = probe_mcp(mcp) if mcp.is_file() and os.access(mcp, os.X_OK) else {"status": "fail", "exit_code": None, "detail": "missing helper", "tool_count": 0}
    checks["helper.mcp"] = {"class": "automated", **mcp_probe}
    checks["helper.tool_catalog"] = {
        "class": "automated",
        "status": "pass" if mcp_probe.get("tool_count") == 21 else "fail",
        "detail": f"tool_count={mcp_probe.get('tool_count', 0)}",
    }

    artifact_hash = sha256(executable) if executable.is_file() else None
    automated_pass = all(value["status"] == "pass" for value in checks.values() if value["class"] == "automated")
    return {
        "schema": "healthmd.macos_qualification_evidence",
        "schema_version": 1,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "candidate": {
            "app_path": str(app.resolve()),
            "bundle_identifier": identifier,
            "version": version,
            "build": build,
            "main_executable_sha256": artifact_hash,
        },
        "host": {
            "operating_system": platform.platform(),
            "machine": platform.machine(),
        },
        "checks": checks,
        "automated_preflight_passed": automated_pass,
        "certified_for_macos_27": False,
        "certification_blocker": "Exact RC and public-build physical evidence must be owner-reviewed and retained.",
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--plan", action="store_true")
    mode.add_argument("--run", action="store_true")
    parser.add_argument("--app", type=Path)
    parser.add_argument("--expected-version")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    if args.plan:
        print(json.dumps({"schema": "healthmd.macos_qualification_plan", "schema_version": 1, "checks": [dict(id=k, classification=t, description=d) for k, t, d in CHECKS]}, indent=2))
        return 0
    if platform.system() != "Darwin":
        parser.error("--run requires macOS; use --plan on other hosts")
    if not args.app or not args.output:
        parser.error("--run requires --app and --output")
    if not args.app.is_dir():
        parser.error("--app must name an existing app bundle")
    result = evidence(args.app, args.expected_version)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(args.output)
    return 0 if result["automated_preflight_passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
