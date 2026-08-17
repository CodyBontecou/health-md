#!/usr/bin/env python3
"""Fail-closed validator for the documented Pixel/Samsung Wear battery controls."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import re
from pathlib import Path

CHECKPOINTS = ("baseline-start", "baseline-end", "healthmd-start", "healthmd-end")
MIN_HOURS = {"paired-24h": 24.0, "disconnected-12h": 12.0}
EXPECTED_MANUFACTURER = {"pixel": "google", "samsung": "samsung"}
MAX_INCREMENTAL_DRAIN_PER_24H = 2.0
MAX_START_LEVEL_DIFFERENCE_PERCENT = 5.0
SHA256 = re.compile(r"^[0-9a-f]{64}$")


def fail(message: str) -> None:
    raise SystemExit(f"Wear battery evidence: {message}")


def parse_metadata(path: Path) -> dict[str, str]:
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
        if not SHA256.fullmatch(digest.lower()) or filename in listed:
            fail(f"invalid/duplicate SHA-256 entry in {sums}: {line!r}")
        target = directory / filename
        if not target.is_file() or target.resolve().parent != directory.resolve():
            fail(f"missing or unsafe checksum target: {target}")
        if hashlib.sha256(target.read_bytes()).hexdigest() != digest.lower():
            fail(f"checksum mismatch: {target}")
        listed.add(filename)
    required = {
        "metadata.txt", "signer.txt", "battery.txt", "features.txt", "display.txt",
        "batterystats-checkin.txt", "batterystats.txt", "batterystats-history.txt",
        "power.txt", "alarm.txt", "jobscheduler.txt", "package.txt", "logcat.txt",
    }
    actual = {path.name for path in directory.iterdir() if path.is_file() and path.name != "SHA256SUMS"}
    if listed != required or actual != required:
        fail(
            f"{sums} must cover the exact checkpoint inventory; "
            f"listed={sorted(listed)} actual={sorted(actual)}"
        )
    for filename in required:
        if not (directory / filename).read_bytes():
            fail(f"required evidence file is empty: {directory / filename}")


def instant(value: str, path: Path) -> dt.datetime:
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


def active_healthmd_wakelock(power: str, uid: str) -> bool:
    """Detect a package- or UID-attributed active wake lock in dumpsys power."""
    in_wake_locks = False
    for raw in power.splitlines():
        line = raw.strip()
        if line.startswith("Wake Locks: size="):
            in_wake_locks = True
            continue
        if in_wake_locks and (line.startswith("Suspend Blockers:") or line.endswith(":")):
            in_wake_locks = False
        if in_wake_locks and (
            "com.healthmd.android" in line
            or re.search(rf"\buid[=: ]+{re.escape(uid)}\b", line, re.IGNORECASE)
        ):
            return True
    return False


def checkpoint(
    root: Path,
    device: str,
    scenario: str,
    name: str,
    expected_apk: str | None,
    expected_signer: str | None,
    expected_version_code: str,
    expected_version_name: str,
) -> dict:
    directory = root / device / scenario / name
    if not directory.is_dir():
        fail(f"missing checkpoint directory: {directory}")
    verify_checksums(directory)
    metadata_path = directory / "metadata.txt"
    metadata = parse_metadata(metadata_path)
    for key, expected in (
        ("device", device), ("scenario", scenario), ("checkpoint", name),
        ("package", "com.healthmd.android"),
    ):
        if metadata.get(key) != expected:
            fail(f"{metadata_path}: expected {key}={expected!r}, got {metadata.get(key)!r}")
    manufacturer = metadata.get("manufacturer", "").strip().lower()
    if manufacturer != EXPECTED_MANUFACTURER[device]:
        fail(f"{metadata_path}: manufacturer {manufacturer!r} does not exactly match {device}")
    if metadata.get("plugged") != "0":
        fail(f"{metadata_path}: checkpoint was plugged or charge state is unknown")
    expected_mode = "baseline" if name.startswith("baseline-") else "healthmd"
    for key, expected in (
        ("controlled_conditions", "yes"),
        ("no_user_refresh", "yes"),
        ("no_wakelock_anr_confirmed", "yes"),
        ("protocol_mode", expected_mode),
        ("version_code", expected_version_code),
        ("version_name", expected_version_name),
    ):
        if metadata.get(key) != expected:
            fail(f"{metadata_path}: expected {key}={expected!r}")
    for key in ("reviewer_id", "review_ticket", "control_profile_id"):
        if not metadata.get(key, "").strip():
            fail(f"{metadata_path}: independent {key} is required")

    apk_sha = metadata.get("wear_base_apk_sha256", "")
    signer_sha = metadata.get("play_app_signing_cert_sha256", "")
    if not SHA256.fullmatch(apk_sha) or not SHA256.fullmatch(signer_sha):
        fail(f"{metadata_path}: invalid exact APK/signer binding")
    if expected_apk is not None and apk_sha != expected_apk:
        fail(f"{metadata_path}: Wear APK differs from retained Play-generated artifact")
    if expected_signer is not None and signer_sha != expected_signer:
        fail(f"{metadata_path}: signer differs from protected Play identity")
    signer_text = (directory / "signer.txt").read_text(encoding="utf-8", errors="replace")
    signer_match = re.search(
        r"^Signer #1 certificate SHA-256 digest: ([0-9A-Fa-f]{64})$",
        signer_text,
        re.MULTILINE,
    )
    if not signer_match or signer_match.group(1).lower() != signer_sha:
        fail(f"{directory}/signer.txt: signer output differs from metadata")

    package_text = (directory / "package.txt").read_text(encoding="utf-8", errors="replace")
    code_match = re.search(r"\bversionCode=(\d+)\b", package_text)
    name_match = re.search(r"\bversionName=([^\s]+)", package_text)
    if (
        not code_match or code_match.group(1) != expected_version_code
        or not name_match or name_match.group(1) != expected_version_name
    ):
        fail(f"{directory}/package.txt: exact Wear version identity is absent")

    if not metadata.get("uid", "").isdigit():
        fail(f"{metadata_path}: package UID is invalid")
    for key in ("serial", "product_model", "build_fingerprint", "build_characteristics", "hardware"):
        if not metadata.get(key, "").strip():
            fail(f"{metadata_path}: {key} is required for physical identity binding")
    if metadata.get("watch_feature") != "true" or metadata.get("screen_round") != "true":
        fail(f"{metadata_path}: evidence is not explicitly bound to a round Wear OS watch")
    if metadata.get("emulator") != "false":
        fail(f"{metadata_path}: emulator/virtual-device evidence is forbidden")
    if "watch" not in {value.strip().lower() for value in metadata["build_characteristics"].split(",")}:
        fail(f"{metadata_path}: build characteristics do not identify a watch")
    qemu_values = (metadata.get("ro_kernel_qemu", "").lower(), metadata.get("ro_boot_qemu", "").lower())
    if any(value in {"1", "true"} for value in qemu_values):
        fail(f"{metadata_path}: qemu properties identify a virtual device")
    virtual_identity = "\n".join((metadata["hardware"], metadata["build_fingerprint"], metadata["product_model"]))
    if re.search(r"(^|[/ _.-])(goldfish|ranchu|cuttlefish|vsoc|emulator|sdk_gphone)([/ _.-]|$)", virtual_identity, re.IGNORECASE):
        fail(f"{metadata_path}: hardware/build identity identifies a virtual device")

    features = (directory / "features.txt").read_text(encoding="utf-8", errors="replace")
    if "feature:android.hardware.type.watch" not in features.splitlines():
        fail(f"{directory}/features.txt: watch hardware feature is absent")
    display = (directory / "display.txt").read_text(encoding="utf-8", errors="replace")
    if not re.search(
        r"(^|[^A-Za-z0-9_])(mIsRound|isRound)[=: ]+true([^A-Za-z0-9_]|$)|FLAG_ROUND|screenRound[=: ]+(true|yes|round)",
        display,
        re.IGNORECASE,
    ):
        fail(f"{directory}/display.txt: explicit round-display evidence is absent")
    size_match = re.search(r"Physical size:\s*([1-9][0-9]*)x([1-9][0-9]*)", display)
    if not size_match:
        fail(f"{directory}/display.txt: physical display size is absent")
    width, height = map(int, size_match.groups())
    physical_size = f"{width}x{height}"
    if metadata.get("physical_size") != physical_size:
        fail(f"{metadata_path}: physical display size differs from raw display evidence")
    if abs(width - height) > max(20, int(max(width, height) * 0.05)):
        fail(f"{directory}/display.txt: display is not a qualifying round-watch framebuffer")

    raw_battery = (directory / "battery.txt").read_text(encoding="utf-8", errors="replace")
    raw_level = re.search(r"^\s*level:\s*(\d+)\s*$", raw_battery, re.MULTILINE)
    raw_scale = re.search(r"^\s*scale:\s*(\d+)\s*$", raw_battery, re.MULTILINE)
    raw_status = re.search(r"^\s*status:\s*(\d+)\s*$", raw_battery, re.MULTILINE)
    if not raw_level or not raw_scale or not raw_status:
        fail(f"{directory}/battery.txt: raw level/scale/status are incomplete")
    if (
        metadata.get("battery_level") != raw_level.group(1)
        or metadata.get("battery_scale") != raw_scale.group(1)
        or metadata.get("battery_status") != raw_status.group(1)
    ):
        fail(f"{metadata_path}: battery level/scale/status differ from raw battery state")
    if raw_status.group(1) in {"2", "5"}:
        fail(f"{directory}/battery.txt: raw battery status reports charging/full")
    powered = {
        key.lower(): value
        for key, value in re.findall(
            r"^\s*(AC|USB|Wireless|Dock) powered:\s*(true|false)\s*$",
            raw_battery,
            re.MULTILINE,
        )
    }
    legacy_plug = re.search(r"^\s*plugged:\s*(\d+)\s*$", raw_battery, re.MULTILINE)
    if {"ac", "usb", "wireless"}.issubset(powered):
        powered.setdefault("dock", "false")
        for key in ("ac", "usb", "wireless", "dock"):
            if metadata.get(f"{key}_powered") != powered[key]:
                fail(f"{metadata_path}: {key} power metadata differs from raw battery state")
        if any(value == "true" for value in powered.values()):
            fail(f"{directory}/battery.txt: raw battery state reports an external power source")
        # Some OEM/API variants retain the numeric bitmask alongside boolean fields. Treat either
        # representation as independently authoritative so contradictory raw evidence fails closed.
        if legacy_plug and legacy_plug.group(1) != "0":
            fail(f"{directory}/battery.txt: raw plugged bitmask contradicts powered fields")
    elif legacy_plug:
        if legacy_plug.group(1) != "0":
            fail(f"{directory}/battery.txt: legacy raw battery state reports plugged")
    else:
        fail(f"{directory}/battery.txt: cannot determine raw charging connection")

    logcat = (directory / "logcat.txt").read_text(encoding="utf-8", errors="replace")
    normalized_logcat = re.sub(
        r"\\u([0-9a-fA-F]{4})",
        lambda match: chr(int(match.group(1), 16)),
        logcat,
    )
    normalized_logcat = re.sub(r"[^a-z0-9]+", "", normalized_logcat.lower())
    if healthmd_crash_or_anr(logcat):
        fail(f"{directory}/logcat.txt: Health.md crash/ANR evidence present")
    if re.search(
        r"localdate|steps|movekilocalories|exerciseminutes|sleepminutes|restingheartratebpm|"
        r"averageheartratebpm|bloodoxygenpercent|hrvrmssdmillis|capturedatepochmillis|"
        r"capturedzoneid|permissionstate|days",
        normalized_logcat,
    ):
        fail(f"{directory}/logcat.txt: health aggregate/contract field leaked")
    power = (directory / "power.txt").read_text(encoding="utf-8", errors="replace")
    if active_healthmd_wakelock(power, metadata.get("uid", "")):
        fail(f"{directory}/power.txt: Health.md wake lock was active at capture")

    try:
        level = int(metadata["battery_level"])
        scale = int(metadata["battery_scale"])
    except (KeyError, ValueError):
        fail(f"{metadata_path}: invalid battery level/scale")
    if scale <= 0 or level not in range(scale + 1):
        fail(f"{metadata_path}: battery level {level}/{scale} is invalid")
    return {
        "directory": str(directory),
        "captured": instant(metadata.get("captured_utc", ""), metadata_path),
        "level": level,
        "scale": scale,
        "serial": metadata.get("serial"),
        "model": metadata.get("product_model"),
        "build": metadata.get("build_fingerprint"),
        "characteristics": metadata.get("build_characteristics"),
        "hardware": metadata.get("hardware"),
        "physicalSize": physical_size,
        "uid": metadata.get("uid"),
        "reviewer": metadata.get("reviewer_id"),
        "reviewTicket": metadata.get("review_ticket"),
        "controlProfile": metadata.get("control_profile_id"),
        "apkSha256": apk_sha,
        "signerSha256": signer_sha,
        "history": (directory / "batterystats-history.txt").read_text(encoding="utf-8", errors="replace"),
    }


def history_records(report: str) -> list[str]:
    """Extract stable event records while ignoring mutable dumpsys headers/summary text."""
    records: list[str] = []
    for raw in report.splitlines():
        line = raw.strip()
        if line.startswith("+") or (line and line[0].isdigit() and "(" in line[:20]):
            records.append(line)
    return records


def history_indicates_charging(start_history: str, end_history: str) -> bool:
    """Reject reset/interleaving and detect charging records appended during the interval."""
    start = history_records(start_history)
    end = history_records(end_history)
    if not start or not end:
        fail("batterystats history contains no recognizable stable event records")
    # Stable cumulative history is expected to append. Treat interleaving, duplicate ambiguity,
    # reset, or truncation as invalid so a charging event cannot be inserted before the final
    # retained start record and evade the interval delta.
    if len(end) < len(start) or end[:len(start)] != start:
        fail("batterystats history reset, truncated, interleaved, or lost a prior event record")
    delta = "\n".join(end[len(start):]).lower()
    charging_tokens = (
        "+plugged", "plug=ac", "plug=usb", "plug=wireless", "status=charging",
        " status=2", "charging=true", "+charging",
    )
    return any(token in delta for token in charging_tokens)


def interval(start: dict, end: dict, label: str, minimum_hours: float) -> dict:
    for key in (
        "serial", "model", "build", "characteristics", "hardware", "physicalSize",
        "uid", "scale", "reviewer", "reviewTicket", "controlProfile", "apkSha256",
        "signerSha256",
    ):
        if start[key] != end[key]:
            fail(f"{label}: {key} changed between checkpoints")
    elapsed_hours = (end["captured"] - start["captured"]).total_seconds() / 3600.0
    if elapsed_hours < minimum_hours:
        fail(f"{label}: duration {elapsed_hours:.2f}h is below required {minimum_hours:.2f}h")
    if end["level"] > start["level"]:
        fail(f"{label}: battery level increased, indicating an uncontrolled charge")
    if history_indicates_charging(start["history"], end["history"]):
        fail(f"{label}: batterystats history records charging during the interval")
    drain_percent = (start["level"] - end["level"]) * 100.0 / start["scale"]
    return {
        "elapsedHours": round(elapsed_hours, 4),
        "drainPercent": round(drain_percent, 4),
        "normalizedDrainPercentPer24h": round(drain_percent * 24.0 / elapsed_hours, 4),
    }


def verify(
    root: Path,
    expected_apk: str | None = None,
    expected_signer: str | None = None,
    expected_version_code: str | None = None,
    expected_version_name: str | None = None,
    expected_reviewer: str | None = None,
    expected_control_profile: str | None = None,
    expected_review_ticket: str | None = None,
) -> dict:
    if expected_apk is None or not SHA256.fullmatch(expected_apk):
        fail("expected Wear APK SHA-256 is required and must be lowercase hex")
    if expected_signer is None or not SHA256.fullmatch(expected_signer):
        fail("expected Play signer SHA-256 is required and must be lowercase hex")
    if expected_version_code is None or expected_version_name is None:
        fail("expected Wear version code/name are required")
    if not expected_version_code.isdigit() or not re.fullmatch(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", expected_version_name):
        fail("expected Wear version code/name are invalid")
    if not expected_reviewer or not expected_review_ticket or not expected_control_profile:
        fail("protected expected battery reviewer, review ticket, and control profile are required")
    results: dict[str, dict] = {}
    global_reviewer: str | None = None
    global_ticket: str | None = None
    global_profile: str | None = None
    device_identity: dict[str, tuple] = {}
    for device in ("pixel", "samsung"):
        results[device] = {}
        for scenario, minimum_hours in MIN_HOURS.items():
            points = {
                name: checkpoint(
                    root, device, scenario, name, expected_apk, expected_signer,
                    expected_version_code, expected_version_name,
                )
                for name in CHECKPOINTS
            }
            identity = {
                (
                    point["serial"], point["model"], point["build"], point["characteristics"],
                    point["hardware"], point["physicalSize"], point["uid"], point["scale"],
                    point["reviewer"], point["reviewTicket"], point["controlProfile"],
                    point["apkSha256"], point["signerSha256"],
                )
                for point in points.values()
            }
            if len(identity) != 1:
                fail(f"{device}/{scenario}: identity/build/artifact/reviewer/control profile differs across controls")
            point = points["baseline-start"]
            scenario_device_identity = (
                point["serial"], point["model"], point["build"], point["characteristics"],
                point["hardware"], point["physicalSize"], point["uid"], point["scale"],
                point["apkSha256"], point["signerSha256"],
            )
            prior_device_identity = device_identity.setdefault(device, scenario_device_identity)
            if scenario_device_identity != prior_device_identity:
                fail(f"{device}: physical watch identity/build/artifact differs across scenarios")
            if global_reviewer is None:
                global_reviewer, global_ticket, global_profile = (
                    point["reviewer"], point["reviewTicket"], point["controlProfile"]
                )
            if (point["reviewer"], point["reviewTicket"], point["controlProfile"]) != (
                global_reviewer, global_ticket, global_profile
            ):
                fail("reviewer/ticket/control profile differs across OEM/scenario controls")
            if expected_reviewer is not None and point["reviewer"] != expected_reviewer:
                fail("battery reviewer differs from protected expected reviewer")
            if expected_control_profile is not None and point["controlProfile"] != expected_control_profile:
                fail("battery control profile differs from protected expected profile")
            if expected_review_ticket is not None and point["reviewTicket"] != expected_review_ticket:
                fail("battery review ticket differs from protected expected ticket")
            chronology = [points[name]["captured"] for name in CHECKPOINTS]
            if chronology != sorted(chronology) or len(set(chronology)) != len(chronology):
                fail(f"{device}/{scenario}: baseline and Health.md checkpoints are not strictly ordered")
            baseline_start = points["baseline-start"]["level"] * 100.0 / points["baseline-start"]["scale"]
            healthmd_start = points["healthmd-start"]["level"] * 100.0 / points["healthmd-start"]["scale"]
            if abs(baseline_start - healthmd_start) > MAX_START_LEVEL_DIFFERENCE_PERCENT:
                fail(
                    f"{device}/{scenario}: baseline and Health.md starting charge differ by more than "
                    f"{MAX_START_LEVEL_DIFFERENCE_PERCENT:.1f}%"
                )
            baseline = interval(
                points["baseline-start"], points["baseline-end"],
                f"{device}/{scenario}/baseline", minimum_hours,
            )
            healthmd = interval(
                points["healthmd-start"], points["healthmd-end"],
                f"{device}/{scenario}/healthmd", minimum_hours,
            )
            incremental = max(
                0.0,
                healthmd["normalizedDrainPercentPer24h"]
                - baseline["normalizedDrainPercentPer24h"],
            )
            if incremental > MAX_INCREMENTAL_DRAIN_PER_24H:
                fail(
                    f"{device}/{scenario}: incremental normalized drain {incremental:.4f}%/24h "
                    f"exceeds {MAX_INCREMENTAL_DRAIN_PER_24H:.1f}%/24h"
                )
            results[device][scenario] = {
                "baseline": baseline,
                "healthmd": healthmd,
                "incrementalDrainPercentPer24h": round(incremental, 4),
                "thresholdPercentPer24h": MAX_INCREMENTAL_DRAIN_PER_24H,
                "passed": True,
            }
    return {
        "schemaVersion": 1,
        "verifiedAtUtc": dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z"),
        "results": results,
        "passed": True,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("root", type=Path)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--wear-apk-sha256", required=True)
    parser.add_argument("--play-signer-sha256", required=True)
    parser.add_argument("--wear-version-code", required=True)
    parser.add_argument("--version-name", required=True)
    parser.add_argument("--expected-reviewer", required=True)
    parser.add_argument("--expected-control-profile", required=True)
    parser.add_argument("--expected-review-ticket", required=True)
    args = parser.parse_args()
    report = verify(
        args.root, args.wear_apk_sha256, args.play_signer_sha256,
        args.wear_version_code, args.version_name,
        args.expected_reviewer, args.expected_control_profile, args.expected_review_ticket,
    )
    text = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(text, encoding="utf-8")
    print(text, end="")


if __name__ == "__main__":
    main()
