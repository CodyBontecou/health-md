#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "validate-wear-release-attestation.py"
SPEC = importlib.util.spec_from_file_location("attestation", SCRIPT)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

SHA = "1" * 40
SIGNER = "2" * 64
ATTESTOR = "release-attestor"
BATTERY = "battery-reviewer"
PAIRED = "paired-reviewer"
SCREENSHOT = "screenshot-reviewer"
SOURCE = "source-reviewer"
SOURCE_PULL_REQUEST = 321
SOURCE_REVIEW_ID = 987654
SOURCE_TICKET = f"https://github.com/CodyBontecou/health-md/pull/{SOURCE_PULL_REQUEST}#pullrequestreview-{SOURCE_REVIEW_ID}"


class ReleaseAttestationTest(unittest.TestCase):
    def fixture(self) -> dict:
        manual = {key: True for key in MODULE.MANUAL_BOOLEAN_KEYS}
        manual.update(
            pairedReviewer=PAIRED,
            pairedReviewTicket="PAIR-1",
            batteryReviewer=BATTERY,
            batteryReviewTicket="BAT-1",
            batteryControlProfile="battery-profile-v1",
        )
        return {
            "schemaVersion": 1,
            "releaseSha": SHA,
            "versionName": "9.8.7",
            "phoneVersionCode": 123,
            "wearVersionCode": 1_000_123,
            "attestor": ATTESTOR,
            "playAppSigningCertSha256": SIGNER,
            "manualQa": manual,
            "screenshots": {
                "appApproved": True,
                "tileApproved": True,
                "reviewer": SCREENSHOT,
                "reviewTicket": "SHOT-1",
            },
            "sourceReview": {
                "approved": True,
                "releaseSha": SHA,
                "reviewer": SOURCE,
                "reviewTicket": SOURCE_TICKET,
                "pullRequestNumber": SOURCE_PULL_REQUEST,
                "reviewId": SOURCE_REVIEW_ID,
                "reviewedAtUtc": "2026-08-14T10:00:00Z",
            },
            "approvedAtUtc": "2026-08-14T11:00:00Z",
        }

    def validate(self, path: Path, **overrides: str) -> None:
        values = {
            "attestor": ATTESTOR,
            "battery_reviewer": BATTERY,
            "paired_reviewer": PAIRED,
            "screenshot_reviewer": SCREENSHOT,
            "source_reviewer": SOURCE,
        }
        values.update(overrides)
        MODULE.validate(
            path,
            SHA,
            "9.8.7",
            123,
            1_000_123,
            values["attestor"],
            SIGNER,
            values["battery_reviewer"],
            "BAT-1",
            "battery-profile-v1",
            values["paired_reviewer"],
            "PAIR-1",
            values["screenshot_reviewer"],
            "SHOT-1",
            values["source_reviewer"],
            SOURCE_TICKET,
            SOURCE_PULL_REQUEST,
            SOURCE_REVIEW_ID,
        )

    def write(self, root: Path, data: dict) -> Path:
        path = root / "release-attestation.json"
        path.write_text(json.dumps(data), encoding="utf-8")
        return path

    def test_exact_valid_attestation_passes(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            self.validate(self.write(Path(temp), self.fixture()))

    def test_missing_closed_track_scenario_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            data = self.fixture()
            data["manualQa"]["closedTrackWatchFirstInstallApproved"] = False
            with self.assertRaises(SystemExit):
                self.validate(self.write(Path(temp), data))

    def test_unknown_or_misspelled_field_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            data = self.fixture()
            data["manualQa"]["pixelAproved"] = data["manualQa"].pop("pixelApproved")
            with self.assertRaises(SystemExit):
                self.validate(self.write(Path(temp), data))

    def test_source_review_for_other_sha_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            data = self.fixture()
            data["sourceReview"]["releaseSha"] = "3" * 40
            with self.assertRaises(SystemExit):
                self.validate(self.write(Path(temp), data))

    def test_source_review_for_other_pull_or_review_id_fails(self) -> None:
        for key, value in (("pullRequestNumber", SOURCE_PULL_REQUEST + 1), ("reviewId", SOURCE_REVIEW_ID + 1)):
            with self.subTest(key=key), tempfile.TemporaryDirectory() as temp:
                data = self.fixture()
                data["sourceReview"][key] = value
                with self.assertRaises(SystemExit):
                    self.validate(self.write(Path(temp), data))

    def test_reviewer_equal_to_attestor_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            path = self.write(Path(temp), self.fixture())
            with self.assertRaises(SystemExit):
                self.validate(path, battery_reviewer=ATTESTOR)

    def test_source_review_after_aggregate_approval_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            data = self.fixture()
            data["sourceReview"]["reviewedAtUtc"] = "2026-08-14T12:00:00Z"
            with self.assertRaises(SystemExit):
                self.validate(self.write(Path(temp), data))

    def test_cli_contract_used_by_bundle_verifier(self) -> None:
        # The sealed-bundle verifier invokes this script with exactly this flag set; keep the CLI
        # contract executable so grep-only coverage cannot mask missing required arguments.
        with tempfile.TemporaryDirectory() as temp:
            path = self.write(Path(temp), self.fixture())
            base = [
                sys.executable,
                str(SCRIPT),
                str(path),
                "--release-sha",
                SHA,
                "--version-name",
                "9.8.7",
                "--phone-version-code",
                "123",
                "--wear-version-code",
                "1000123",
                "--attestor",
                ATTESTOR,
                "--play-signer",
                SIGNER,
                "--battery-reviewer",
                BATTERY,
                "--battery-ticket",
                "BAT-1",
                "--battery-profile",
                "battery-profile-v1",
                "--paired-reviewer",
                PAIRED,
                "--paired-ticket",
                "PAIR-1",
                "--screenshot-reviewer",
                SCREENSHOT,
                "--screenshot-ticket",
                "SHOT-1",
                "--source-reviewer",
                SOURCE,
                "--source-ticket",
                SOURCE_TICKET,
            ]
            completed = subprocess.run(
                base + ["--source-pull-request-number", str(SOURCE_PULL_REQUEST), "--source-review-id", str(SOURCE_REVIEW_ID)],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
            )
            self.assertEqual(completed.returncode, 0, completed.stdout.decode())
            # The bundle verifier's exact invocation without either required GitHub identity
            # argument must fail, proving the CLI contract cannot silently degrade.
            completed = subprocess.run(base, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            self.assertNotEqual(completed.returncode, 0, completed.stdout.decode())


if __name__ == "__main__":
    unittest.main()
