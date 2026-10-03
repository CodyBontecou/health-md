#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "verify-wear-play-screenshot-upload-evidence.py"
SPEC = importlib.util.spec_from_file_location("screenshot_upload", SCRIPT)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

WEAR_APK = "a" * 64
SIGNER = "b" * 64
REVIEWER = "reviewer@example.test"
TICKET = "REVIEW-123"


class ScreenshotUploadEvidenceTest(unittest.TestCase):
    def make_fixture(self, root: Path) -> tuple[Path, Path]:
        assets = root / "assets"
        evidence = root / "evidence"
        assets.mkdir()
        evidence.mkdir()
        (assets / "wear-app.png").write_bytes(b"approved app framebuffer")
        (assets / "wear-tile.png").write_bytes(b"approved tile framebuffer")
        app_sha = hashlib.sha256((assets / "wear-app.png").read_bytes()).hexdigest()
        tile_sha = hashlib.sha256((assets / "wear-tile.png").read_bytes()).hexdigest()
        receipt = {
            "schemaVersion": 1,
            "package": "com.healthmd.android",
            "versionName": "9.8.7",
            "phoneVersionCode": 123,
            "wearVersionCode": 1000123,
            "wearApkSha256": WEAR_APK,
            "playAppSigningCertSha256": SIGNER,
            "language": "en-US",
            "imageType": "wearScreenshots",
            "reviewer": REVIEWER,
            "reviewTicket": TICKET,
            "playEditId": "edit-1",
            "commitResponseReceived": True,
            "preCommitAlreadyMatched": False,
            "committed": True,
            "committedAtUtc": "2026-08-14T10:11:12Z",
            "images": [
                {"fileName": "wear-app.png", "sha256": app_sha},
                {"fileName": "wear-tile.png", "sha256": tile_sha},
            ],
        }
        listing = {"images": [{"sha256": tile_sha.upper()}, {"sha256": app_sha}]}
        (evidence / "receipt.json").write_text(json.dumps(receipt))
        (evidence / "pre-commit-listing.json").write_text(json.dumps({"images": []}))
        (evidence / "remote-listing.json").write_text(json.dumps(listing))
        (evidence / "commit-response.json").write_text(json.dumps({
            "editId": "edit-1",
            "responseReceived": True,
            "preCommitAlreadyMatched": False,
            "commitExitCode": 0,
            "reconciledAgainstCommittedListing": True,
            "response": {"id": "edit-1"},
        }))
        with (evidence / "SHA256SUMS").open("w") as sums:
            for name in ("commit-response.json", "pre-commit-listing.json", "receipt.json", "remote-listing.json"):
                digest = hashlib.sha256((evidence / name).read_bytes()).hexdigest()
                sums.write(f"{digest}  {name}\n")
        return evidence, assets

    def verify(self, evidence: Path, assets: Path) -> None:
        MODULE.verify(evidence, assets, WEAR_APK, SIGNER, "9.8.7", 123, 1000123, REVIEWER, TICKET)

    def reseal(self, evidence: Path) -> None:
        with (evidence / "SHA256SUMS").open("w") as sums:
            for name in ("commit-response.json", "pre-commit-listing.json", "receipt.json", "remote-listing.json"):
                digest = hashlib.sha256((evidence / name).read_bytes()).hexdigest()
                sums.write(f"{digest}  {name}\n")

    def test_valid_committed_receipt_passes(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            evidence, assets = self.make_fixture(Path(temp))
            self.verify(evidence, assets)

    def test_reconciled_lost_commit_response_passes(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            evidence, assets = self.make_fixture(Path(temp))
            receipt = json.loads((evidence / "receipt.json").read_text())
            receipt["commitResponseReceived"] = False
            (evidence / "receipt.json").write_text(json.dumps(receipt))
            commit = json.loads((evidence / "commit-response.json").read_text())
            commit["responseReceived"] = False
            commit["commitExitCode"] = 56
            commit["response"] = None
            (evidence / "commit-response.json").write_text(json.dumps(commit))
            self.reseal(evidence)
            self.verify(evidence, assets)

    def test_ambiguous_response_cannot_reuse_already_matching_precommit_state(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            evidence, assets = self.make_fixture(Path(temp))
            receipt = json.loads((evidence / "receipt.json").read_text())
            receipt["commitResponseReceived"] = False
            receipt["preCommitAlreadyMatched"] = True
            (evidence / "receipt.json").write_text(json.dumps(receipt))
            commit = json.loads((evidence / "commit-response.json").read_text())
            commit.update({
                "responseReceived": False,
                "preCommitAlreadyMatched": True,
                "commitExitCode": 56,
                "response": None,
            })
            (evidence / "commit-response.json").write_text(json.dumps(commit))
            committed = json.loads((evidence / "remote-listing.json").read_text())
            (evidence / "pre-commit-listing.json").write_text(json.dumps(committed))
            self.reseal(evidence)
            with self.assertRaises(SystemExit):
                self.verify(evidence, assets)

    def test_definite_http_rejection_cannot_be_reconciled(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            evidence, assets = self.make_fixture(Path(temp))
            receipt = json.loads((evidence / "receipt.json").read_text())
            receipt["commitResponseReceived"] = False
            (evidence / "receipt.json").write_text(json.dumps(receipt))
            commit = json.loads((evidence / "commit-response.json").read_text())
            commit.update({"responseReceived": False, "commitExitCode": 22, "response": None})
            (evidence / "commit-response.json").write_text(json.dumps(commit))
            self.reseal(evidence)
            with self.assertRaises(SystemExit):
                self.verify(evidence, assets)

    def test_different_protected_reviewer_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            evidence, assets = self.make_fixture(Path(temp))
            with self.assertRaises(SystemExit):
                MODULE.verify(evidence, assets, WEAR_APK, SIGNER, "9.8.7", 123, 1000123, "other", TICKET)

    def test_remote_hash_substitution_fails_even_if_resealed(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            evidence, assets = self.make_fixture(Path(temp))
            (evidence / "remote-listing.json").write_text(json.dumps({"images": [{"sha256": "c" * 64}, {"sha256": "d" * 64}]}))
            self.reseal(evidence)
            with self.assertRaises(SystemExit):
                self.verify(evidence, assets)

    def test_different_generated_wear_apk_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            evidence, assets = self.make_fixture(Path(temp))
            with self.assertRaises(SystemExit):
                MODULE.verify(evidence, assets, "c" * 64, SIGNER, "9.8.7", 123, 1000123, REVIEWER, TICKET)

    def test_commit_response_edit_id_mismatch_fails_even_if_resealed(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            evidence, assets = self.make_fixture(Path(temp))
            commit = json.loads((evidence / "commit-response.json").read_text())
            commit["editId"] = "different-edit"
            (evidence / "commit-response.json").write_text(json.dumps(commit))
            self.reseal(evidence)
            with self.assertRaises(SystemExit):
                self.verify(evidence, assets)

    def test_extra_file_or_incomplete_checksum_inventory_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            evidence, assets = self.make_fixture(Path(temp))
            (evidence / "unexpected.txt").write_text("extra")
            with self.assertRaises(SystemExit):
                self.verify(evidence, assets)


if __name__ == "__main__":
    unittest.main()
