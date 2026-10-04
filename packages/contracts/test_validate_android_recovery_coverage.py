#!/usr/bin/env python3
"""Strict private-field supplement checks; historical Shared Setup bytes stay frozen."""
from __future__ import annotations

import copy
import json
import tempfile
import unittest
from pathlib import Path

import validate

ROOT = Path(__file__).resolve().parents[2]
INVENTORY = ROOT / "packages/contracts/portability-inventory/android-agent-recovery/v1/inventory.json"


class AndroidRecoveryCoverageTests(unittest.TestCase):
    def setUp(self) -> None:
        self.payload = json.loads(INVENTORY.read_text())

    def check(self, payload: dict) -> None:
        with tempfile.NamedTemporaryFile(suffix=".json") as handle:
            handle.write(json.dumps(payload).encode())
            handle.flush()
            validate.validate_android_recovery_coverage(ROOT, Path(handle.name))

    def reject(self, mutation) -> None:
        payload = copy.deepcopy(self.payload)
        mutation(payload)
        with self.assertRaises(validate.ContractValidationError):
            self.check(payload)

    def test_reviewed_private_fields_pass(self) -> None:
        self.check(self.payload)
        self.assertEqual(7, len(self.payload["fields"]))

    def test_recovery_state_cannot_become_portable(self) -> None:
        for disposition in ("portable", "platform_extension", "schedule_intent", "local_only"):
            with self.subTest(disposition=disposition):
                self.reject(lambda p: p["fields"][0].update(disposition=disposition))
        self.reject(lambda p: p["fields"][0].update(contract_path="profiles[].schedule.enabled"))

    def test_unknown_duplicate_reordered_and_empty_fields_rejected(self) -> None:
        self.reject(lambda p: p.update(extra=True))
        self.reject(lambda p: p["fields"][0].update(extra=True))
        self.reject(lambda p: p["fields"].append(copy.deepcopy(p["fields"][0])))
        self.reject(lambda p: p["fields"].reverse())
        self.reject(lambda p: p.update(fields=[]))
        self.reject(lambda p: p["fields"][0].update(evidence=" "))
        self.reject(lambda p: p["fields"][0].update(coverage_kind="portable"))

    def test_frozen_ledger_pin_and_target_are_not_replaced(self) -> None:
        self.reject(lambda p: p["base_inventory"].update(sha256="0" * 64))
        self.reject(lambda p: p["base_inventory"].update(path="../replacement.json"))
        self.reject(lambda p: p["target_contract"].update(schema_version=3))
        self.reject(lambda p: p.update(schema_version=True))
        self.reject(lambda p: p.update(audited_git_base="main"))

    def test_baseline_row_cannot_be_reclassified(self) -> None:
        base = json.loads((ROOT / self.payload["base_inventory"]["path"]).read_text())
        self.reject(lambda p: p.update(fields=[dict(base["fields"][0], disposition="prohibited", contract_path=None)]))


if __name__ == "__main__":
    unittest.main()
