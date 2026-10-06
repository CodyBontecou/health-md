"""Registry-v1 reconstruction uses frozen evidence, never the live product ledger."""

import hashlib
import importlib.util
import json
from pathlib import Path
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "import-native-registry.py"
spec = importlib.util.spec_from_file_location("native_registry_import", SCRIPT)
importer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(importer)
FROZEN_REGISTRY_SHA256 = "56def644baa3d81e0c6c2eda3733bfdd7ceee6554ca9ec609da80356c6578c99"


class NativeRegistryImportTests(unittest.TestCase):
    def regenerate(self):
        return importer.canonical_bytes(
            importer.build_registry(importer.parse_apple(), importer.parse_android())
        )

    def test_reconstruction_preserves_shipped_registry_bytes_and_hash(self):
        committed = importer.REGISTRY_PATH.read_bytes()
        self.assertEqual(hashlib.sha256(committed).hexdigest(), FROZEN_REGISTRY_SHA256)
        self.assertEqual(self.regenerate(), committed)

    def test_product_capability_additions_and_availability_do_not_rewrite_v1(self):
        read_text = Path.read_text

        def evolved_ledger(path, *args, **kwargs):
            if path.name == "product-capabilities.json":
                return json.dumps({"capabilities": [{
                    "id": "future.available-capability",
                    "platforms": {"apple": {"state": "available"},
                                  "android": {"state": "available"}},
                }]})
            return read_text(path, *args, **kwargs)

        with patch.object(Path, "read_text", evolved_ledger):
            self.assertEqual(self.regenerate(), importer.REGISTRY_PATH.read_bytes())

    def test_frozen_capability_projection_has_independent_provenance(self):
        baseline = json.loads(importer.CAPABILITY_BASELINE.read_text())
        registry = json.loads(importer.REGISTRY_PATH.read_text())
        self.assertEqual(baseline["schema"], "healthmd.native_capability_baseline")
        self.assertEqual(baseline["schema_version"], 1)
        self.assertEqual(baseline["source_registry_sha256"], FROZEN_REGISTRY_SHA256)
        for key in ("known_capability_ids", "available_capability_ids_by_platform"):
            self.assertEqual(baseline[key], registry[key])
        self.assertNotIn("future.available-capability", baseline["known_capability_ids"])


if __name__ == "__main__":
    unittest.main()
