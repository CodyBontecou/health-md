#!/usr/bin/env python3
"""Fail-closed validator for the retained Pixel/Samsung paired-Wear QA checkpoints."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import re
from pathlib import Path

OEM_MANUFACTURER = {"pixel": "google", "samsung": "samsung"}
CHECKPOINTS = ("installed", "synced", "offline", "reconnected", "cleared", "rebooted", "final")
MAX_SNAPSHOT_BYTES = 64 * 1024
SHA256 = re.compile(r"^[0-9a-f]{64}$")


def fail(message: str) -> None:
    raise SystemExit(f"Wear paired QA evidence: {message}")


def parse_key_values(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.is_file():
        fail(f"missing {path}")
    for line in path.read_text(encoding="utf-8").splitlines():
        if "=" not in line:
            fail(f"invalid metadata line in {path}: {line!r}")
        key, value = line.split("=", 1)
        if not key or key in values:
            fail(f"duplicate/empty metadata key in {path}: {key!r}")
        values[key] = value
    return values


def verify_checksums(directory: Path) -> None:
    sums = directory / "SHA256SUMS"
    if not sums.is_file():
        fail(f"missing {sums}")
    listed: set[str] = set()
    for line in sums.read_text(encoding="utf-8").splitlines():
        try:
            digest, filename = line.split(None, 1)
        except ValueError:
            fail(f"invalid checksum line in {sums}: {line!r}")
        filename = filename.lstrip("*")
        target = directory / filename
        if not SHA256.fullmatch(digest.lower()) or not target.is_file():
            fail(f"invalid checksum target in {sums}: {line!r}")
        try:
            target.resolve().relative_to(directory.resolve())
        except ValueError:
            fail(f"unsafe checksum target in {sums}: {filename}")
        if hashlib.sha256(target.read_bytes()).hexdigest() != digest.lower():
            fail(f"checksum mismatch: {target}")
        listed.add(filename)
    required = {
        "metadata.txt",
        "phone/base.apk",
        "phone/signer.txt",
        "phone/package.txt",
        "phone/services.txt",
        "phone/broadcast-history.txt",
        "phone/connectivity.txt",
        "phone/battery.txt",
        "phone/logcat.txt",
        "watch/base.apk",
        "watch/signer.txt",
        "watch/package.txt",
        "watch/services.txt",
        "watch/broadcast-history.txt",
        "watch/connectivity.txt",
        "watch/battery.txt",
        "watch/logcat.txt",
        "watch/private-state.txt",
    }
    missing = required - listed
    if missing:
        fail(f"{sums} does not cover required files: {sorted(missing)}")
    actual_files = {
        str(path.relative_to(directory))
        for path in directory.rglob("*")
        if path.is_file() and path.name != "SHA256SUMS"
    }
    unlisted = actual_files - listed
    if unlisted:
        fail(f"{sums} omits captured files: {sorted(unlisted)}")


def captured_instant(value: str, path: Path) -> dt.datetime:
    try:
        parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        fail(f"invalid captured_utc in {path}: {value!r}")
    if parsed.tzinfo is None:
        fail(f"captured_utc lacks timezone in {path}")
    return parsed.astimezone(dt.timezone.utc)


def healthmd_crash_or_anr(logcat: str) -> bool:
    patterns = (
        r"ANR in com\.healthmd\.android",
        r"am_anr[^\n]*com\.healthmd\.android",
        r"am_crash[^\n]*com\.healthmd\.android",
        r"FATAL EXCEPTION[^\n]*(?:\n[^\n]*){0,6}\n[^\n]*Process: com\.healthmd\.android",
        r"AndroidRuntime[^\n]*Process: com\.healthmd\.android",
    )
    return any(re.search(pattern, logcat, re.IGNORECASE) for pattern in patterns)


def contract_field_leaked(logcat: str) -> bool:
    normalized = re.sub(
        r"\\u([0-9a-fA-F]{4})",
        lambda match: chr(int(match.group(1), 16)),
        logcat,
    )
    normalized = re.sub(r"[^a-z0-9]+", "", normalized.lower())
    return bool(re.search(
        r"localdate|steps|movekilocalories|exerciseminutes|sleepminutes|"
        r"restingheartratebpm|averageheartratebpm|bloodoxygenpercent|"
        r"hrvrmssdmillis|capturedatepochmillis|capturedzoneid|permissionstate|days",
        normalized,
    ))


def state(path: Path) -> dict[str, str]:
    values = parse_key_values(path)
    for key in ("cache_file_present", "mismatch_marker_present", "clear_tombstone_present", "ordering_corrupt"):
        if values.get(key) not in {"true", "false"}:
            fail(f"{path}: invalid {key}")
    if values["ordering_corrupt"] != "false":
        fail(f"{path}: ordering metadata is corrupt")
    if not values.get("uid", "").isdigit():
        fail(f"{path}: invalid provider uid")
    present = values["cache_file_present"] == "true"
    if present:
        try:
            size = int(values.get("cache_size", ""))
        except ValueError:
            fail(f"{path}: invalid cache_size")
        if size not in range(1, MAX_SNAPSHOT_BYTES + 1) or not SHA256.fullmatch(values.get("cache_sha256", "")):
            fail(f"{path}: cached snapshot lacks valid size/hash")
    elif "cache_size" in values or "cache_sha256" in values:
        fail(f"{path}: absent cache has size/hash")
    return values


def checkpoint(
    root: Path,
    oem: str,
    name: str,
    expected_phone_code: str,
    expected_wear_code: str,
    expected_version_name: str,
    expected_phone_apk: str | None,
    expected_wear_apk: str | None,
    expected_signer: str | None,
) -> dict:
    directory = root / oem / name
    if not directory.is_dir():
        fail(f"missing checkpoint directory: {directory}")
    verify_checksums(directory)
    metadata_path = directory / "metadata.txt"
    metadata = parse_key_values(metadata_path)
    expected = {
        "oem": oem,
        "checkpoint": name,
        "package": "com.healthmd.android",
        "phone_version_code": expected_phone_code,
        "watch_version_code": expected_wear_code,
        "version_name": expected_version_name,
    }
    for key, value in expected.items():
        if metadata.get(key) != value:
            fail(f"{metadata_path}: expected {key}={value!r}, got {metadata.get(key)!r}")
    manufacturer = metadata.get("watch_manufacturer", "").lower()
    if OEM_MANUFACTURER[oem] not in manufacturer:
        fail(f"{metadata_path}: manufacturer {manufacturer!r} does not match {oem}")
    for key in ("reviewer_id", "review_ticket"):
        if not metadata.get(key, "").strip():
            fail(f"{metadata_path}: independent {key} is required")
    for key in (
        "phone_base_apk_sha256",
        "watch_base_apk_sha256",
        "expected_play_app_signing_cert_sha256",
    ):
        if not SHA256.fullmatch(metadata.get(key, "")):
            fail(f"{metadata_path}: invalid {key}")
    if expected_phone_apk is not None and metadata["phone_base_apk_sha256"] != expected_phone_apk:
        fail(f"{metadata_path}: phone APK differs from retained Play-generated artifact")
    if expected_wear_apk is not None and metadata["watch_base_apk_sha256"] != expected_wear_apk:
        fail(f"{metadata_path}: Wear APK differs from retained Play-generated artifact")
    if expected_signer is not None and metadata["expected_play_app_signing_cert_sha256"] != expected_signer:
        fail(f"{metadata_path}: signer differs from protected Play identity")
    for label in ("phone", "watch"):
        apk = directory / label / "base.apk"
        actual = hashlib.sha256(apk.read_bytes()).hexdigest()
        if actual != metadata[f"{label}_base_apk_sha256"]:
            fail(f"{metadata_path}: {label} base APK digest does not match captured bytes")
        signer = directory / label / "signer.txt"
        match = re.search(r"^Signer #1 certificate SHA-256 digest: ([0-9A-Fa-f]{64})$", signer.read_text(encoding="utf-8"), re.MULTILINE)
        if not match or match.group(1).lower() != metadata["expected_play_app_signing_cert_sha256"]:
            fail(f"{signer}: signer does not match authorized Play identity")
        package_path = directory / label / "package.txt"
        package_text = package_path.read_text(encoding="utf-8", errors="replace")
        code_match = re.search(r"\bversionCode=(\d+)\b", package_text)
        name_match = re.search(r"\bversionName=([^\s]+)", package_text)
        expected_code = expected_phone_code if label == "phone" else expected_wear_code
        if (
            not code_match or code_match.group(1) != expected_code
            or not name_match or name_match.group(1) != expected_version_name
        ):
            fail(f"{package_path}: exact {label} package identity is absent")
        logcat_path = directory / label / "logcat.txt"
        logcat = logcat_path.read_text(encoding="utf-8", errors="replace")
        if healthmd_crash_or_anr(logcat):
            fail(f"{logcat_path}: Health.md crash/ANR evidence present")
        if contract_field_leaked(logcat):
            fail(f"{logcat_path}: health aggregate/contract field leaked")
    return {
        "captured": captured_instant(metadata.get("captured_utc", ""), metadata_path),
        "metadata": metadata,
        "state": state(directory / "watch/private-state.txt"),
    }


def verify(
    root: Path,
    expected_phone_apk: str | None = None,
    expected_wear_apk: str | None = None,
    expected_signer: str | None = None,
    expected_phone_code: str | None = None,
    expected_wear_code: str | None = None,
    expected_version_name: str | None = None,
    expected_reviewer: str | None = None,
    expected_review_ticket: str | None = None,
) -> None:
    for label, value in (
        ("phone APK", expected_phone_apk),
        ("Wear APK", expected_wear_apk),
        ("Play signer", expected_signer),
    ):
        if value is not None and not SHA256.fullmatch(value):
            fail(f"expected {label} SHA-256 must be lowercase hex")
    if expected_phone_code is None or expected_wear_code is None or expected_version_name is None:
        fail("expected phone/Wear version codes and semantic version name are required")
    if not expected_phone_code.isdigit() or not expected_wear_code.isdigit():
        fail("expected phone/Wear version codes must be decimal integers")
    if int(expected_phone_code) >= 1_000_000 or int(expected_wear_code) < 1_000_000:
        fail("expected phone/Wear version codes are outside their reserved ranges")
    if not re.fullmatch(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", expected_version_name):
        fail("expected semantic version name is invalid")
    if not expected_reviewer or not expected_review_ticket:
        fail("protected expected paired-QA reviewer and review ticket are required")
    global_reviewer_ticket: tuple[str, str] | None = None
    for oem in OEM_MANUFACTURER:
        points = {
            name: checkpoint(
                root, oem, name, expected_phone_code, expected_wear_code, expected_version_name,
                expected_phone_apk, expected_wear_apk, expected_signer,
            )
            for name in CHECKPOINTS
        }
        timestamps = [points[name]["captured"] for name in CHECKPOINTS]
        if timestamps != sorted(timestamps) or len(set(timestamps)) != len(timestamps):
            fail(f"{oem}: checkpoint timestamps are not strictly ordered")
        invariant_keys = (
            "phone_serial",
            "watch_serial",
            "phone_base_apk_sha256",
            "watch_base_apk_sha256",
            "expected_play_app_signing_cert_sha256",
            "phone_model",
            "watch_model",
            "phone_manufacturer",
            "watch_manufacturer",
            "phone_build",
            "watch_build",
            "reviewer_id",
            "review_ticket",
        )
        for key in invariant_keys:
            values = {points[name]["metadata"].get(key) for name in CHECKPOINTS}
            if len(values) != 1 or None in values or "" in values:
                fail(f"{oem}: {key} differs or is missing across checkpoints")
        point = points["installed"]["metadata"]
        reviewer_ticket = (point["reviewer_id"], point["review_ticket"])
        if global_reviewer_ticket is None:
            global_reviewer_ticket = reviewer_ticket
        elif reviewer_ticket != global_reviewer_ticket:
            fail("paired QA reviewer/ticket differs across OEMs")
        if expected_reviewer is not None and point["reviewer_id"] != expected_reviewer:
            fail(f"{oem}: paired QA reviewer differs from protected expected reviewer")
        if expected_review_ticket is not None and point["review_ticket"] != expected_review_ticket:
            fail(f"{oem}: paired QA ticket differs from protected expected ticket")
        for name in ("synced", "offline", "reconnected", "rebooted", "final"):
            if points[name]["state"]["cache_file_present"] != "true":
                fail(f"{oem}/{name}: expected durable cached snapshot")
        if points["cleared"]["state"]["cache_file_present"] != "false":
            fail(f"{oem}/cleared: health cache is still present")
        if points["cleared"]["state"]["clear_tombstone_present"] != "true":
            fail(f"{oem}/cleared: durable clear barrier is absent")
        for name, point in points.items():
            if point["state"]["mismatch_marker_present"] != "false":
                fail(f"{oem}/{name}: unexpected version-mismatch marker")
        synced_hash = points["synced"]["state"].get("cache_sha256")
        if points["offline"]["state"].get("cache_sha256") != synced_hash:
            fail(f"{oem}/offline: last-good cache changed while disconnected")
        reconnected_hash = points["reconnected"]["state"].get("cache_sha256")
        if reconnected_hash == points["offline"]["state"].get("cache_sha256"):
            fail(f"{oem}/reconnected: no newer durable snapshot was observed after reconnect")
        if points["rebooted"]["state"].get("cache_sha256") != reconnected_hash:
            fail(f"{oem}/rebooted: reconnected cache did not persist across reboot")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("root", type=Path)
    parser.add_argument("--phone-apk-sha256")
    parser.add_argument("--wear-apk-sha256")
    parser.add_argument("--play-signer-sha256")
    parser.add_argument("--phone-version-code", required=True)
    parser.add_argument("--wear-version-code", required=True)
    parser.add_argument("--version-name", required=True)
    parser.add_argument("--expected-reviewer", required=True)
    parser.add_argument("--expected-review-ticket", required=True)
    args = parser.parse_args()
    verify(
        args.root, args.phone_apk_sha256, args.wear_apk_sha256, args.play_signer_sha256,
        args.phone_version_code, args.wear_version_code, args.version_name,
        args.expected_reviewer, args.expected_review_ticket,
    )
    print("Wear paired QA evidence: all Pixel/Samsung checkpoints are internally valid")


if __name__ == "__main__":
    main()
