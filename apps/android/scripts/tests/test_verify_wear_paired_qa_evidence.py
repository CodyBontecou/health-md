#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
import shutil
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "verify-wear-paired-qa-evidence.py"
spec = importlib.util.spec_from_file_location("wear_paired_validator", SCRIPT)
assert spec and spec.loader
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)
_raw_verify = validator.verify


def verify_fixture(*args, **kwargs):
    kwargs.setdefault("expected_phone_code", "29")
    kwargs.setdefault("expected_wear_code", "1000029")
    kwargs.setdefault("expected_version_name", "1.7.1")
    kwargs.setdefault("expected_reviewer", "physical-qa-reviewer")
    kwargs.setdefault("expected_review_ticket", "https://example.invalid/qa/123")
    return _raw_verify(*args, **kwargs)


validator.verify = verify_fixture


class WearPairedEvidenceValidatorTest(unittest.TestCase):
    def test_dynamic_release_identity_is_required(self) -> None:
        with self.assertRaises(SystemExit):
            _raw_verify(Path("missing"))

    def create_checkpoint(
        self,
        root: Path,
        oem: str,
        checkpoint: str,
        minute: int,
        cache: bool,
        tombstone: bool,
        wear_digest: str = "b" * 64,
        cache_digest: str = "c" * 64,
    ) -> None:
        directory = root / oem / checkpoint
        if directory.exists():
            shutil.rmtree(directory)
        (directory / "phone").mkdir(parents=True)
        (directory / "watch").mkdir()
        phone_apk = b"phone-apk"
        wear_apk = b"wear-apk"
        phone_digest = hashlib.sha256(phone_apk).hexdigest()
        actual_wear_digest = hashlib.sha256(wear_apk).hexdigest()
        # This override is used to prove cross-checkpoint artifact continuity; it also changes the
        # captured bytes so the per-checkpoint digest binding remains valid.
        if wear_digest != "b" * 64:
            wear_apk = wear_digest.encode()
            actual_wear_digest = hashlib.sha256(wear_apk).hexdigest()
        signer = "a" * 64
        manufacturer = "Google" if oem == "pixel" else "Samsung"
        metadata = "\n".join(
            (
                f"captured_utc=2026-01-01T00:{minute:02d}:00Z",
                f"oem={oem}",
                f"checkpoint={checkpoint}",
                "package=com.healthmd.android",
                "phone_serial=phone-1",
                f"watch_serial={oem}-watch-1",
                "phone_version_code=29",
                "watch_version_code=1000029",
                "version_name=1.7.1",
                f"phone_base_apk_sha256={phone_digest}",
                f"watch_base_apk_sha256={actual_wear_digest}",
                f"expected_play_app_signing_cert_sha256={signer}",
                "reviewer_id=physical-qa-reviewer",
                "review_ticket=https://example.invalid/qa/123",
                "phone_model=Phone",
                f"watch_model={oem.title()} Watch",
                "phone_manufacturer=Google",
                f"watch_manufacturer={manufacturer}",
                "phone_build=phone/build",
                f"watch_build={oem}/build",
            )
        ) + "\n"
        (directory / "metadata.txt").write_text(metadata)
        (directory / "phone/base.apk").write_bytes(phone_apk)
        (directory / "watch/base.apk").write_bytes(wear_apk)
        signer_text = f"Signer #1 certificate SHA-256 digest: {signer}\n"
        for label in ("phone", "watch"):
            (directory / label / "signer.txt").write_text(signer_text)
            code = "29" if label == "phone" else "1000029"
            (directory / label / "package.txt").write_text(
                f"versionCode={code} minSdk=28 targetSdk=35\nversionName=1.7.1\n"
            )
            for name in ("services.txt", "broadcast-history.txt", "connectivity.txt", "battery.txt"):
                (directory / label / name).write_text(f"{label}-{name}\n")
            (directory / label / "logcat.txt").write_text("ordinary Health.md lifecycle\n")
        state = (
            "uid=123\n"
            f"cache_file_present={'true' if cache else 'false'}\n"
            "mismatch_marker_present=false\n"
            f"clear_tombstone_present={'true' if tombstone else 'false'}\n"
            "ordering_corrupt=false\n"
        )
        if cache:
            state += f"cache_size=10\ncache_sha256={cache_digest}\n"
        (directory / "watch/private-state.txt").write_text(state)
        files = sorted(path for path in directory.rglob("*") if path.is_file())
        sums = "".join(
            f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.relative_to(directory)}\n"
            for path in files
        )
        (directory / "SHA256SUMS").write_text(sums)

    def fixture(self, root: Path) -> None:
        for oem in validator.OEM_MANUFACTURER:
            for minute, checkpoint in enumerate(validator.CHECKPOINTS):
                self.create_checkpoint(
                    root,
                    oem,
                    checkpoint,
                    minute,
                    cache=checkpoint != "cleared" and checkpoint != "installed",
                    tombstone=checkpoint == "cleared",
                    cache_digest=("d" * 64 if checkpoint in {"reconnected", "rebooted", "final"} else "c" * 64),
                )

    def rehash(self, directory: Path) -> None:
        files = sorted(
            path for path in directory.rglob("*")
            if path.is_file() and path.name != "SHA256SUMS"
        )
        (directory / "SHA256SUMS").write_text("".join(
            f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.relative_to(directory)}\n"
            for path in files
        ))

    def test_valid_fixture_passes(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.fixture(root)
            phone = hashlib.sha256(b"phone-apk").hexdigest()
            wear = hashlib.sha256(b"wear-apk").hexdigest()
            validator.verify(root, phone, wear, "a" * 64)

    def test_protected_expected_reviewer_and_ticket_are_required(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.fixture(root)
            with self.assertRaises(SystemExit):
                _raw_verify(
                    root,
                    expected_phone_code="29",
                    expected_wear_code="1000029",
                    expected_version_name="1.7.1",
                )

    def test_retained_play_artifact_or_signer_mismatch_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.fixture(root)
            phone = hashlib.sha256(b"phone-apk").hexdigest()
            wear = hashlib.sha256(b"wear-apk").hexdigest()
            for expected in (
                ("f" * 64, wear, "a" * 64),
                (phone, "f" * 64, "a" * 64),
                (phone, wear, "f" * 64),
            ):
                with self.subTest(expected=expected), self.assertRaises(SystemExit):
                    validator.verify(root, *expected)

    def test_raw_package_identity_is_independently_checked(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.fixture(root)
            directory = root / "pixel/synced"
            package = directory / "watch/package.txt"
            package.write_text(package.read_text().replace("versionCode=1000029", "versionCode=1000030"))
            self.rehash(directory)
            with self.assertRaises(SystemExit):
                validator.verify(root)

    def test_raw_log_privacy_fields_are_normalized_and_rejected(self) -> None:
        fields = (
            "localDate", "steps", "moveKilocalories", "exerciseMinutes", "sleepMinutes",
            "restingHeartRateBpm", "averageHeartRateBpm", "bloodOxygenPercent",
            "hrvRmssdMillis", "capturedAtEpochMillis", "capturedZoneId",
            "permissionState", "days", "STEPS", r"\u0073teps",
        )
        for field in fields:
            with self.subTest(field=field), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                self.fixture(root)
                directory = root / "pixel/synced"
                (directory / "watch/logcat.txt").write_text(f"payload {field}=sensitive\n")
                self.rehash(directory)
                with self.assertRaises(SystemExit):
                    validator.verify(root)

    def test_raw_log_crash_evidence_is_independently_checked(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.fixture(root)
            directory = root / "pixel/synced"
            (directory / "watch/logcat.txt").write_text(
                "FATAL EXCEPTION: main\nProcess: com.healthmd.android, PID: 123\n"
            )
            self.rehash(directory)
            with self.assertRaises(SystemExit):
                validator.verify(root)

    def test_offline_cache_change_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.fixture(root)
            self.create_checkpoint(root, "pixel", "offline", 2, cache=True, tombstone=False, cache_digest="e" * 64)
            with self.assertRaises(SystemExit):
                validator.verify(root)

    def test_reconnect_without_new_snapshot_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.fixture(root)
            self.create_checkpoint(root, "pixel", "reconnected", 3, cache=True, tombstone=False, cache_digest="c" * 64)
            with self.assertRaises(SystemExit):
                validator.verify(root)

    def test_checksum_tamper_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.fixture(root)
            (root / "pixel/synced/watch/private-state.txt").write_text("tampered\n")
            with self.assertRaises(SystemExit):
                validator.verify(root)

    def test_clear_with_cache_fails_even_with_recomputed_checksums(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.fixture(root)
            self.create_checkpoint(root, "pixel", "cleared", 4, cache=True, tombstone=True)
            with self.assertRaises(SystemExit):
                validator.verify(root)

    def test_dynamic_version_name_is_bound(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.fixture(root)
            with self.assertRaises(SystemExit):
                validator.verify(
                    root,
                    expected_phone_code="29",
                    expected_wear_code="1000029",
                    expected_version_name="1.7.2",
                )

    def test_protected_reviewer_ticket_and_cross_oem_consistency_are_bound(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.fixture(root)
            validator.verify(
                root,
                expected_reviewer="physical-qa-reviewer",
                expected_review_ticket="https://example.invalid/qa/123",
            )
            with self.assertRaises(SystemExit):
                validator.verify(root, expected_reviewer="other-reviewer")

            for checkpoint in validator.CHECKPOINTS:
                directory = root / "samsung" / checkpoint
                metadata = directory / "metadata.txt"
                metadata.write_text(metadata.read_text().replace(
                    "reviewer_id=physical-qa-reviewer",
                    "reviewer_id=other-reviewer",
                ))
                files = sorted(path for path in directory.rglob("*") if path.is_file() and path.name != "SHA256SUMS")
                (directory / "SHA256SUMS").write_text("".join(
                    f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.relative_to(directory)}\n"
                    for path in files
                ))
            with self.assertRaises(SystemExit):
                validator.verify(root)

    def test_artifact_swap_between_checkpoints_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.fixture(root)
            self.create_checkpoint(root, "samsung", "final", 6, cache=True, tombstone=False, wear_digest="changed")
            with self.assertRaises(SystemExit):
                validator.verify(root)


if __name__ == "__main__":
    unittest.main()
