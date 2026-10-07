#!/usr/bin/env python3
"""Tests for selecting a stable, SDK-compatible iOS simulator."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPTS_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS_DIR))

from select_ios_simulator import runtime_version, select_device  # noqa: E402


class SelectIOSSimulatorTests(unittest.TestCase):
    @staticmethod
    def payload(*runtimes: tuple[str, list[dict[str, object]]]) -> dict[str, object]:
        return {"devices": {identifier: devices for identifier, devices in runtimes}}

    def test_chooses_newest_runtime_supported_by_active_sdk(self) -> None:
        payload = self.payload(
            (
                "com.apple.CoreSimulator.SimRuntime.iOS-26-2",
                [{"name": "iPhone 17 Pro", "udid": "OLD", "isAvailable": True}],
            ),
            (
                "com.apple.CoreSimulator.SimRuntime.iOS-26-5",
                [{"name": "iPhone 16", "udid": "CURRENT", "isAvailable": True}],
            ),
            (
                "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
                [{"name": "iPhone 17 Pro", "udid": "BETA", "isAvailable": True}],
            ),
        )

        self.assertEqual(
            select_device(payload, "26.6"),
            ("iPhone 16", "CURRENT", (26, 5, 0)),
        )

    def test_prefers_newer_phone_model_within_selected_runtime(self) -> None:
        payload = self.payload(
            (
                "com.apple.CoreSimulator.SimRuntime.iOS-26-5",
                [
                    {"name": "iPhone 15", "udid": "FIFTEEN", "isAvailable": True},
                    {"name": "iPhone 17", "udid": "SEVENTEEN", "isAvailable": True},
                    {"name": "iPhone 17 Pro", "udid": "PRO", "isAvailable": True},
                ],
            ),
        )

        self.assertEqual(select_device(payload, "26.6")[1], "PRO")

    def test_falls_back_to_any_available_iphone(self) -> None:
        payload = self.payload(
            (
                "com.apple.CoreSimulator.SimRuntime.iOS-26-5",
                [
                    {"name": "iPad Air", "udid": "IPAD", "isAvailable": True},
                    {"name": "iPhone SE", "udid": "SE", "isAvailable": True},
                ],
            ),
        )

        self.assertEqual(select_device(payload, "26.6")[1], "SE")

    def test_rejects_unavailable_or_incompatible_devices(self) -> None:
        payload = self.payload(
            (
                "com.apple.CoreSimulator.SimRuntime.iOS-26-5",
                [{"name": "iPhone 17 Pro", "udid": "GONE", "isAvailable": False}],
            ),
            (
                "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
                [{"name": "iPhone 17 Pro", "udid": "BETA", "isAvailable": True}],
            ),
        )

        with self.assertRaisesRegex(ValueError, "no available iPhone simulator"):
            select_device(payload, "26.6")

    def test_ipad_uses_newest_compatible_runtime_instead_of_first_listed(self) -> None:
        payload = self.payload(
            (
                "com.apple.CoreSimulator.SimRuntime.iOS-26-2",
                [{"name": "iPad Pro 13-inch (M5)", "udid": "OLD", "isAvailable": True}],
            ),
            (
                "com.apple.CoreSimulator.SimRuntime.iOS-26-5",
                [
                    {"name": "iPhone 17 Pro", "udid": "PHONE", "isAvailable": True},
                    {"name": "iPad Air 11-inch (M3)", "udid": "CURRENT", "isAvailable": True},
                    {"name": "iPad Pro", "udid": "UNAVAILABLE", "isAvailable": False},
                ],
            ),
            (
                "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
                [{"name": "iPad Pro", "udid": "BETA", "isAvailable": True}],
            ),
        )

        self.assertEqual(
            select_device(payload, "26.6", device_family="iPad"),
            ("iPad Air 11-inch (M3)", "CURRENT", (26, 5, 0)),
        )
        self.assertEqual(select_device(payload, "26.6")[1], "PHONE")

    def test_ipad_does_not_fall_back_to_phone_or_unsupported_runtime(self) -> None:
        payload = self.payload(
            (
                "com.apple.CoreSimulator.SimRuntime.iOS-26-5",
                [
                    {"name": "iPhone 17 Pro", "udid": "PHONE", "isAvailable": True},
                    {"name": "iPad Air", "udid": "GONE", "isAvailable": False},
                ],
            ),
            (
                "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
                [{"name": "iPad Pro", "udid": "BETA", "isAvailable": True}],
            ),
        )

        with self.assertRaisesRegex(ValueError, "no available iPad simulator"):
            select_device(payload, "26.6", device_family="iPad")

    def test_shell_wrapper_forwards_ipad_family_and_keeps_phone_default(self) -> None:
        payload = self.payload(
            (
                "com.apple.CoreSimulator.SimRuntime.iOS-26-2",
                [{"name": "iPad Pro", "udid": "OLD", "isAvailable": True}],
            ),
            (
                "com.apple.CoreSimulator.SimRuntime.iOS-26-5",
                [
                    {"name": "iPhone 17 Pro", "udid": "PHONE", "isAvailable": True},
                    {"name": "iPad Air", "udid": "IPAD", "isAvailable": True},
                ],
            ),
        )
        responses = {
            ("--sdk", "iphonesimulator", "--show-sdk-version"): "26.6",
            ("simctl", "list", "devices", "available", "-j"): json.dumps(payload),
        }
        for arguments, expected in (([], "PHONE"), (["--device-family", "iPad"], "IPAD")):
            with self.subTest(arguments=arguments):
                result, calls = self.run_wrapper(responses, arguments)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), f"platform=iOS Simulator,id={expected}")
                self.assertEqual(len(calls), 2)

    @staticmethod
    def run_wrapper(
        responses: dict[tuple[str, ...], str], arguments: list[str]
    ) -> tuple[subprocess.CompletedProcess[str], list[list[str]]]:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "responses.json").write_text(json.dumps({json.dumps(k): v for k, v in responses.items()}))
            xcrun = root / "xcrun"
            xcrun.write_text(
                "#!/usr/bin/env python3\n"
                "import json, sys\nfrom pathlib import Path\n"
                "root = Path(__file__).parent\n"
                "with (root / 'calls.jsonl').open('a') as calls:\n"
                "    calls.write(json.dumps(sys.argv[1:]) + '\\n')\n"
                "responses = json.loads((root / 'responses.json').read_text())\n"
                "key = json.dumps(sys.argv[1:])\n"
                "if key not in responses:\n"
                "    raise SystemExit('unexpected xcrun invocation: ' + key)\n"
                "print(responses[key])\n"
            )
            xcrun.chmod(0o755)
            result = subprocess.run(
                ["bash", str(SCRIPTS_DIR / "select-ios-simulator.sh"), *arguments],
                env=dict(os.environ, PATH=f"{directory}:{os.environ['PATH']}"),
                capture_output=True,
                text=True,
                check=False,
            )
            calls = [json.loads(line) for line in (root / "calls.jsonl").read_text().splitlines()]
            return result, calls

    @staticmethod
    def ci_responses() -> dict[tuple[str, ...], str]:
        return {
            ("--sdk", "iphonesimulator", "--show-sdk-version"): "26.6",
            ("simctl", "list", "devices", "available", "-j"): json.dumps({"devices": {
                "com.apple.CoreSimulator.SimRuntime.iOS-26-2": [
                    {"name": "iPad Pro", "udid": "OLD", "isAvailable": True}],
                "com.apple.CoreSimulator.SimRuntime.iOS-26-5": [
                    {"name": "iPhone 17 Pro", "udid": "PHONE", "isAvailable": True},
                    {"name": "iPad Pro", "udid": "UNAVAILABLE", "isAvailable": False}],
                "com.apple.CoreSimulator.SimRuntime.iOS-27-0": [
                    {"name": "iPad Pro", "udid": "BETA", "isAvailable": True}],
            }}),
            ("simctl", "list", "runtimes", "available", "-j"): json.dumps({"runtimes": [
                {"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-2", "isAvailable": True},
                {"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-5", "isAvailable": True,
                 "supportedDeviceTypes": [
                     {"name": "iPhone 17 Pro", "productFamily": "iPhone", "identifier": "PHONE-TYPE"},
                     {"name": "iPad Pro", "productFamily": "iPad", "identifier": "CURRENT-IPAD-TYPE"}]},
                {"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-6", "isAvailable": False},
                {"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-27-0", "isAvailable": True,
                 "supportedDeviceTypes": [
                     {"name": "iPad Pro", "productFamily": "iPad", "identifier": "BETA-TYPE"}]},
            ]}),
            ("simctl", "create", "iPad HealthMd CI", "CURRENT-IPAD-TYPE",
             "com.apple.CoreSimulator.SimRuntime.iOS-26-5"): "A1111111-1111-4111-8111-111111111111",
        }

    def test_ci_creates_supported_ipad_on_current_runtime_when_only_old_ipad_exists(self) -> None:
        result, calls = self.run_wrapper(self.ci_responses(), ["--device-family", "iPad", "--create-missing"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "platform=iOS Simulator,id=A1111111-1111-4111-8111-111111111111")
        self.assertEqual(calls[-1], ["simctl", "create", "iPad HealthMd CI", "CURRENT-IPAD-TYPE",
                                    "com.apple.CoreSimulator.SimRuntime.iOS-26-5"])
        self.assertEqual(len(calls), 4)

    def test_ci_reuses_current_ipad_without_creation(self) -> None:
        responses = self.ci_responses()
        devices_key = ("simctl", "list", "devices", "available", "-j")
        payload = json.loads(responses[devices_key])
        payload["devices"]["com.apple.CoreSimulator.SimRuntime.iOS-26-5"].append(
            {"name": "iPad Air", "udid": "CURRENT", "isAvailable": True})
        responses[devices_key] = json.dumps(payload)
        result, calls = self.run_wrapper(responses, ["--device-family", "iPad", "--create-missing"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "platform=iOS Simulator,id=CURRENT")
        self.assertEqual(len(calls), 3)

    def test_ci_does_not_create_on_beta_or_use_unsupported_device_type(self) -> None:
        runtime_key = ("simctl", "list", "runtimes", "available", "-j")
        for scenario in ("beta-only", "no-supported-ipad", "creation-fails", "invalid-created-id"):
            with self.subTest(scenario=scenario):
                responses = self.ci_responses()
                runtimes = json.loads(responses[runtime_key])
                if scenario == "beta-only":
                    runtimes["runtimes"] = [runtimes["runtimes"][-1]]
                elif scenario == "no-supported-ipad":
                    runtimes["runtimes"][1]["supportedDeviceTypes"] = [
                        {"name": "iPhone", "productFamily": "iPhone", "identifier": "PHONE-TYPE"}]
                elif scenario == "creation-fails":
                    del responses[("simctl", "create", "iPad HealthMd CI", "CURRENT-IPAD-TYPE",
                                   "com.apple.CoreSimulator.SimRuntime.iOS-26-5")]
                else:
                    responses[("simctl", "create", "iPad HealthMd CI", "CURRENT-IPAD-TYPE",
                               "com.apple.CoreSimulator.SimRuntime.iOS-26-5")] = "invalid-udid"
                responses[runtime_key] = json.dumps(runtimes)
                result, calls = self.run_wrapper(responses, ["--device-family", "iPad", "--create-missing"])
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")
                if scenario in ("beta-only", "no-supported-ipad"):
                    self.assertFalse(any(call[:2] == ["simctl", "create"] for call in calls))
                expected_error = {
                    "beta-only": "no available iOS runtime",
                    "no-supported-ipad": "no supported iPad device types",
                    "creation-fails": "returned non-zero exit status",
                    "invalid-created-id": "badly formed hexadecimal UUID string",
                }[scenario]
                self.assertIn(expected_error, result.stderr)

    def test_create_missing_requires_explicit_ipad_family(self) -> None:
        result, calls = self.run_wrapper(self.ci_responses(), ["--create-missing"])
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertFalse(any(call[:2] == ["simctl", "create"] for call in calls))
        self.assertIn("--create-missing requires --device-family iPad", result.stderr)

    def test_runtime_identifier_parser_is_bounded(self) -> None:
        self.assertEqual(
            runtime_version("com.apple.CoreSimulator.SimRuntime.iOS-26-5-1"),
            (26, 5, 1),
        )
        self.assertIsNone(runtime_version("com.apple.CoreSimulator.SimRuntime.watchOS-26-5"))


if __name__ == "__main__":
    unittest.main()
