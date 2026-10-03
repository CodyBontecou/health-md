#!/usr/bin/env python3
"""SDK-free Watch governance checks; not Kotlin runtime or physical-device QA."""

import hashlib
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
WATCH_ID = "export.watch-origin-manual-api"
REGISTRY_SHA256 = "56def644baa3d81e0c6c2eda3733bfdd7ceee6554ca9ec609da80356c6578c99"


class WatchCapabilityGovernanceTests(unittest.TestCase):
    def setUp(self):
        self.inventory = json.loads((ROOT / "packages/contracts/product-capabilities.json").read_text())
        rows = [row for row in self.inventory["capabilities"] if row["id"] == WATCH_ID]
        self.assertEqual(len(rows), 1)
        self.watch = rows[0]

    def test_apple_is_planned_pending_physical_network_and_receiver_qualification(self):
        self.assertEqual(self.watch["classification"], "planned")
        self.assertEqual(self.watch["platforms"]["apple"], {
            "state": "planned",
            "target": "Qualify the healthmd.watch_snapshot v1 source path with physical Watch Wi-Fi/cellular uploads while the iPhone is unavailable, interruption/authorization checks, and backend account-bound idempotency receipts before release.",
        })
        self.assertIn("apps/apple/docs/features/watch-api-sync.md", self.watch["evidence"])

    def test_android_is_planned_for_local_capture_not_phone_snapshot_parity(self):
        self.assertEqual(self.watch["platforms"]["android"], {
            "state": "planned",
            "target": "Wear OS watch-origin API export milestone: add reviewed local Health Services capture, secure destination setup, direct HTTPS delivery and retry; preserve the current phone-authoritative Wear snapshot and keep non-equivalent exercise/sensor statistics distinct.",
        })
        self.assertIn("apps/android/docs/features/wear-os.md", self.watch["evidence"])

    def test_watch_has_no_daily_profile_or_frozen_registry_authority(self):
        self.assertEqual(self.watch["profiles"], [])
        self.assertEqual({row["id"] for row in self.inventory["output_profiles"]}, {
            "apple-v8", "android-frozen-v4", "android-analytical-v5",
        })
        registry_bytes = (ROOT / "packages/healthmd-core-rust/crates/healthmd-core/registry/metric-registry-v1.json").read_bytes()
        self.assertEqual(hashlib.sha256(registry_bytes).hexdigest(), REGISTRY_SHA256)
        self.assertNotIn(WATCH_ID, json.loads(registry_bytes)["known_capability_ids"])
        for projection in (
            "apps/apple/HealthMd/Shared/Models/HealthMetrics.swift",
            "apps/android/app/src/main/java/com/healthmd/domain/model/MetricSelection.kt",
        ):
            self.assertIn(REGISTRY_SHA256, (ROOT / projection).read_text(), projection)

    def test_snapshot_contract_stays_deferred_with_original_mirrored_bytes(self):
        manifest = json.loads((ROOT / "packages/contracts/manifest.json").read_text())
        contracts = [row for row in manifest["contracts"] if row["id"] == "healthmd.watch_snapshot"]
        self.assertEqual(len(contracts), 1)
        self.assertEqual((contracts[0]["version"], contracts[0]["status"]), (1, "deferred"))
        fixture = ROOT / "packages/contracts/watch-snapshot/v1/fixtures/watch-snapshot-v1.json"
        mirror = ROOT / "apps/apple/Packages/HealthMdWatchExport/Tests/HealthMdWatchExportTests/Fixtures/watch-snapshot-v1.json"
        self.assertEqual(fixture.read_bytes(), mirror.read_bytes())
        self.assertEqual(hashlib.sha256(fixture.read_bytes()).hexdigest(),
                         "4c08ecfe86c686c039e894a88c3080d0aba34148b86b07cf3e55546a8a284a4d")


if __name__ == "__main__":
    unittest.main(verbosity=2)
