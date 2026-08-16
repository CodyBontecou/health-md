#!/usr/bin/env python3
from __future__ import annotations

import datetime as dt
import hashlib
import importlib.util
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "verify-wear-battery-evidence.py"
spec = importlib.util.spec_from_file_location("wear_battery_validator", SCRIPT)
assert spec and spec.loader
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)
_raw_verify = validator.verify


def verify_fixture(*args, **kwargs):
    kwargs.setdefault("expected_version_code", "1000029")
    kwargs.setdefault("expected_version_name", "1.7.1")
    kwargs.setdefault("expected_reviewer", "reviewer@example.test")
    kwargs.setdefault("expected_review_ticket", "QA-1234")
    kwargs.setdefault("expected_control_profile", "wear-battery-profile-v1")
    return _raw_verify(*args, **kwargs)


validator.verify = verify_fixture

APK = "a" * 64
SIGNER = "b" * 64
FILES = {
    "signer.txt": f"Signer #1 certificate SHA-256 digest: {SIGNER}\n",
    "battery.txt": (
        "Current Battery Service state:\n AC powered: false\n USB powered: false\n"
        " Wireless powered: false\n Dock powered: false\n status: 3\n level: 90\n scale: 100\n"
    ),
    "features.txt": "feature:android.hardware.type.watch\nfeature:android.hardware.bluetooth\n",
    "display.txt": (
        "--- dumpsys window displays ---\nDisplayInfo{flags=FLAG_ROUND} mIsRound=true\n"
        "--- wm size ---\nPhysical size: 450x450\n--- wm density ---\nPhysical density: 320\n"
    ),
    "batterystats-checkin.txt": "9,0,i,vers,34\n",
    "batterystats.txt": "Estimated power use\n",
    "power.txt": "Wake Locks: size=0\nSuspend Blockers: size=0\n",
    "alarm.txt": "Alarm Stats\n",
    "jobscheduler.txt": "JOB CONTROLLER STATE\n",
    "package.txt": "versionCode=1000029 minSdk=30 targetSdk=35\nversionName=1.7.1\n",
    "logcat.txt": "08-13 00:00:00 I HealthMd: ordinary lifecycle\n",
}


class WearBatteryEvidencePolicyTest(unittest.TestCase):
    def test_dynamic_release_identity_is_required(self) -> None:
        with self.assertRaises(SystemExit):
            _raw_verify(Path("missing"), APK, SIGNER)

    def test_exact_play_artifact_and_signer_are_required(self) -> None:
        common = {
            "expected_version_code": "1000029",
            "expected_version_name": "1.7.1",
            "expected_reviewer": "reviewer@example.test",
            "expected_review_ticket": "QA-1234",
            "expected_control_profile": "wear-battery-profile-v1",
        }
        with self.assertRaises(SystemExit):
            _raw_verify(Path("missing"), None, SIGNER, **common)
        with self.assertRaises(SystemExit):
            _raw_verify(Path("missing"), APK, None, **common)

    def test_protected_expected_reviewer_ticket_and_profile_are_required(self) -> None:
        with self.assertRaises(SystemExit):
            _raw_verify(
                Path("missing"),
                APK,
                SIGNER,
                expected_version_code="1000029",
                expected_version_name="1.7.1",
            )

    def test_history_accepts_changing_headers_and_appended_records(self) -> None:
        start = "Battery History (old header):\n  +0ms 100 status=discharging\n"
        end = "Battery History (rewritten header):\n  summary=changed\n  +0ms 100 status=discharging\n  +1h screen\n"
        self.assertFalse(validator.history_indicates_charging(start, end))

    def test_history_rejects_mid_interval_plug_even_when_endpoint_could_be_lower(self) -> None:
        self.assertTrue(validator.history_indicates_charging(
            "+0ms status=discharging\n",
            "+0ms status=discharging\n+1h +plugged\n+2h -plugged\n",
        ))

    def test_history_rejects_oem_charging_status(self) -> None:
        self.assertTrue(validator.history_indicates_charging(
            "+0ms status=discharging\n",
            "+0ms status=discharging\n+1h plug=wireless status=charging\n",
        ))

    def test_history_rejects_inserted_record_before_final_start_record(self) -> None:
        with self.assertRaises(SystemExit):
            validator.history_indicates_charging(
                "+0ms status=discharging\n+2h screen\n",
                "+0ms status=discharging\n+1h +plugged\n+2h screen\n",
            )

    def test_history_reset_fails_closed(self) -> None:
        with self.assertRaises(SystemExit):
            validator.history_indicates_charging(
                "+0ms old cumulative history\n",
                "+0ms new reset history\n",
            )

    def test_history_without_stable_records_fails_closed(self) -> None:
        with self.assertRaises(SystemExit):
            validator.history_indicates_charging("mutable header only\n", "another header\n")

    def test_healthmd_wakelock_and_scoped_crash_detection(self) -> None:
        self.assertTrue(validator.active_healthmd_wakelock(
            "Wake Locks: size=1\nPARTIAL_WAKE_LOCK 'com.healthmd.android:sync'\nSuspend Blockers: size=0\n",
            "10234",
        ))
        self.assertTrue(validator.active_healthmd_wakelock(
            "Wake Locks: size=1\nPARTIAL_WAKE_LOCK 'sync' (uid=10234 pid=3)\nSuspend Blockers: size=0\n",
            "10234",
        ))
        self.assertFalse(validator.active_healthmd_wakelock(
            "Wake Locks: size=1\nPARTIAL_WAKE_LOCK 'android' (uid=1000 pid=2)\nSuspend Blockers: size=0\n",
            "10234",
        ))
        self.assertTrue(validator.healthmd_crash_or_anr(
            "FATAL EXCEPTION: main\nProcess: com.healthmd.android, PID: 42\n"
        ))
        self.assertFalse(validator.healthmd_crash_or_anr(
            "FATAL EXCEPTION: main\nProcess: com.other.app, PID: 42\n"
        ))

    def _metadata(
        self,
        device: str,
        scenario: str,
        checkpoint: str,
        captured: dt.datetime,
        level: int,
    ) -> str:
        manufacturer = "Google" if device == "pixel" else "Samsung"
        mode = "baseline" if checkpoint.startswith("baseline-") else "healthmd"
        return "\n".join((
            f"captured_utc={captured.isoformat().replace('+00:00', 'Z')}",
            f"serial={device}-serial",
            f"device={device}",
            f"model_label={device} watch",
            f"scenario={scenario}",
            f"checkpoint={checkpoint}",
            "package=com.healthmd.android",
            "uid=10234",
            "version_code=1000029",
            "version_name=1.7.1",
            f"wear_base_apk_sha256={APK}",
            f"play_app_signing_cert_sha256={SIGNER}",
            "reviewer_id=reviewer@example.test",
            "review_ticket=QA-1234",
            "control_profile_id=wear-battery-profile-v1",
            "controlled_conditions=yes",
            "no_user_refresh=yes",
            "no_wakelock_anr_confirmed=yes",
            f"protocol_mode={mode}",
            f"manufacturer={manufacturer}",
            f"product_model={device}-model",
            f"build_fingerprint={device}/build/1",
            "build_characteristics=watch",
            f"hardware={device}-watch-hardware",
            "ro_kernel_qemu=",
            "ro_boot_qemu=",
            "watch_feature=true",
            "screen_round=true",
            "emulator=false",
            "physical_size=450x450",
            "sdk=35",
            f"battery_level={level}",
            "battery_scale=100",
            "battery_status=3",
            "ac_powered=false",
            "usb_powered=false",
            "wireless_powered=false",
            "dock_powered=false",
            "plugged=0",
            "temperature_tenths_c=300",
            "",
        ))

    def _write_checkpoint(
        self,
        root: Path,
        device: str,
        scenario: str,
        checkpoint: str,
        captured: dt.datetime,
        level: int,
        history_records: list[str],
    ) -> None:
        directory = root / device / scenario / checkpoint
        directory.mkdir(parents=True)
        contents = dict(FILES)
        contents["battery.txt"] = contents["battery.txt"].replace("level: 90", f"level: {level}")
        contents["metadata.txt"] = self._metadata(device, scenario, checkpoint, captured, level)
        contents["batterystats-history.txt"] = "Battery History (mutable header):\n" + "\n".join(history_records) + "\n"
        for name, text in contents.items():
            (directory / name).write_text(text, encoding="utf-8")
        with (directory / "SHA256SUMS").open("w", encoding="utf-8") as handle:
            for name in sorted(contents):
                digest = hashlib.sha256((directory / name).read_bytes()).hexdigest()
                handle.write(f"{digest}  {name}\n")

    def _fixture(self, root: Path) -> None:
        origin = dt.datetime(2026, 8, 1, tzinfo=dt.timezone.utc)
        for device_index, device in enumerate(("pixel", "samsung")):
            for scenario_index, (scenario, hours) in enumerate(validator.MIN_HOURS.items()):
                base = origin + dt.timedelta(days=device_index * 8 + scenario_index * 3)
                records = ["+0ms status=discharging"]
                self._write_checkpoint(root, device, scenario, "baseline-start", base, 90, records)
                records = records + [f"+{int(hours)}h baseline-end"]
                self._write_checkpoint(root, device, scenario, "baseline-end", base + dt.timedelta(hours=hours), 88, records)
                start = base + dt.timedelta(hours=hours + 2)
                records = records + [f"+{int(hours) + 2}h healthmd-start"]
                self._write_checkpoint(root, device, scenario, "healthmd-start", start, 90, records)
                records = records + [f"+{int(hours) * 2 + 2}h healthmd-end"]
                self._write_checkpoint(root, device, scenario, "healthmd-end", start + dt.timedelta(hours=hours), 88, records)

    def test_complete_fixture_is_artifact_bound_and_passes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self._fixture(root)
            report = validator.verify(root, APK, SIGNER)
            self.assertTrue(report["passed"])

    def test_complete_fixture_rejects_version_prefix_and_unlisted_file(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self._fixture(root)
            directory = root / "pixel" / "paired-24h" / "baseline-start"
            package = directory / "package.txt"
            package.write_text(package.read_text().replace("versionCode=1000029", "versionCode=10000290"))
            # Regenerate this checkpoint's checksum so rejection is semantic, not a hash mismatch.
            lines = []
            for name in sorted(FILES | {"metadata.txt": "", "batterystats-history.txt": ""}):
                lines.append(f"{hashlib.sha256((directory / name).read_bytes()).hexdigest()}  {name}\n")
            (directory / "SHA256SUMS").write_text("".join(lines))
            with self.assertRaises(SystemExit):
                validator.verify(root, APK, SIGNER)

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self._fixture(root)
            directory = root / "pixel" / "paired-24h" / "baseline-start"
            (directory / "unlisted.txt").write_text("unexpected\n")
            with self.assertRaises(SystemExit):
                validator.verify(root, APK, SIGNER)

    def test_complete_fixture_rejects_dock_power_health_log_and_global_attestation_drift(self) -> None:
        mutations = (
            (
                "pixel/paired-24h/baseline-start",
                "battery.txt",
                lambda text: text.replace("Dock powered: false", "Dock powered: true"),
            ),
            (
                "pixel/paired-24h/baseline-start",
                "battery.txt",
                lambda text: text + " plugged: 8\n",
            ),
            (
                "pixel/paired-24h/baseline-start",
                "logcat.txt",
                lambda text: text + "steps=8420 restingHeartRateBpm=58\n",
            ),
            (
                "pixel/paired-24h/baseline-start",
                "logcat.txt",
                lambda text: text + "permissionState=PERMISSION_REQUIRED days=[aggregate]\n",
            ),
            (
                "pixel/paired-24h/baseline-start",
                "logcat.txt",
                lambda text: text + '"permission\\u0053tate":"PERMISSION_REQUIRED"\n',
            ),
            (
                "pixel/paired-24h/baseline-start",
                "logcat.txt",
                lambda text: text + "permission_state=PERMISSION_REQUIRED\n",
            ),
            (
                "pixel/paired-24h/baseline-start",
                "metadata.txt",
                lambda text: text.replace("battery_level=90", "battery_level=89"),
            ),
            (
                "pixel/paired-24h/baseline-start",
                "battery.txt",
                lambda text: text.replace("status: 3", "status: 2"),
            ),
            (
                "samsung/disconnected-12h/baseline-start",
                "metadata.txt",
                lambda text: text.replace("control_profile_id=wear-battery-profile-v1", "control_profile_id=other-profile"),
            ),
        )
        for relative, filename, mutate in mutations:
            with self.subTest(filename=filename), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                self._fixture(root)
                directory = root / relative
                path = directory / filename
                path.write_text(mutate(path.read_text()))
                self._resum(directory)
                with self.assertRaises(SystemExit):
                    validator.verify(root, APK, SIGNER)

    def test_missing_physical_identity_fails(self) -> None:
        for key in ("serial", "product_model", "build_fingerprint", "build_characteristics", "hardware"):
            with self.subTest(key=key), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                self._fixture(root)
                for device in ("pixel", "samsung"):
                    for scenario in validator.MIN_HOURS:
                        for checkpoint in validator.CHECKPOINTS:
                            directory = root / device / scenario / checkpoint
                            metadata = directory / "metadata.txt"
                            metadata.write_text("\n".join(
                                line for line in metadata.read_text().splitlines()
                                if not line.startswith(f"{key}=")
                            ) + "\n")
                            self._resum(directory)
                with self.assertRaises(SystemExit):
                    validator.verify(root, APK, SIGNER)

    def test_non_watch_non_round_and_virtual_targets_fail_closed(self) -> None:
        mutations = (
            ("features.txt", lambda text: text.replace("feature:android.hardware.type.watch\n", "")),
            ("display.txt", lambda text: text.replace("FLAG_ROUND", "FLAG_SECURE").replace("mIsRound=true", "mIsRound=false")),
            ("display.txt", lambda text: text.replace("450x450", "1080x2400")),
            ("metadata.txt", lambda text: text.replace("emulator=false", "emulator=true")),
            ("metadata.txt", lambda text: text.replace("hardware=pixel-watch-hardware", "hardware=ranchu")),
            ("metadata.txt", lambda text: text.replace("ro_kernel_qemu=", "ro_kernel_qemu=1")),
            ("metadata.txt", lambda text: text.replace("manufacturer=Google", "manufacturer=NotGoogle")),
        )
        for filename, mutate in mutations:
            with self.subTest(filename=filename), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                self._fixture(root)
                directory = root / "pixel" / "paired-24h" / "baseline-start"
                path = directory / filename
                path.write_text(mutate(path.read_text()))
                self._resum(directory)
                with self.assertRaises(SystemExit):
                    validator.verify(root, APK, SIGNER)

    def test_protected_expected_reviewer_profile_and_ticket_are_bound(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self._fixture(root)
            report = validator.verify(
                root,
                APK,
                SIGNER,
                expected_reviewer="reviewer@example.test",
                expected_control_profile="wear-battery-profile-v1",
                expected_review_ticket="QA-1234",
            )
            self.assertTrue(report["passed"])
            with self.assertRaises(SystemExit):
                validator.verify(
                    root,
                    APK,
                    SIGNER,
                    expected_reviewer="reviewer@example.test",
                    expected_control_profile="wear-battery-profile-v1",
                    expected_review_ticket="OTHER-TICKET",
                )

    def test_complete_fixture_rejects_cross_scenario_device_swap(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self._fixture(root)
            for checkpoint in validator.CHECKPOINTS:
                directory = root / "pixel" / "disconnected-12h" / checkpoint
                metadata = directory / "metadata.txt"
                text = metadata.read_text()
                text = text.replace("serial=pixel-serial", "serial=other-pixel")
                text = text.replace("product_model=pixel-model", "product_model=other-model")
                text = text.replace("build_fingerprint=pixel/build/1", "build_fingerprint=pixel/build/2")
                text = text.replace("uid=10234", "uid=20234")
                metadata.write_text(text)
                self._resum(directory)
            with self.assertRaises(SystemExit):
                validator.verify(root, APK, SIGNER)

    def test_complete_fixture_rejects_wrong_binary_wakelock_and_chronology(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self._fixture(root)
            with self.assertRaises(SystemExit):
                validator.verify(root, "c" * 64, SIGNER)

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self._fixture(root)
            directory = root / "samsung" / "disconnected-12h" / "healthmd-end"
            (directory / "power.txt").write_text(
                "Wake Locks: size=1\nPARTIAL_WAKE_LOCK 'sync' (uid=10234 pid=3)\nSuspend Blockers: size=0\n"
            )
            self._resum(directory)
            with self.assertRaises(SystemExit):
                validator.verify(root, APK, SIGNER)

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self._fixture(root)
            directory = root / "pixel" / "paired-24h" / "healthmd-start"
            metadata = directory / "metadata.txt"
            lines = metadata.read_text().splitlines()
            lines = [
                "captured_utc=2026-08-01T12:00:00Z" if line.startswith("captured_utc=") else line
                for line in lines
            ]
            metadata.write_text("\n".join(lines) + "\n")
            self._resum(directory)
            with self.assertRaises(SystemExit):
                validator.verify(root, APK, SIGNER)

    @staticmethod
    def _resum(directory: Path) -> None:
        names = sorted(path.name for path in directory.iterdir() if path.is_file() and path.name != "SHA256SUMS")
        with (directory / "SHA256SUMS").open("w", encoding="utf-8") as handle:
            for name in names:
                handle.write(f"{hashlib.sha256((directory / name).read_bytes()).hexdigest()}  {name}\n")


if __name__ == "__main__":
    unittest.main()
