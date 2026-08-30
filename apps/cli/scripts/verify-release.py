#!/usr/bin/env python3
"""Verify the immutable identity and version closure of a CLI release."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import tomllib
from pathlib import Path
from typing import Any

TAG_RE = re.compile(
    r"^healthmd-cli/v(?P<version>"
    r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)"
    r"(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?"
    r"(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?"
    r")$"
)
PUBLISHED = (
    "healthmd-protocol",
    "healthmd-operations",
    "healthmd-client",
    "healthmd-mcp",
    "healthmd-cli",
)
NON_PUBLISHED = ("healthmd-core", "healthmd-core-uniffi", "xtask")
ALL_PACKAGES = set(PUBLISHED + NON_PUBLISHED)
MOBILE_QUALIFICATION_LABELS = (
    "iPhone status/raw/extract/generated files/resume/cancel",
    "iPhone portable typed MCP queries",
    "Android status/provider-native raw/generated files/resume/cancel",
)
PENDING_MOBILE_QUALIFICATION = "**Pending; no public CLI/mobile pair qualified yet**"
QUALIFIED_MOBILE_RE = re.compile(
    r"^\*\*Qualified:\*\* "
    r"mobile_build=[^;|]{1,128}; "
    r"source_commit=[0-9a-f]{40}; "
    r"device_os=[^;|]{1,128}; "
    r"lan=pass; tailscale=pass; "
    r"evidence_sha256=[0-9a-f]{64}$"
)


def fail(message: str) -> None:
    raise SystemExit(f"release identity error: {message}")


def run(*arguments: str, cwd: Path) -> str:
    completed = subprocess.run(
        arguments,
        cwd=cwd,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return completed.stdout.strip()


def metadata(manifest: Path) -> dict[str, Any]:
    return json.loads(
        run(
            "cargo",
            "metadata",
            "--manifest-path",
            str(manifest),
            "--no-deps",
            "--format-version=1",
            cwd=manifest.parent,
        )
    )


def lock_versions(lockfile: Path) -> dict[str, str]:
    with lockfile.open("rb") as handle:
        payload = tomllib.load(handle)
    return {
        package["name"]: package["version"]
        for package in payload["package"]
        if package["name"] in ALL_PACKAGES
    }


def validate_mobile_qualification(path: Path, require_qualified: bool) -> None:
    rows: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.startswith("|"):
            continue
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if len(cells) != 4 or cells[0] not in MOBILE_QUALIFICATION_LABELS:
            continue
        if cells[0] in rows:
            fail(f"duplicate mobile compatibility row: {cells[0]}")
        rows[cells[0]] = cells[3]
    if set(rows) != set(MOBILE_QUALIFICATION_LABELS):
        fail("mobile compatibility ledger is missing a required qualification row")
    for label in MOBILE_QUALIFICATION_LABELS:
        result = rows[label]
        if result == PENDING_MOBILE_QUALIFICATION:
            if require_qualified:
                fail(f"mobile compatibility remains pending for {label}")
            continue
        if QUALIFIED_MOBILE_RE.fullmatch(result) is None:
            fail(f"mobile compatibility result has an invalid qualified record for {label}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tag")
    parser.add_argument("--sha")
    parser.add_argument("--main-sha")
    arguments = parser.parse_args()

    root = Path(__file__).resolve().parents[3]
    cli_manifest = root / "apps/cli/Cargo.toml"
    core_manifest = root / "packages/healthmd-core-rust/Cargo.toml"
    signing_identities = json.loads(
        (root / "apps/cli/release-identities.json").read_text(encoding="utf-8")
    )
    expected_apple = {
        "team_id": "67KC823C9A",
        "healthmd_identifier": "md.health.cli.healthmd",
        "healthmd_mcp_identifier": "md.health.cli.healthmd-mcp",
    }
    expected_sigstore = {
        "certificate_identity_template": (
            "https://github.com/CodyBontecou/health-md/.github/workflows/"
            "cli-release.yml@refs/tags/healthmd-cli/v<VERSION>"
        ),
        "oidc_issuer": "https://token.actions.githubusercontent.com",
    }
    windows_identity = signing_identities.get("windows")
    if (
        set(signing_identities) != {
            "schema",
            "schema_version",
            "apple",
            "windows",
            "sigstore",
        }
        or signing_identities.get("schema")
        != "healthmd.cli_release_signing_identities"
        or signing_identities.get("schema_version") != 1
        or signing_identities.get("apple") != expected_apple
        or signing_identities.get("sigstore") != expected_sigstore
        or not isinstance(windows_identity, dict)
        or set(windows_identity) != {"publisher_subject", "status"}
        or windows_identity.get("status")
        not in {"pending_external_certificate_provisioning", "qualified"}
        or (
            windows_identity.get("status") == "pending_external_certificate_provisioning"
            and windows_identity.get("publisher_subject") is not None
        )
        or (
            windows_identity.get("status") == "qualified"
            and (
                not isinstance(windows_identity.get("publisher_subject"), str)
                or not windows_identity["publisher_subject"].strip()
            )
        )
    ):
        fail("release signing identity ledger is invalid")
    cli = metadata(cli_manifest)
    core = metadata(core_manifest)
    packages = {package["name"]: package for package in cli["packages"] + core["packages"]}
    if set(packages) != ALL_PACKAGES:
        fail(f"unexpected workspace package set: {sorted(packages)}")

    if arguments.tag:
        match = TAG_RE.fullmatch(arguments.tag)
        if match is None:
            fail("tag must be exact healthmd-cli/v<Cargo-SemVer>")
        version = match.group("version")
        validate_mobile_qualification(
            root / "apps/cli/docs/mobile-compatibility.md",
            require_qualified=True,
        )
        if not arguments.sha or not arguments.main_sha:
            fail("--tag requires --sha and --main-sha")
        tag_sha = run("git", "rev-parse", f"refs/tags/{arguments.tag}^{{commit}}", cwd=root)
        if tag_sha != arguments.sha:
            fail(f"tag commit {tag_sha} does not equal workflow SHA {arguments.sha}")
        if arguments.main_sha != arguments.sha:
            fail(f"main commit {arguments.main_sha} does not equal tag SHA {arguments.sha}")
        windows_identity = signing_identities.get("windows", {})
        # Windows Authenticode may be deferred: a pending ledger with no publisher subject is a
        # deliberate unsigned-release state (Windows archives ship Authenticode-unsigned with
        # integrity covered by the Sigstore-signed checksum closure). Once the ledger records a
        # qualified subject, never regress it to pending for a later release.
        if windows_identity.get("status") == "qualified" and not (
            isinstance(windows_identity.get("publisher_subject"), str)
            and windows_identity["publisher_subject"].strip()
        ):
            fail("qualified Windows publisher identity must carry a non-empty subject")
    else:
        if arguments.sha or arguments.main_sha:
            fail("--sha and --main-sha are valid only with --tag")
        version = packages["healthmd-cli"]["version"]
        validate_mobile_qualification(
            root / "apps/cli/docs/mobile-compatibility.md",
            require_qualified=False,
        )

    for name, package in sorted(packages.items()):
        if package["version"] != version:
            fail(f"{name} has version {package['version']}, expected {version}")
        expected_publish = ["crates-io"] if name in PUBLISHED else []
        if (package.get("publish") or []) != expected_publish:
            fail(f"{name} publish policy is not {expected_publish}")
        for dependency in package["dependencies"]:
            if dependency["name"] in ALL_PACKAGES and dependency["req"] != f"={version}":
                fail(
                    f"{name} dependency {dependency['name']} uses {dependency['req']}, "
                    f"expected ={version}"
                )

    expected_cli_lock = {
        name: version
        for name in (
            "healthmd-protocol",
            "healthmd-operations",
            "healthmd-client",
            "healthmd-mcp",
            "healthmd-cli",
        )
    }
    expected_core_lock = {
        name: version
        for name in ("healthmd-protocol", "healthmd-core", "healthmd-core-uniffi", "xtask")
    }
    if lock_versions(root / "apps/cli/Cargo.lock") != expected_cli_lock:
        fail("CLI lockfile local package versions do not match the release")
    if lock_versions(root / "packages/healthmd-core-rust/Cargo.lock") != expected_core_lock:
        fail("shared-core lockfile local package versions do not match the release")

    print(
        json.dumps(
            {
                "schema": "healthmd.cli_release_identity",
                "schema_version": 1,
                "version": version,
                "publication_order": list(PUBLISHED),
                "tag": arguments.tag,
                "sha": arguments.sha,
                "windows_signing": windows_identity.get("status"),
            },
            separators=(",", ":"),
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except subprocess.CalledProcessError as error:
        print(error.stderr, file=sys.stderr)
        raise SystemExit(error.returncode) from error
