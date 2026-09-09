#!/usr/bin/env python3
"""Tests for selecting a stable, SDK-compatible iOS simulator."""

from __future__ import annotations

import sys
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

    def test_runtime_identifier_parser_is_bounded(self) -> None:
        self.assertEqual(
            runtime_version("com.apple.CoreSimulator.SimRuntime.iOS-26-5-1"),
            (26, 5, 1),
        )
        self.assertIsNone(runtime_version("com.apple.CoreSimulator.SimRuntime.watchOS-26-5"))


if __name__ == "__main__":
    unittest.main()
