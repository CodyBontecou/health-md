#!/usr/bin/env python3
"""Keep registry-v1 authority and immutable differential fixtures stable."""

import contextlib
import io
import sys
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "native_registry_import", Path(__file__).with_name("import-native-registry.py")
)
importer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(importer)
IMPORTER = importer
SCRIPT = Path(__file__).with_name("import-native-registry.py")


class RegistryCapabilityScopeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.apple = importer.parse_apple()
        cls.android = importer.parse_android()
        cls.manifest = json.loads(importer.CAPABILITY_MANIFEST.read_text())
        cls.committed = json.loads(importer.REGISTRY_PATH.read_text())

    def build(self, manifest):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "capabilities.json"
            path.write_text(json.dumps(manifest))
            with patch.object(importer, "CAPABILITY_MANIFEST", path):
                return importer.build_registry(self.apple, self.android)

    def test_current_inventory_preserves_exact_registry_v1_bytes_and_pin(self):
        rebuilt = importer.canonical_bytes(self.build(self.manifest))
        self.assertEqual(importer.REGISTRY_PATH.read_bytes(), rebuilt)
        self.assertEqual(
            "56def644baa3d81e0c6c2eda3733bfdd7ceee6554ca9ec609da80356c6578c99",
            hashlib.sha256(rebuilt).hexdigest(),
        )

    def test_unrelated_new_product_capability_does_not_change_metric_authority(self):
        manifest = copy.deepcopy(self.manifest)
        additional = copy.deepcopy(manifest["capabilities"][0])
        additional["id"] = "direct.synthetic_future_transport"
        manifest["capabilities"].insert(0, additional)
        self.assertEqual(self.committed, self.build(manifest))

    def test_missing_versioned_capability_is_rejected(self):
        manifest = copy.deepcopy(self.manifest)
        manifest["capabilities"] = [
            item for item in manifest["capabilities"] if item["id"] != "export.activity-basics"
        ]
        with self.assertRaisesRegex(ValueError, "capabilit"):
            self.build(manifest)

    def test_new_metric_capability_requires_explicit_registry_review(self):
        with patch.object(importer, "metric_capability", return_value="direct.synthetic_future_transport"):
            with self.assertRaisesRegex(ValueError, "reviewed registry revision"):
                self.build(self.manifest)

    def test_duplicate_product_capability_is_rejected(self):
        manifest = copy.deepcopy(self.manifest)
        manifest["capabilities"].append(copy.deepcopy(manifest["capabilities"][0]))
        with self.assertRaisesRegex(ValueError, "duplicate product capability"):
            self.build(manifest)

    def test_expanding_committed_inventory_requires_reviewed_registry_revision(self):
        manifest = copy.deepcopy(self.manifest)
        additional = copy.deepcopy(manifest["capabilities"][0])
        additional["id"] = "direct.synthetic_future_transport"
        manifest["capabilities"].append(additional)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "capabilities.json"
            path.write_text(json.dumps(manifest))
            known = self.committed["known_capability_ids"] + [additional["id"]]
            with patch.object(importer, "CAPABILITY_MANIFEST", path):
                with self.assertRaisesRegex(ValueError, "reviewed registry revision"):
                    importer.build_registry(self.apple, self.android, known)

    def test_existing_metric_availability_still_comes_from_live_governance(self):
        manifest = copy.deepcopy(self.manifest)
        activity = next(item for item in manifest["capabilities"] if item["id"] == "export.activity-basics")
        activity["platforms"]["android"]["state"] = "unavailable"
        rebuilt = self.build(manifest)
        self.assertNotIn(
            "export.activity-basics", rebuilt["available_capability_ids_by_platform"]["android"]
        )
        self.assertIn("export.activity-basics", rebuilt["known_capability_ids"])


class NativeRegistryImportTest(unittest.TestCase):
    def setUp(self) -> None:
        self.registry = json.loads(IMPORTER.REGISTRY_PATH.read_text())
        self.capabilities = json.loads(IMPORTER.CAPABILITY_MANIFEST.read_text())
        self.apple = IMPORTER.APPLE_BASELINE.read_bytes()
        self.android = IMPORTER.ANDROID_BASELINE.read_bytes()

    def run_import(self, *, check: bool = True) -> bytes:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            registry = root / "metric-registry-v1.json"
            apple = root / "native-baseline-apple-v7.json"
            android = root / "native-baseline-android-v4-v5.json"
            capabilities = root / "product-capabilities.json"
            baseline = root / "native-baseline-capabilities-v1.json"
            baseline.write_bytes(IMPORTER.CAPABILITY_BASELINE.read_bytes())
            registry.write_bytes(IMPORTER.canonical_bytes(self.registry))
            apple.write_bytes(self.apple)
            android.write_bytes(self.android)
            capabilities.write_bytes(IMPORTER.canonical_bytes(self.capabilities))
            with (
                patch.multiple(
                    IMPORTER,
                    REPO=root,
                    REGISTRY_DIR=root,
                    REGISTRY_PATH=registry,
                    APPLE_BASELINE=apple,
                    ANDROID_BASELINE=android,
                    CAPABILITY_MANIFEST=capabilities,
                    CAPABILITY_BASELINE=baseline,
                ),
                patch.object(sys, "argv", [str(SCRIPT), *(["--check"] if check else [])]),
                contextlib.redirect_stdout(io.StringIO()),
            ):
                IMPORTER.main()
            self.assertEqual(self.apple, apple.read_bytes())
            self.assertEqual(self.android, android.read_bytes())
            return registry.read_bytes()

    def test_check_ignores_unrelated_product_capabilities(self) -> None:
        extra = copy.deepcopy(self.capabilities["capabilities"][0])
        extra["id"] = "automation.synthetic-unrelated-capability"
        self.capabilities["capabilities"].append(extra)
        self.assertEqual(IMPORTER.canonical_bytes(self.registry), self.run_import())

    def test_rebuild_preserves_reviewed_capability_inventory(self) -> None:
        self.assertEqual(
            IMPORTER.canonical_bytes(self.registry), self.run_import(check=False)
        )

    def test_check_rejects_changed_native_mapping(self) -> None:
        self.registry["metrics"][0]["apple"]["unit"] = "synthetic-invalid-unit"
        with self.assertRaisesRegex(SystemExit, "stale native registry import"):
            self.run_import()

    def test_check_rejects_stale_platform_availability(self) -> None:
        self.registry["available_capability_ids_by_platform"]["apple"].pop()
        with self.assertRaisesRegex(SystemExit, "stale native registry import"):
            self.run_import()

    def test_check_rejects_unknown_capability(self) -> None:
        self.registry["known_capability_ids"].append("synthetic.unknown-capability")
        with self.assertRaisesRegex(ValueError, "unknown product capabilities"):
            self.run_import()

    def test_check_rejects_reordered_capability_inventory(self) -> None:
        self.registry["known_capability_ids"].reverse()
        with self.assertRaisesRegex(ValueError, "product-capabilities order"):
            self.run_import()

    def test_check_rejects_duplicate_capability(self) -> None:
        self.registry["known_capability_ids"].append(
            self.registry["known_capability_ids"][0]
        )
        with self.assertRaisesRegex(ValueError, "duplicate registry capability"):
            self.run_import()

    def test_check_rejects_missing_metric_capability(self) -> None:
        self.registry["known_capability_ids"].remove(
            self.registry["metrics"][0]["capability_id"]
        )
        with self.assertRaisesRegex(ValueError, "metric capabilities missing"):
            self.run_import()


if __name__ == "__main__":
    unittest.main()
