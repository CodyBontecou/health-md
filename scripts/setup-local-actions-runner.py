#!/usr/bin/env python3
"""Register the Apple pilot runner only with its private controller; never install a service."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import sys
import tarfile
import tempfile
import urllib.request


REPOSITORY = "CodyBontecou/health-md-local-ci"
LABEL = "healthmd-local-pilot-macos-arm64"
ROOT = Path(__file__).resolve().parents[1]


def github(endpoint: str, method: str = "GET"):
    result = subprocess.run(["gh", "api", "--method", method, endpoint],
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        raise ValueError(f"GitHub access failed for {endpoint}; verify gh auth login and repository admin access")
    return json.loads(result.stdout)


def require_private_controller() -> None:
    metadata = github(f"repos/{REPOSITORY}")
    if not isinstance(metadata, dict) or metadata.get("full_name") != REPOSITORY:
        raise ValueError(f"Runner controller must be exactly {REPOSITORY}")
    owner = metadata.get("owner")
    if (not isinstance(owner, dict) or owner.get("login") != REPOSITORY.split("/", 1)[0]
            or owner.get("type") != "User"):
        raise ValueError("Runner controller must remain owned by the expected personal account")
    if metadata.get("private") is not True:
        raise ValueError("Runner controller must be private; public runner registration is prohibited")
    if metadata.get("default_branch") != "main":
        raise ValueError("Runner controller default branch must be main")
    permissions = metadata.get("permissions")
    if not isinstance(permissions, dict) or permissions.get("admin") is not True:
        raise ValueError("Authenticated GitHub access must have controller repository admin permission")


def runner_asset(release: dict) -> tuple[str, str]:
    assets = [item for item in release.get("assets", [])
              if re.fullmatch(r"actions-runner-osx-arm64-[0-9.]+\.tar\.gz", item.get("name", ""))]
    if len(assets) != 1:
        raise ValueError("Official runner release must contain exactly one macOS ARM64 archive")
    asset = assets[0]
    digest = asset.get("digest", "")
    if not re.fullmatch(r"sha256:[0-9a-f]{64}", digest):
        raise ValueError("Official runner archive has no valid SHA-256 digest")
    url = asset.get("browser_download_url", "")
    if not url.startswith("https://github.com/actions/runner/releases/download/"):
        raise ValueError("Runner archive URL must belong to the official actions/runner repository")
    return url, digest.removeprefix("sha256:")


def registered_runners() -> list:
    runners = []
    page = 1
    while True:
        result = github(f"repos/{REPOSITORY}/actions/runners?per_page=100&page={page}")
        runners.extend(result["runners"])
        if len(result["runners"]) < 100:
            return runners
        page += 1


def extract_archive(archive: Path, destination: Path, expected: str) -> None:
    digest = hashlib.sha256()
    with archive.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    if digest.hexdigest() != expected:
        raise ValueError("Runner archive SHA-256 mismatch; nothing was executed")
    with tarfile.open(archive, "r:gz") as bundle:
        members = bundle.getmembers()
        links = []
        for member in members:
            target = (destination / member.name).resolve()
            if not target.is_relative_to(destination.resolve()):
                raise ValueError("Runner archive contains an escaping path")
            if member.issym() or member.islnk():
                link_base = target.parent if member.issym() else destination
                if not (link_base / member.linkname).resolve().is_relative_to(destination.resolve()):
                    raise ValueError("Runner archive contains an escaping link")
                links.append(destination / member.name)
            elif not (member.isfile() or member.isdir()):
                raise ValueError("Runner archive contains an unsupported special file")
        # Recheck resolved paths immediately before each write, including links created earlier.
        for member in members:
            target = (destination / member.name).resolve()
            if not target.is_relative_to(destination.resolve()):
                raise ValueError("Runner archive writes through an escaping link")
            if member.issym() or member.islnk():
                link_base = target.parent if member.issym() else destination
                if not (link_base / member.linkname).resolve().is_relative_to(destination.resolve()):
                    raise ValueError("Runner archive links through an escaping link")
            bundle.extract(member, destination)
        if any(not link.resolve().is_relative_to(destination.resolve()) for link in links):
            raise ValueError("Runner archive contains an escaping link chain")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runner-dir", type=Path, default=ROOT / ".external" / "local-actions-runner")
    parser.add_argument("--name", default="healthmd-local-pilot")
    args = parser.parse_args()
    os.umask(0o077)
    destination = args.runner_dir.expanduser().resolve()
    try:
        if platform.system() != "Darwin" or platform.machine() != "arm64":
            raise ValueError("This runner is for native macOS ARM64 only")
        if not re.fullmatch(r"[A-Za-z0-9_.-]{1,64}", args.name):
            raise ValueError("Runner name must use 1-64 letters, digits, periods, underscores or hyphens")
        if destination.exists() and any(destination.iterdir()):
            raise ValueError(f"Runner directory is not empty: {destination}; refusing to replace registration")
        # Check the actual API visibility/identity before any archive download,
        # filesystem installation, registration-token request or runner execution.
        require_private_controller()
        runners = registered_runners()
        if any(item["name"] == args.name for item in runners):
            raise ValueError(f"Runner name {args.name!r} is already registered; refusing replacement")
        release = github("repos/actions/runner/releases/latest")
        url, expected = runner_asset(release)
        destination.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="healthmd-runner-") as temporary:
            archive = Path(temporary) / "runner.tar.gz"
            print(f"Downloading official runner {release['tag_name']} and verifying SHA-256", flush=True)
            with urllib.request.urlopen(url, timeout=60) as response, archive.open("wb") as output:
                while chunk := response.read(1024 * 1024):
                    output.write(chunk)
            extract_archive(archive, destination, expected)
        token = github(f"repos/{REPOSITORY}/actions/runners/registration-token", "POST")["token"]
        environment = {key: value for key, value in os.environ.items()
                       if key not in {"GH_TOKEN", "GITHUB_TOKEN", "GH_ENTERPRISE_TOKEN", "GITHUB_ENTERPRISE_TOKEN"}}
        registration = subprocess.run([str(destination / "config.sh"), "--unattended",
            "--url", f"https://github.com/{REPOSITORY}", "--token", token, "--name", args.name,
            "--no-default-labels", "--labels", LABEL, "--work", "_work"], cwd=destination,
            env=environment, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        if registration.returncode:
            raise ValueError("Runner registration failed: " + registration.stdout.replace(token, "[redacted]"))
        matches = [item for item in registered_runners() if item["name"] == args.name]
        if len(matches) != 1 or {item["name"] for item in matches[0]["labels"]} != {LABEL}:
            raise ValueError("Registered labels differ from the isolated pilot policy; do not start this runner")
        print(f"Registered {args.name} on private controller {REPOSITORY} with only label {LABEL}")
        print(f"Runner directory: {destination}")
        print("Start in that directory: env -u GH_TOKEN -u GITHUB_TOKEN -u GH_ENTERPRISE_TOKEN -u GITHUB_ENTERPRISE_TOKEN ./run.sh")
        print("Stop with Ctrl-C. No background service was installed.")
        return 0
    except (ValueError, OSError, KeyError, json.JSONDecodeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
