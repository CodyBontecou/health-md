#!/usr/bin/env python3
"""Keep registry-v1 authority and immutable differential fixtures stable."""

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
        with self.assertRaisesRegex(ValueError, "capability"):
            self.build(manifest)

    def test_new_metric_capability_requires_explicit_registry_review(self):
        with patch.object(importer, "metric_capability", return_value="direct.synthetic_future_transport"):
            with self.assertRaisesRegex(ValueError, "reviewed registry revision"):
                self.build(self.manifest)

    def test_existing_metric_availability_still_comes_from_live_governance(self):
        manifest = copy.deepcopy(self.manifest)
        activity = next(item for item in manifest["capabilities"] if item["id"] == "export.activity-basics")
        activity["platforms"]["android"]["state"] = "unavailable"
        rebuilt = self.build(manifest)
        self.assertNotIn(
            "export.activity-basics", rebuilt["available_capability_ids_by_platform"]["android"]
        )
        self.assertIn("export.activity-basics", rebuilt["known_capability_ids"])


if __name__ == "__main__":
    unittest.main()
