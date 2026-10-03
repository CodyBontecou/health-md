#!/usr/bin/env python3
"""Behavior tests for product inventory versus immutable registry authority."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "import-native-registry.py"
spec = importlib.util.spec_from_file_location("registry_importer", SCRIPT)
importer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(importer)


class RegistryCapabilityScopeTests(unittest.TestCase):
    def setUp(self):
        self.apple = importer.parse_apple()
        self.android = importer.parse_android()
        self.manifest = json.loads(importer.CAPABILITY_MANIFEST.read_text())

    def build_with_manifest(self, manifest):
        with tempfile.TemporaryDirectory(prefix="healthmd-registry-scope-test-") as directory:
            path = Path(directory) / "product-capabilities.json"
            path.write_text(json.dumps(manifest))
            with patch.object(importer, "CAPABILITY_MANIFEST", path):
                return importer.build_registry(self.apple, self.android)

    def test_reproduction_preserves_exact_registry_identity_and_all_metric_rows(self):
        actual = importer.canonical_bytes(importer.build_registry(self.apple, self.android))
        expected = importer.REGISTRY_PATH.read_bytes()
        self.assertEqual(actual, expected)
        scope = json.loads(importer.CAPABILITY_SCOPE.read_text())
        self.assertEqual(hashlib.sha256(actual).hexdigest(), scope["baseline_registry_sha256"])
        # Watch delivery is in the product inventory but not pure metric authority.
        self.assertIn("export.watch-origin-manual-api", [row["id"] for row in self.manifest["capabilities"]])
        self.assertNotIn("export.watch-origin-manual-api", json.loads(actual)["known_capability_ids"])

    def test_adding_product_only_capability_does_not_repin_immutable_semantic_results(self):
        manifest = copy.deepcopy(self.manifest)
        manifest["capabilities"].insert(0, {
            "id": "device.synthetic-network-feature",
            "platforms": {"apple": {"state": "available"}, "android": {"state": "available"}}
        })
        actual = importer.canonical_bytes(self.build_with_manifest(manifest))
        self.assertEqual(actual, importer.REGISTRY_PATH.read_bytes())

    def test_missing_scoped_inventory_entry_fails_closed(self):
        manifest = copy.deepcopy(self.manifest)
        manifest["capabilities"] = [row for row in manifest["capabilities"] if row["id"] != "export.activity-basics"]
        with self.assertRaisesRegex(ValueError, "missing from product inventory"):
            self.build_with_manifest(manifest)

    def test_new_metric_capability_requires_explicit_scope_review(self):
        with patch.dict(importer.CATEGORY_CAPABILITY, {"Activity": "export.synthetic-new-metric-contract"}):
            with self.assertRaisesRegex(ValueError, "reviewed registry scope/version change"):
                importer.build_registry(self.apple, self.android)

    def test_existing_scoped_availability_is_still_derived_from_product_inventory(self):
        manifest = copy.deepcopy(self.manifest)
        row = next(row for row in manifest["capabilities"] if row["id"] == "export.daily-files")
        row["platforms"]["apple"] = {"state": "planned", "target": "synthetic test"}
        actual = self.build_with_manifest(manifest)
        self.assertNotIn("export.daily-files", actual["available_capability_ids_by_platform"]["apple"])
        self.assertIn("export.daily-files", actual["available_capability_ids_by_platform"]["android"])
        self.assertIn("export.daily-files", actual["known_capability_ids"])


if __name__ == "__main__":
    unittest.main()
