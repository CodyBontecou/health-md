#!/usr/bin/env python3
"""Verify retained evidence for the committed Google Play Wear screenshot transaction."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import re
from pathlib import Path

SHA256 = re.compile(r"^[0-9a-f]{64}$")
EXPECTED_FILES = {"receipt.json", "pre-commit-listing.json", "remote-listing.json", "commit-response.json"}
EXPECTED_IMAGES = {"wear-app.png", "wear-tile.png"}


def fail(message: str) -> None:
    raise SystemExit(f"Wear screenshot upload evidence: {message}")


def load_json(path: Path) -> object:
    if not path.is_file():
        fail(f"missing {path}")
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        fail(f"invalid JSON in {path}: {error}")


def verify_checksums(root: Path) -> None:
    sums = root / "SHA256SUMS"
    if not sums.is_file():
        fail(f"missing {sums}")
    listed: set[str] = set()
    for line in sums.read_text(encoding="utf-8").splitlines():
        parts = line.split(None, 1)
        if len(parts) != 2:
            fail(f"invalid checksum line: {line!r}")
        digest, name = parts
        name = name.lstrip("*")
        if not SHA256.fullmatch(digest.lower()) or name in listed or name not in EXPECTED_FILES:
            fail(f"invalid checksum entry: {line!r}")
        target = root / name
        if not target.is_file() or hashlib.sha256(target.read_bytes()).hexdigest() != digest.lower():
            fail(f"checksum mismatch: {target}")
        listed.add(name)
    if listed != EXPECTED_FILES:
        fail(f"checksum inventory differs: {sorted(listed)}")
    actual = {path.name for path in root.iterdir() if path.is_file() and path.name != "SHA256SUMS"}
    if actual != EXPECTED_FILES:
        fail(f"retained file inventory differs: {sorted(actual)}")


def require_sha(value: object, label: str) -> str:
    if not isinstance(value, str) or not SHA256.fullmatch(value):
        fail(f"{label} must be lowercase SHA-256")
    return value


def parse_time(value: object) -> None:
    if not isinstance(value, str) or not value.endswith("Z"):
        fail("committedAtUtc must be an explicit UTC instant")
    try:
        parsed = dt.datetime.fromisoformat(value.removesuffix("Z") + "+00:00")
    except ValueError:
        fail("committedAtUtc is invalid")
    if parsed.tzinfo is None:
        fail("committedAtUtc lacks timezone")


def verify(
    root: Path,
    assets: Path,
    wear_apk_sha256: str,
    play_signer_sha256: str,
    version_name: str,
    phone_version_code: int,
    wear_version_code: int,
    reviewer: str,
    review_ticket: str,
) -> None:
    if not root.is_dir() or not assets.is_dir():
        fail("evidence root and screenshot assets directory are required")
    require_sha(wear_apk_sha256, "expected Wear APK")
    require_sha(play_signer_sha256, "expected Play signer")
    if not re.fullmatch(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", version_name):
        fail("expected version name is invalid")
    if phone_version_code < 1 or wear_version_code < 1 or not reviewer or not review_ticket:
        fail("version codes, protected reviewer, and protected review ticket are required")

    verify_checksums(root)
    receipt = load_json(root / "receipt.json")
    pre_listing = load_json(root / "pre-commit-listing.json")
    listing = load_json(root / "remote-listing.json")
    commit = load_json(root / "commit-response.json")
    if not all(isinstance(value, dict) for value in (receipt, pre_listing, listing, commit)):
        fail("receipt, pre-commit listing, committed listing, and commit response must be JSON objects")

    expected_fields = {
        "schemaVersion": 1,
        "package": "com.healthmd.android",
        "versionName": version_name,
        "phoneVersionCode": phone_version_code,
        "wearVersionCode": wear_version_code,
        "wearApkSha256": wear_apk_sha256,
        "playAppSigningCertSha256": play_signer_sha256,
        "language": "en-US",
        "imageType": "wearScreenshots",
        "reviewer": reviewer,
        "reviewTicket": review_ticket,
        "committed": True,
    }
    for key, expected in expected_fields.items():
        if receipt.get(key) != expected:
            fail(f"receipt {key} differs from protected expectation")
    if not isinstance(receipt.get("playEditId"), str) or not receipt["playEditId"]:
        fail("receipt lacks Play edit ID")
    if not isinstance(receipt.get("commitResponseReceived"), bool):
        fail("receipt lacks commit response/reconciliation classification")
    if not isinstance(receipt.get("preCommitAlreadyMatched"), bool):
        fail("receipt lacks pre-commit state classification")
    if commit.get("editId") != receipt["playEditId"]:
        fail("Play commit evidence edit ID differs from receipt")
    if commit.get("responseReceived") != receipt["commitResponseReceived"]:
        fail("Play commit response classification differs from receipt")
    if commit.get("reconciledAgainstCommittedListing") is not True:
        fail("Play commit was not reconciled against committed listing state")
    if commit.get("preCommitAlreadyMatched") != receipt["preCommitAlreadyMatched"]:
        fail("pre-commit classification differs from receipt")
    exit_code = commit.get("commitExitCode")
    if not isinstance(exit_code, int) or isinstance(exit_code, bool) or exit_code < 0:
        fail("Play commit exit code is invalid")
    parse_time(receipt.get("committedAtUtc"))

    local_hashes: dict[str, str] = {}
    for name in EXPECTED_IMAGES:
        path = assets / name
        if not path.is_file():
            fail(f"missing screenshot asset: {path}")
        local_hashes[name] = hashlib.sha256(path.read_bytes()).hexdigest()

    pre_images = pre_listing.get("images")
    if not isinstance(pre_images, list):
        fail("retained pre-commit Play listing has no image list")
    pre_hashes = []
    for image in pre_images:
        if not isinstance(image, dict):
            fail("retained pre-commit Play image entry is invalid")
        pre_hashes.append(require_sha(str(image.get("sha256", "")).lower(), "pre-commit remote image"))
    pre_exact = len(pre_hashes) == 2 and sorted(pre_hashes) == sorted(local_hashes.values())
    if receipt["preCommitAlreadyMatched"] != pre_exact:
        fail("retained pre-commit listing differs from its classification")

    response = commit.get("response")
    if receipt["commitResponseReceived"]:
        if exit_code != 0 or not isinstance(response, dict) or response.get("id") != receipt["playEditId"]:
            fail("received Play commit response differs from receipt")
    else:
        if response is not None or exit_code in {0, 22} or pre_exact:
            fail("ambiguous Play commit is not safely attributable to this edit")

    images = receipt.get("images")
    if not isinstance(images, list) or len(images) != 2:
        fail("receipt must contain exactly two images")
    receipt_hashes: dict[str, str] = {}
    for image in images:
        if not isinstance(image, dict) or set(image) != {"fileName", "sha256"}:
            fail("receipt image schema differs")
        name = image["fileName"]
        digest = require_sha(image["sha256"], f"receipt image {name}")
        if name in receipt_hashes:
            fail(f"duplicate receipt image: {name}")
        receipt_hashes[name] = digest
    if receipt_hashes != local_hashes:
        fail("receipt image hashes differ from canonical assets")

    remote_images = listing.get("images")
    if not isinstance(remote_images, list) or len(remote_images) != 2:
        fail("retained Play listing must contain exactly two images")
    remote_hashes = []
    for image in remote_images:
        if not isinstance(image, dict):
            fail("retained Play image entry is invalid")
        remote_hashes.append(require_sha(str(image.get("sha256", "")).lower(), "remote image"))
    if sorted(remote_hashes) != sorted(local_hashes.values()):
        fail("retained Play listing hashes differ from approved assets")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("root", type=Path)
    parser.add_argument("--assets", type=Path, required=True)
    parser.add_argument("--wear-apk-sha256", required=True)
    parser.add_argument("--play-signer-sha256", required=True)
    parser.add_argument("--version-name", required=True)
    parser.add_argument("--phone-version-code", type=int, required=True)
    parser.add_argument("--wear-version-code", type=int, required=True)
    parser.add_argument("--expected-reviewer", required=True)
    parser.add_argument("--expected-review-ticket", required=True)
    args = parser.parse_args()
    verify(
        args.root,
        args.assets,
        args.wear_apk_sha256,
        args.play_signer_sha256,
        args.version_name,
        args.phone_version_code,
        args.wear_version_code,
        args.expected_reviewer,
        args.expected_review_ticket,
    )
    print("Wear screenshot upload evidence: committed transaction receipt is valid")


if __name__ == "__main__":
    main()
