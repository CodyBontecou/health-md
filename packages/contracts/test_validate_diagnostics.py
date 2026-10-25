"""Synthetic diagnostics conformance and privacy-negative acceptance tests."""
import copy
import json
import unittest
from pathlib import Path

import validate
from diagnostics.validate import validate_event, validate_manifest

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "packages/contracts/diagnostics/v1"


class DiagnosticsValidationTests(unittest.TestCase):
    def setUp(self):
        self.event = json.loads((BASE / "fixtures/privacy.json").read_text())["expected_operational"]
        self.bundle = json.loads((BASE / "fixtures/bundle.json").read_text())["manifest"]

    def test_reviewed_vectors_and_native_generation(self):
        for path in ["privacy.json", "bundle.json"]:
            validate.validate_diagnostics_fixture(ROOT, BASE / "fixtures" / path)

    def test_unknown_health_and_credential_fields_cannot_be_published(self):
        for key in ["health_values", "access_token", "date_range", "destination_path"]:
            event = copy.deepcopy(self.event)
            event["fields"][key] = "SYNTHETIC_RESTRICTED_VALUE"
            with self.assertRaises(validate.ContractValidationError):
                validate_event(ROOT, event, validate.validate_json_schema_subset)

    def test_root_metadata_cannot_be_a_free_text_channel(self):
        for key, value in [("source", "/private/SYNTHETIC_PATH"), ("platform", "SYNTHETIC_VALUE"), ("sequence", "SYNTHETIC_VALUE"), ("severity", "friendly error replacement"), ("event_id", "unknown.event")]:
            event = copy.deepcopy(self.event)
            event[key] = value
            with self.assertRaises(validate.ContractValidationError):
                validate_event(ROOT, event, validate.validate_json_schema_subset)

    def test_known_fields_reject_wrong_types_and_excessive_values(self):
        for key, value in [("ready", 1), ("duration_ms", -1), ("error_code", 2**63), ("operation_id", "SYNTHETIC_VALUE"), ("peer_alias", "SYNTHETIC_PRIVATE_NAME")]:
            event = copy.deepcopy(self.event)
            event["fields"][key] = value
            with self.assertRaises(validate.ContractValidationError):
                validate_event(ROOT, event, validate.validate_json_schema_subset)

    def test_private_text_is_utf8_bounded(self):
        self.event["omitted_fields"].pop("peer_name")
        self.event["fields"]["peer_name"] = "🙂" * 129
        with self.assertRaises(ValueError):
            validate_event(ROOT, self.event, validate.validate_json_schema_subset)

    def test_fields_and_omissions_are_disjoint(self):
        self.event["omitted_fields"]["state"] = "not_recorded"
        with self.assertRaises(ValueError):
            validate_event(ROOT, self.event, validate.validate_json_schema_subset)

    def test_attachment_updates_health_disclosure_even_with_private_switch_off(self):
        validate_manifest(ROOT, self.bundle, validate.validate_json_schema_subset)
        self.bundle["health_content"] = "not_included"
        with self.assertRaises(ValueError):
            validate_manifest(ROOT, self.bundle, validate.validate_json_schema_subset)

    def test_bundle_path_traversal_and_unknown_keys_fail(self):
        self.bundle["files"][3]["path"] = "../../original.txt"
        with self.assertRaises(validate.ContractValidationError):
            validate_manifest(ROOT, self.bundle, validate.validate_json_schema_subset)

    def test_recorded_private_context_cannot_ignore_sharing_consent(self):
        self.bundle["files"][1]["privacy"] = "private_context"
        with self.assertRaises(ValueError):
            validate_manifest(ROOT, self.bundle, validate.validate_json_schema_subset)

    def test_inventory_duplicate_and_missing_files_fail(self):
        self.bundle["files"][2] = copy.deepcopy(self.bundle["files"][1])
        with self.assertRaises(ValueError):
            validate_manifest(ROOT, self.bundle, validate.validate_json_schema_subset)


if __name__ == "__main__":
    unittest.main()
