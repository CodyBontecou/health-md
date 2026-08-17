#!/usr/bin/env python3
"""Validate the unsigned Wear release attestation against protected release identities."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
from pathlib import Path

SHA40 = re.compile(r"^[0-9a-f]{40}$")
SHA64 = re.compile(r"^[0-9a-f]{64}$")
SEMVER = re.compile(r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")

TOP_LEVEL_KEYS = {
    "schemaVersion",
    "releaseSha",
    "versionName",
    "phoneVersionCode",
    "wearVersionCode",
    "attestor",
    "playAppSigningCertSha256",
    "manualQa",
    "screenshots",
    "sourceReview",
    "approvedAtUtc",
}
MANUAL_BOOLEAN_KEYS = {
    "pixelApproved",
    "samsungApproved",
    "talkBackApproved",
    "rotaryApproved",
    "rtlLargeFontApproved",
    "allSurfacesApproved",
    "dataLayerRoundTripApproved",
    "clearReconnectRebootApproved",
    "closedTrackPhoneFirstInstallApproved",
    "closedTrackWatchFirstInstallApproved",
    "closedTrackUpgradeFromProductionApproved",
    "closedTrackVersionSkewApproved",
    "closedTrackDeleteUninstallReinstallApproved",
    "batteryConditionsControlled",
    "noUserRefreshDuringBatteryRuns",
}
MANUAL_STRING_KEYS = {
    "pairedReviewer",
    "pairedReviewTicket",
    "batteryReviewer",
    "batteryReviewTicket",
    "batteryControlProfile",
}
SCREENSHOT_KEYS = {"appApproved", "tileApproved", "reviewer", "reviewTicket"}
SOURCE_KEYS = {
    "approved",
    "releaseSha",
    "reviewer",
    "reviewTicket",
    "pullRequestNumber",
    "reviewId",
    "reviewedAtUtc",
}


def fail(message: str) -> None:
    raise SystemExit(f"Wear release attestation: {message}")


def object_with_exact_keys(value: object, expected: set[str], label: str) -> dict[str, object]:
    if not isinstance(value, dict):
        fail(f"{label} must be a JSON object")
    keys = set(value)
    if keys != expected:
        fail(f"{label} keys differ; missing={sorted(expected - keys)}, extra={sorted(keys - expected)}")
    return value


def required_string(value: object, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        fail(f"{label} must be a nonempty string")
    return value


def utc_instant(value: object, label: str) -> dt.datetime:
    text = required_string(value, label)
    if not text.endswith("Z"):
        fail(f"{label} must end in Z")
    try:
        parsed = dt.datetime.fromisoformat(text.removesuffix("Z") + "+00:00")
    except ValueError:
        fail(f"{label} is not an ISO-8601 UTC instant")
    return parsed


def validate(
    path: Path,
    release_sha: str,
    version_name: str,
    phone_version_code: int,
    wear_version_code: int,
    attestor: str,
    play_signer: str,
    battery_reviewer: str,
    battery_ticket: str,
    battery_profile: str,
    paired_reviewer: str,
    paired_ticket: str,
    screenshot_reviewer: str,
    screenshot_ticket: str,
    source_reviewer: str,
    source_ticket: str,
    source_pull_request_number: int,
    source_review_id: int,
) -> None:
    if not path.is_file():
        fail(f"missing {path}")
    if not SHA40.fullmatch(release_sha) or not SEMVER.fullmatch(version_name):
        fail("expected release SHA/version is invalid")
    if phone_version_code < 1 or phone_version_code >= 1_000_000:
        fail("expected phone version code is outside the phone range")
    if wear_version_code < 1_000_000:
        fail("expected Wear version code is outside the Wear range")
    if not SHA64.fullmatch(play_signer):
        fail("expected Play signer must be lowercase SHA-256")
    protected = {
        "attestor": attestor,
        "battery reviewer": battery_reviewer,
        "battery ticket": battery_ticket,
        "battery profile": battery_profile,
        "paired reviewer": paired_reviewer,
        "paired ticket": paired_ticket,
        "screenshot reviewer": screenshot_reviewer,
        "screenshot ticket": screenshot_ticket,
        "source reviewer": source_reviewer,
        "source ticket": source_ticket,
    }
    for label, value in protected.items():
        required_string(value, f"protected {label}")
    for reviewer in (battery_reviewer, paired_reviewer, screenshot_reviewer, source_reviewer):
        if reviewer == attestor:
            fail("manual reviewers must differ from release attestor")
    if source_pull_request_number < 1 or source_review_id < 1:
        fail("protected source pull request number and review ID must be positive")

    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        fail(f"invalid JSON: {error}")
    root = object_with_exact_keys(data, TOP_LEVEL_KEYS, "root")
    expected_root = {
        "schemaVersion": 1,
        "releaseSha": release_sha,
        "versionName": version_name,
        "phoneVersionCode": phone_version_code,
        "wearVersionCode": wear_version_code,
        "attestor": attestor,
        "playAppSigningCertSha256": play_signer,
    }
    for key, expected in expected_root.items():
        if root.get(key) != expected:
            fail(f"root.{key} differs from protected expected value")
    approved_at = utc_instant(root.get("approvedAtUtc"), "root.approvedAtUtc")

    manual = object_with_exact_keys(root.get("manualQa"), MANUAL_BOOLEAN_KEYS | MANUAL_STRING_KEYS, "manualQa")
    for key in MANUAL_BOOLEAN_KEYS:
        if manual.get(key) is not True:
            fail(f"manualQa.{key} must be true")
    expected_manual = {
        "pairedReviewer": paired_reviewer,
        "pairedReviewTicket": paired_ticket,
        "batteryReviewer": battery_reviewer,
        "batteryReviewTicket": battery_ticket,
        "batteryControlProfile": battery_profile,
    }
    for key, expected in expected_manual.items():
        if manual.get(key) != expected:
            fail(f"manualQa.{key} differs from protected expected value")

    screenshots = object_with_exact_keys(root.get("screenshots"), SCREENSHOT_KEYS, "screenshots")
    if screenshots.get("appApproved") is not True or screenshots.get("tileApproved") is not True:
        fail("both screenshot approvals must be true")
    if screenshots.get("reviewer") != screenshot_reviewer or screenshots.get("reviewTicket") != screenshot_ticket:
        fail("screenshot reviewer/ticket differs from protected expected value")

    source = object_with_exact_keys(root.get("sourceReview"), SOURCE_KEYS, "sourceReview")
    if source.get("approved") is not True or source.get("releaseSha") != release_sha:
        fail("source review is not approved for the exact release SHA")
    if source.get("reviewer") != source_reviewer or source.get("reviewTicket") != source_ticket:
        fail("source reviewer/ticket differs from protected expected value")
    if source.get("pullRequestNumber") != source_pull_request_number or source.get("reviewId") != source_review_id:
        fail("source pull request number/review ID differs from protected GitHub proof")
    reviewed_at = utc_instant(source.get("reviewedAtUtc"), "sourceReview.reviewedAtUtc")
    if reviewed_at > approved_at:
        fail("source review occurs after the aggregate release approval")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--release-sha", required=True)
    parser.add_argument("--version-name", required=True)
    parser.add_argument("--phone-version-code", required=True, type=int)
    parser.add_argument("--wear-version-code", required=True, type=int)
    parser.add_argument("--attestor", required=True)
    parser.add_argument("--play-signer", required=True)
    parser.add_argument("--battery-reviewer", required=True)
    parser.add_argument("--battery-ticket", required=True)
    parser.add_argument("--battery-profile", required=True)
    parser.add_argument("--paired-reviewer", required=True)
    parser.add_argument("--paired-ticket", required=True)
    parser.add_argument("--screenshot-reviewer", required=True)
    parser.add_argument("--screenshot-ticket", required=True)
    parser.add_argument("--source-reviewer", required=True)
    parser.add_argument("--source-ticket", required=True)
    parser.add_argument("--source-pull-request-number", required=True, type=int)
    parser.add_argument("--source-review-id", required=True, type=int)
    args = parser.parse_args()
    validate(
        args.manifest,
        args.release_sha,
        args.version_name,
        args.phone_version_code,
        args.wear_version_code,
        args.attestor,
        args.play_signer,
        args.battery_reviewer,
        args.battery_ticket,
        args.battery_profile,
        args.paired_reviewer,
        args.paired_ticket,
        args.screenshot_reviewer,
        args.screenshot_ticket,
        args.source_reviewer,
        args.source_ticket,
        args.source_pull_request_number,
        args.source_review_id,
    )
    print("Wear release attestation: exact protected schema and approvals are valid")


if __name__ == "__main__":
    main()
