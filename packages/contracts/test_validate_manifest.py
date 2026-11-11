"""Mutable capability metadata does not weaken frozen contract validation."""
import copy
import json
from pathlib import Path
import unittest
from unittest.mock import patch

import validate

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "packages/contracts/manifest.json"
PRODUCT = ROOT / "packages/contracts/product-capabilities.json"


class ManifestValidationTests(unittest.TestCase):
    def setUp(self):
        self.manifest = json.loads(MANIFEST.read_text())
        self.product = json.loads(PRODUCT.read_text())
        # The mutable product inventory must not require a byte pin.
        self.manifest["inventories"][0].pop("sha256", None)

    def check(self):
        original_load = validate.load_json

        def load(path, context):
            if path == MANIFEST:
                return copy.deepcopy(self.manifest)
            if path == PRODUCT:
                return copy.deepcopy(self.product)
            return original_load(path, context)

        with patch.object(validate, "load_json", side_effect=load):
            return validate.validate_manifest(ROOT)

    def test_product_capability_metadata_can_change_without_rehashing(self):
        self.product["capabilities"][0]["summary"] += " Updated evidence description."
        result = self.check()
        self.assertEqual(result[3], 2)
        self.assertEqual(result[5], len(self.product["capabilities"]))

    def test_invalid_product_capabilities_are_still_rejected(self):
        self.product["capabilities"][0]["classification"] = "unchecked"
        with self.assertRaisesRegex(validate.ContractValidationError, "classification must"):
            self.check()

    def test_metric_registry_checksum_is_still_required(self):
        registry = next(item for item in self.manifest["inventories"]
                        if item["id"] == validate.METRIC_REGISTRY_SCHEMA)
        registry["sha256"] = "0" * 64
        with self.assertRaisesRegex(validate.ContractValidationError,
                                    "healthmd.metric_registry: SHA-256 mismatch"):
            self.check()

    def test_immutable_fixture_checksums_are_still_required(self):
        self.manifest["contracts"][0]["fixtures"][0]["sha256"] = "0" * 64
        with self.assertRaisesRegex(validate.ContractValidationError, "SHA-256 mismatch"):
            self.check()


if __name__ == "__main__":
    unittest.main()
