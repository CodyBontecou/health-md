#!/usr/bin/env python3
"""Read-only availability audit; never downloads or executes installers/binaries.

Publication is NOT signature verification, runtime QA, or stable qualification.
REST contract: https://docs.github.com/en/rest/releases/releases#get-a-release-by-tag-name
"""
import base64
import json
import os
from pathlib import Path
import re
from urllib.error import HTTPError
from urllib.parse import quote
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[3]
SPEC = ROOT / "apps/cli/docs/release-availability.json"
ARCHIVES = (
    "healthmd-cli-aarch64-apple-darwin.tar.xz",
    "healthmd-cli-x86_64-apple-darwin.tar.xz",
    "healthmd-cli-aarch64-unknown-linux-gnu.tar.xz",
    "healthmd-cli-x86_64-unknown-linux-gnu.tar.xz",
    "healthmd-cli-x86_64-pc-windows-msvc.zip",
    "healthmd-cli-aarch64-apple-darwin.dmg",
    "healthmd-cli-x86_64-apple-darwin.dmg",
)
REQUIRED = ARCHIVES + tuple(f"{name}.sha256" for name in ARCHIVES) + (
    "healthmd-cli-installer.sh", "healthmd-cli-installer.ps1", "healthmd.rb",
    "release-identities.json", "sha256.sum", "sha256.sum.sigstore.json",
)


def validate_release(release, repository, version):
    tag = f"healthmd-cli/v{version}"
    if (release.get("tag_name") != tag or release.get("draft") is not False
            or not release.get("published_at") or release.get("prerelease") is not True):
        raise ValueError(f"{tag} is not a published preview")
    assets = release.get("assets", [])
    names = [asset["name"] for asset in assets]
    if len(set(names)) != len(names):
        raise ValueError("duplicate release asset")
    by_name = {asset["name"]: asset for asset in assets}
    base = f"https://github.com/{repository}/releases/download/{tag}"
    for name in REQUIRED:
        asset = by_name.get(name, {})
        if (asset.get("state") != "uploaded" or asset.get("size", 0) <= 0
                or asset.get("browser_download_url") != f"{base}/{name}"):
            raise ValueError(f"missing, empty, incomplete, or misdirected asset: {name}")
    return by_name


def validate_checksums(text):
    entries = {}
    for line in text.splitlines():
        match = re.fullmatch(r"([0-9a-f]{64})  ([A-Za-z0-9_.-]+)", line)
        if not match or match[2] in entries:
            raise ValueError("malformed or duplicate checksum entry")
        entries[match[2]] = match[1]
    # The signed manifest cannot checksum itself or its detached signature bundle.
    for name in REQUIRED:
        if name not in ("sha256.sum", "sha256.sum.sigstore.json") and name not in entries:
            raise ValueError(f"checksum missing: {name}")
    return entries


def validate_formula(text, repository, version, checksums):
    if re.search(r'^\s*version "([^"]+)"', text, re.M).group(1) != version:
        raise ValueError("tap version differs from advertised preview")
    pairs = re.findall(r'url "([^"]+)"\s+sha256 "([0-9a-f]{64})"', text)
    base = f"https://github.com/{repository}/releases/download/healthmd-cli/v{version}/"
    expected = {base + name for name in ARCHIVES if "windows" not in name and name.endswith(".tar.xz")}
    if {url for url, _ in pairs} != expected or len(pairs) != len(expected):
        raise ValueError("tap URLs differ from published desktop archives")
    for url, digest in pairs:
        if digest != checksums[url.rsplit("/", 1)[1]]:
            raise ValueError("tap archive checksum mismatch")


def validate_install_examples(root, version):
    readme = (root / "apps/cli/README.md").read_text()
    pinned = re.findall(r"(?:VERSION=|\$Version = )'([^']+)'", readme)
    skill = (root / ".agents/skills/healthmd-cli/SKILL.md").read_text()
    pinned += re.findall(r"git checkout healthmd-cli/v([^\s]+)", skill)
    if len(pinned) != 3 or any(value != version for value in pinned):
        raise ValueError("README/consumer skill install versions differ from audited preview")


def fetch(url, *, api=False, limit=2 * 1024 * 1024):
    headers = {"User-Agent": "healthmd-release-availability-audit"}
    if api:
        headers.update({"Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28"})
        token = os.environ.get("GH_TOKEN")
        if token:
            headers["Authorization"] = f"Bearer {token}"
    with urlopen(Request(url, headers=headers), timeout=30) as response:
        body = response.read(limit + 1)
    if len(body) > limit:
        raise ValueError("availability response exceeds size limit")
    return body


def audit(spec, get=fetch):
    repository, version = spec["repository"], spec["published_preview"]
    api = f"https://api.github.com/repos/{repository}"
    tag_url = lambda v: f"{api}/releases/tags/{quote('healthmd-cli/v' + v, safe='')}"
    release = json.loads(get(tag_url(version), api=True))
    assets = validate_release(release, repository, version)
    checksums = validate_checksums(get(assets["sha256.sum"]["browser_download_url"], limit=65536).decode())
    formula_response = json.loads(get("https://api.github.com/repos/CodyBontecou/homebrew-tap/contents/Formula/healthmd.rb", api=True))
    formula = base64.b64decode(formula_response["content"]).decode()
    validate_formula(formula, repository, version, checksums)
    for pending in spec["pending"]:
        try:
            candidate = json.loads(get(tag_url(pending), api=True))
        except HTTPError as error:
            if error.code != 404:
                raise
            # Public/read-only tokens cannot see drafts. 404 does not prove a draft exists.
            print(f"{pending}: not publicly available; draft status from dated maintainer audit")
            continue
        if candidate.get("draft") is not True:
            raise ValueError(f"{pending} is no longer a pending draft; refresh availability documentation")
        print(f"{pending}: draft, {len(candidate.get('assets', []))} assets")
    print(f"{release['html_url']}: published preview; {len(REQUIRED)} required assets uploaded; checksum closure and tap match")
    print("Availability only: installers/binaries not executed; signatures and device qualification not verified.")


if __name__ == "__main__":
    try:
        spec = json.loads(SPEC.read_text())
        validate_install_examples(ROOT, spec["published_preview"])
        audit(spec)
    except (ValueError, KeyError, AttributeError, OSError) as error:
        raise SystemExit(f"release availability audit failed: {error}")
