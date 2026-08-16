#!/usr/bin/env python3
"""Bind canonical Wear Play PNGs to exact installed Play-signed capture receipts."""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import re
from pathlib import Path

SHA = re.compile(r"^[0-9a-f]{64}$")


def fail(message: str) -> None:
    raise SystemExit(f"Wear screenshot evidence: {message}")


def parse(path: Path) -> dict[str, str]:
    if not path.is_file():
        fail(f"missing {path}")
    values: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if "=" not in line:
            fail(f"invalid receipt line in {path}: {line!r}")
        key, value = line.split("=", 1)
        if not key or key in values:
            fail(f"duplicate/empty receipt key in {path}: {key!r}")
        values[key] = value
    return values


def verify_checksums(directory: Path) -> None:
    sums = directory / "SHA256SUMS"
    if not sums.is_file():
        fail(f"missing {sums}")
    entries: dict[str, str] = {}
    for line in sums.read_text(encoding="utf-8").splitlines():
        try:
            digest, name = line.split(None, 1)
        except ValueError:
            fail(f"invalid checksum line: {line!r}")
        name = name.lstrip("*")
        if not SHA.fullmatch(digest.lower()) or name not in {"receipt.txt", "signer.txt", "package.txt"}:
            fail(f"unsafe checksum entry: {line!r}")
        target = directory / name
        if not target.is_file() or hashlib.sha256(target.read_bytes()).hexdigest() != digest.lower():
            fail(f"checksum mismatch: {target}")
        entries[name] = digest.lower()
    if set(entries) != {"receipt.txt", "signer.txt", "package.txt"}:
        fail(f"{sums} must cover receipt.txt, signer.txt, and package.txt exactly")


def verify(
    asset_root: Path,
    evidence_root: Path,
    expected_apk: str,
    expected_signer: str,
    expected_wear_version_code: str | None = None,
    expected_version_name: str | None = None,
    expected_reviewer: str | None = None,
    expected_review_ticket: str | None = None,
) -> None:
    if not SHA.fullmatch(expected_apk) or not SHA.fullmatch(expected_signer):
        fail("expected APK and Play signer SHA-256 values must be lowercase hex")
    if expected_wear_version_code is None or expected_version_name is None:
        fail("expected Wear version code/name are required")
    if not expected_wear_version_code.isdigit() or not re.fullmatch(
        r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", expected_version_name
    ):
        fail("expected Wear version code/name are invalid")
    if not expected_reviewer or not expected_review_ticket:
        fail("protected expected screenshot reviewer and review ticket are required")
    observed_reviewer_ticket: tuple[str, str] | None = None
    for kind in ("app", "tile"):
        directory = evidence_root / kind
        verify_checksums(directory)
        receipt = parse(directory / "receipt.txt")
        expected = {
            "kind": kind,
            "version_code": expected_wear_version_code,
            "version_name": expected_version_name,
            "wear_base_apk_sha256": expected_apk,
            "play_app_signing_cert_sha256": expected_signer,
            "exact_release_ui_confirmed": "yes",
            "no_production_health_values_confirmed": "yes",
        }
        for key, value in expected.items():
            if receipt.get(key) != value:
                fail(f"{directory}/receipt.txt: expected {key}={value!r}")
        for key in ("watch_serial", "reviewer_id", "review_ticket"):
            if not receipt.get(key, "").strip():
                fail(f"{directory}/receipt.txt: independent {key} is required")
        try:
            captured = dt.datetime.fromisoformat(receipt.get("captured_utc", "").replace("Z", "+00:00"))
        except ValueError:
            fail(f"{directory}/receipt.txt: captured_utc is invalid")
        if captured.tzinfo is None:
            fail(f"{directory}/receipt.txt: captured_utc lacks timezone")
        reviewer_ticket = (receipt["reviewer_id"], receipt["review_ticket"])
        if observed_reviewer_ticket is None:
            observed_reviewer_ticket = reviewer_ticket
        elif reviewer_ticket != observed_reviewer_ticket:
            fail("app/Tile screenshot reviewer and ticket must match")
        if expected_reviewer is not None and receipt["reviewer_id"] != expected_reviewer:
            fail(f"{kind} reviewer differs from protected expected reviewer")
        if expected_review_ticket is not None and receipt["review_ticket"] != expected_review_ticket:
            fail(f"{kind} ticket differs from protected expected ticket")
        image = asset_root / f"wear-{kind}.png"
        if not image.is_file():
            fail(f"missing {image}")
        digest = hashlib.sha256(image.read_bytes()).hexdigest()
        if receipt.get("image_sha256") != digest:
            fail(f"{kind} receipt does not match canonical PNG")
        signer_text = (directory / "signer.txt").read_text(encoding="utf-8")
        match = re.search(r"^Signer #1 certificate SHA-256 digest: ([0-9A-Fa-f]{64})$", signer_text, re.MULTILINE)
        if not match or match.group(1).lower() != expected_signer:
            fail(f"{kind} signer output does not match authorized Play identity")
        package_text = (directory / "package.txt").read_text(encoding="utf-8", errors="replace")
        code_match = re.search(r"\bversionCode=(\d+)\b", package_text)
        name_match = re.search(r"\bversionName=([^\s]+)", package_text)
        if (
            not code_match or code_match.group(1) != expected_wear_version_code
            or not name_match or name_match.group(1) != expected_version_name
        ):
            fail(f"{kind} captured package output does not match the exact Wear release")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--assets", type=Path, default=Path("play-store/wear/screenshots"))
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--wear-apk-sha256", required=True)
    parser.add_argument("--play-signer-sha256", required=True)
    parser.add_argument("--wear-version-code", required=True)
    parser.add_argument("--version-name", required=True)
    parser.add_argument("--expected-reviewer", required=True)
    parser.add_argument("--expected-review-ticket", required=True)
    args = parser.parse_args()
    verify(
        args.assets, args.evidence, args.wear_apk_sha256, args.play_signer_sha256,
        args.wear_version_code, args.version_name,
        args.expected_reviewer, args.expected_review_ticket,
    )
    print("Wear screenshot evidence: canonical PNGs match exact installed Play-signed capture receipts")


if __name__ == "__main__":
    main()
