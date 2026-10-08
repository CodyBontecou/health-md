#!/usr/bin/env python3
"""Keep native migration checks independent of unrelated product capabilities."""

from __future__ import annotations

import contextlib
import copy
import importlib.util
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SCRIPT = Path(__file__).with_name("import-native-registry.py")
SPEC = importlib.util.spec_from_file_location("native_registry_import", SCRIPT)
IMPORTER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(IMPORTER)


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
