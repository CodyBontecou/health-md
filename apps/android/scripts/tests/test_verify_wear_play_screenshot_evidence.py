#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "verify-wear-play-screenshot-evidence.py"
spec = importlib.util.spec_from_file_location("wear_screenshot_validator", SCRIPT)
assert spec and spec.loader
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)
_raw_verify = validator.verify


def verify_fixture(*args, **kwargs):
    if len(args) < 5:
        kwargs.setdefault("expected_wear_version_code", "1000029")
    if len(args) < 6:
        kwargs.setdefault("expected_version_name", "1.8.0")
    kwargs.setdefault("expected_reviewer", "release-reviewer")
    kwargs.setdefault("expected_review_ticket", "https://example.invalid/review/123")
    return _raw_verify(*args, **kwargs)


validator.verify = verify_fixture


class WearScreenshotEvidencePolicyTest(unittest.TestCase):
    apk = "a" * 64
    signer = "b" * 64

    def test_dynamic_release_identity_is_required(self) -> None:
        with self.assertRaises(SystemExit):
            _raw_verify(Path("missing-assets"), Path("missing-evidence"), self.apk, self.signer)

    def fixture(self, root: Path) -> tuple[Path, Path]:
        assets = root / "assets"
        evidence = root / "evidence"
        assets.mkdir()
        for kind in ("app", "tile"):
            image = assets / f"wear-{kind}.png"
            image.write_bytes(f"png-{kind}".encode())
            directory = evidence / kind
            directory.mkdir(parents=True)
            receipt = (
                f"captured_utc=2026-08-13T00:00:00Z\nkind={kind}\nwatch_serial=watch\n"
                f"version_code=1000029\nversion_name=1.8.0\nwear_base_apk_sha256={self.apk}\n"
                f"play_app_signing_cert_sha256={self.signer}\n"
                f"image_sha256={hashlib.sha256(image.read_bytes()).hexdigest()}\n"
                "exact_release_ui_confirmed=yes\nno_production_health_values_confirmed=yes\n"
                "reviewer_id=release-reviewer\nreview_ticket=https://example.invalid/review/123\n"
            )
            (directory / "receipt.txt").write_text(receipt)
            (directory / "signer.txt").write_text(
                f"Signer #1 certificate SHA-256 digest: {self.signer}\n"
            )
            (directory / "package.txt").write_text(
                "versionCode=1000029 minSdk=30 targetSdk=35\nversionName=1.8.0\n"
            )
            sums = "".join(
                f"{hashlib.sha256((directory / name).read_bytes()).hexdigest()}  {name}\n"
                for name in ("receipt.txt", "signer.txt", "package.txt")
            )
            (directory / "SHA256SUMS").write_text(sums)
        return assets, evidence

    def test_valid_exact_release_pair_passes(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            assets, evidence = self.fixture(Path(temp))
            validator.verify(assets, evidence, self.apk, self.signer)

    def test_protected_expected_reviewer_and_ticket_are_required(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            assets, evidence = self.fixture(Path(temp))
            with self.assertRaises(SystemExit):
                _raw_verify(
                    assets,
                    evidence,
                    self.apk,
                    self.signer,
                    "1000029",
                    "1.8.0",
                )

    def test_capture_checksum_command_emits_verifier_compatible_basenames(self) -> None:
        capture = SCRIPT.parent / "capture-wear-play-screenshot.sh"
        source = capture.read_text()
        self.assertIn('cd "$evidence"', source)
        self.assertIn("shasum -a 256 receipt.txt signer.txt package.txt >SHA256SUMS", source)
        self.assertNotIn('shasum -a 256 "$evidence/receipt.txt"', source)

        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            (directory / "receipt.txt").write_text("receipt\n")
            (directory / "signer.txt").write_text("signer\n")
            (directory / "package.txt").write_text("package\n")
            subprocess.run(
                ["bash", "-c", "shasum -a 256 receipt.txt signer.txt package.txt >SHA256SUMS"],
                cwd=directory,
                check=True,
            )
            validator.verify_checksums(directory)

    def test_directory_prefixed_checksum_names_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            (directory / "receipt.txt").write_text("receipt\n")
            (directory / "signer.txt").write_text("signer\n")
            (directory / "package.txt").write_text("package\n")
            (directory / "SHA256SUMS").write_text(
                f"{hashlib.sha256((directory / 'receipt.txt').read_bytes()).hexdigest()}  evidence/receipt.txt\n"
                f"{hashlib.sha256((directory / 'signer.txt').read_bytes()).hexdigest()}  evidence/signer.txt\n"
                f"{hashlib.sha256((directory / 'package.txt').read_bytes()).hexdigest()}  evidence/package.txt\n"
            )
            with self.assertRaises(SystemExit):
                validator.verify_checksums(directory)

    def test_dynamic_version_name_is_bound(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            assets, evidence = self.fixture(Path(temp))
            with self.assertRaises(SystemExit):
                validator.verify(assets, evidence, self.apk, self.signer, "1000029", "1.7.2")

    def test_captured_package_identity_is_independently_checked(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            assets, evidence = self.fixture(Path(temp))
            directory = evidence / "app"
            package = directory / "package.txt"
            package.write_text(package.read_text().replace("versionCode=1000029", "versionCode=1000030"))
            (directory / "SHA256SUMS").write_text("".join(
                f"{hashlib.sha256((directory / name).read_bytes()).hexdigest()}  {name}\n"
                for name in ("receipt.txt", "signer.txt", "package.txt")
            ))
            with self.assertRaises(SystemExit):
                validator.verify(assets, evidence, self.apk, self.signer)

    def test_capture_time_is_required_and_parseable(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            assets, evidence = self.fixture(Path(temp))
            directory = evidence / "tile"
            receipt = directory / "receipt.txt"
            receipt.write_text(receipt.read_text().replace(
                "captured_utc=2026-08-13T00:00:00Z",
                "captured_utc=not-a-time",
            ))
            (directory / "SHA256SUMS").write_text("".join(
                f"{hashlib.sha256((directory / name).read_bytes()).hexdigest()}  {name}\n"
                for name in ("receipt.txt", "signer.txt", "package.txt")
            ))
            with self.assertRaises(SystemExit):
                validator.verify(assets, evidence, self.apk, self.signer)

    def test_protected_reviewer_ticket_and_app_tile_consistency_are_bound(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            assets, evidence = self.fixture(Path(temp))
            validator.verify(
                assets,
                evidence,
                self.apk,
                self.signer,
                expected_reviewer="release-reviewer",
                expected_review_ticket="https://example.invalid/review/123",
            )
            with self.assertRaises(SystemExit):
                validator.verify(assets, evidence, self.apk, self.signer, expected_reviewer="other")

            receipt = evidence / "tile/receipt.txt"
            receipt.write_text(receipt.read_text().replace(
                "reviewer_id=release-reviewer",
                "reviewer_id=other-reviewer",
            ))
            directory = receipt.parent
            (directory / "SHA256SUMS").write_text("".join(
                f"{hashlib.sha256((directory / name).read_bytes()).hexdigest()}  {name}\n"
                for name in ("receipt.txt", "signer.txt", "package.txt")
            ))
            with self.assertRaises(SystemExit):
                validator.verify(assets, evidence, self.apk, self.signer)

    def test_substituted_image_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            assets, evidence = self.fixture(Path(temp))
            (assets / "wear-app.png").write_bytes(b"replacement")
            with self.assertRaises(SystemExit):
                validator.verify(assets, evidence, self.apk, self.signer)

    def test_wrong_release_signer_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            assets, evidence = self.fixture(Path(temp))
            with self.assertRaises(SystemExit):
                validator.verify(assets, evidence, self.apk, "c" * 64)

    def test_missing_independent_reviewer_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            assets, evidence = self.fixture(Path(temp))
            receipt = evidence / "app/receipt.txt"
            receipt.write_text(receipt.read_text().replace("reviewer_id=release-reviewer\n", ""))
            directory = receipt.parent
            (directory / "SHA256SUMS").write_text("".join(
                f"{hashlib.sha256((directory / name).read_bytes()).hexdigest()}  {name}\n"
                for name in ("receipt.txt", "signer.txt", "package.txt")
            ))
            with self.assertRaises(SystemExit):
                validator.verify(assets, evidence, self.apk, self.signer)

    def test_missing_visual_attestation_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            assets, evidence = self.fixture(Path(temp))
            receipt = evidence / "tile/receipt.txt"
            receipt.write_text(receipt.read_text().replace("exact_release_ui_confirmed=yes", "exact_release_ui_confirmed=no"))
            directory = receipt.parent
            (directory / "SHA256SUMS").write_text("".join(
                f"{hashlib.sha256((directory / name).read_bytes()).hexdigest()}  {name}\n"
                for name in ("receipt.txt", "signer.txt", "package.txt")
            ))
            with self.assertRaises(SystemExit):
                validator.verify(assets, evidence, self.apk, self.signer)


if __name__ == "__main__":
    unittest.main()
