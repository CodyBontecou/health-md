#!/usr/bin/env python3
"""Current capability metadata cannot mutate old semantic/render registry identity."""
from __future__ import annotations

import copy
import hashlib
import json
import tempfile
import unittest
from pathlib import Path

import validate

ROOT = Path(__file__).resolve().parents[2]
INDEX = ROOT / "packages/healthmd-core-rust/crates/healthmd-core/registry/capability-index-v1.json"
REGISTRY = ROOT / "packages/healthmd-core-rust/crates/healthmd-core/registry/metric-registry-v1.json"


class CapabilityIndexTests(unittest.TestCase):
    def setUp(self) -> None:
        self.payload = json.loads(INDEX.read_text())

    def check(self, payload: dict) -> None:
        with tempfile.NamedTemporaryFile(suffix=".json") as handle:
            handle.write(json.dumps(payload).encode())
            handle.flush()
            validate.validate_capability_index(ROOT, Path(handle.name))

    def reject(self, mutation) -> None:
        payload = copy.deepcopy(self.payload)
        mutation(payload)
        with self.assertRaises(validate.ContractValidationError):
            self.check(payload)

    def test_current_index_and_frozen_registry_pass(self) -> None:
        self.check(self.payload)
        self.assertEqual("56def644baa3d81e0c6c2eda3733bfdd7ceee6554ca9ec609da80356c6578c99", hashlib.sha256(REGISTRY.read_bytes()).hexdigest())

    def test_planned_feature_cannot_become_available(self) -> None:
        self.reject(lambda p: p["available_capability_ids_by_platform"]["android"].append("agent.export.explicit-settings"))
        self.reject(lambda p: p["known_capability_ids"].pop())
        self.reject(lambda p: p["known_capability_ids"].reverse())

    def test_source_pin_closed_shape_and_version_checked(self) -> None:
        self.reject(lambda p: p.update(source_inventory_sha256="0" * 64))
        self.reject(lambda p: p.update(source_inventory_path="../replacement.json"))
        self.reject(lambda p: p.update(extra=True))
        self.reject(lambda p: p.update(schema_version=True))
        self.reject(lambda p: p["available_capability_ids_by_platform"].update(other=[]))


if __name__ == "__main__":
    unittest.main()
