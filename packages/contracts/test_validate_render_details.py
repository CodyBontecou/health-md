"""Schema controls for the successor-only detail presentation boundary."""
import copy
import json
from pathlib import Path
import unittest

import validate

ROOT = Path(__file__).resolve().parents[2]


class NativeDetailSchemaTests(unittest.TestCase):
    def setUp(self):
        self.schema = json.loads((ROOT / "packages/contracts/render-input/v2/render-input.schema.json").read_text())
        fixture = json.loads((ROOT / "packages/contracts/render-input/v2/fixtures/native-android-v6-handoff.json").read_text())
        self.batch = copy.deepcopy(fixture["render_batches"][0])
        self.day = self.batch["days"][0]
        self.day["native_details"] = {
            "output_keys": [self.day["metrics"][0]["output_key"]],
            "csv_rows": [{"date": self.day["owner_date"], "category": "Samples", "metric": "Captured sample", "value": "1234.125", "unit": "steps", "timestamp": "2026-07-25T00:00:00.123456789Z", "ordinal": 0}],
            "markdown_blocks": [{"heading": "Samples", "lines": ["1234.125 steps"], "ordinal": 0}],
            "bases_frontmatter_blocks": [{"key": "captured_samples", "lines": ["  - value: 1234.125"], "ordinal": 0}],
        }

    def check(self, batch=None, schema=None):
        validate.validate_json_schema_subset(batch or self.batch, schema or self.schema, "native-details")

    def test_successor_details_and_native_json_can_coexist(self):
        self.check()

    def test_null_incomplete_unknown_and_duplicate_keys_reject(self):
        for payload in [None, {}, {**self.day["native_details"], "unknown": True}, {**self.day["native_details"], "output_keys": ["steps", "steps"]}]:
            with self.subTest(payload=payload):
                batch = copy.deepcopy(self.batch)
                batch["days"][0]["native_details"] = payload
                with self.assertRaises(validate.ContractValidationError):
                    self.check(batch)

    def test_yaml_lines_cannot_escape_into_public_authority(self):
        for line in ["schema_version: 0", "  - value: 1\nschema_version: 0", "  - value: 1\rschema_version: 0"]:
            with self.subTest(line=line):
                batch = copy.deepcopy(self.batch)
                batch["days"][0]["native_details"]["bases_frontmatter_blocks"][0]["lines"] = [line]
                with self.assertRaises(validate.ContractValidationError):
                    self.check(batch)

    def test_competing_native_documents_reject(self):
        for key, value in [("csv_rows", []), ("markdown_body", {"lines": ["Native body"], "trailing_newline": True})]:
            with self.subTest(key=key):
                batch = copy.deepcopy(self.batch)
                batch["days"][0]["profile_documents"][key] = value
                with self.assertRaises(validate.ContractValidationError):
                    self.check(batch)

    def test_historical_schema_rejects_the_new_member(self):
        fixture = json.loads((ROOT / "packages/healthmd-core-rust/crates/healthmd-core/tests/fixtures/render-differential-v1.json").read_text())
        batch = copy.deepcopy(fixture["cases"][0]["batches"][0])
        schema = json.loads((ROOT / "packages/contracts/render-input/v1/render-input.schema.json").read_text())
        self.check(batch, schema)
        batch["days"][0]["native_details"] = self.day["native_details"]
        with self.assertRaises(validate.ContractValidationError):
            self.check(batch, schema)
