#!/usr/bin/env python3
"""Focused acceptance and rejection tests for the shared-setup v1 validator."""

from __future__ import annotations

import copy
import json
import tempfile
import unittest
from pathlib import Path

import validate


ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "packages/contracts/shared-setup/v1/fixtures/shared-setup-v1.json"
ANDROID_FIXTURE = ROOT / "packages/contracts/shared-setup/v1/fixtures/android-shared-setup-v1.json"


class SharedSetupValidationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.payload = json.loads(FIXTURE.read_text(encoding="utf-8"))

    def validate(self, payload: object) -> None:
        encoded = validate.canonical_json(payload) + b"\n"
        with tempfile.NamedTemporaryFile(suffix=".json") as handle:
            handle.write(encoded)
            handle.flush()
            validate.validate_shared_setup_fixture(ROOT, Path(handle.name))

    def assert_rejected(self, payload: object) -> None:
        with self.assertRaises(validate.ContractValidationError):
            self.validate(payload)

    def test_canonical_fixture_and_safe_unknown_fields_are_accepted(self) -> None:
        self.validate(self.payload)
        android = json.loads(ANDROID_FIXTURE.read_text(encoding="utf-8"))
        self.validate(android)
        self.assertEqual(android["created_by"]["platform"], "android")
        self.assertTrue(android["profile"]["daily_notes"]["create_if_missing"])
        self.assertEqual(android["profile"]["individual_entries"]["filename_template"], "{metric}-{date}-{time}")
        self.assertEqual(android["profile"]["schedule"]["local_time"], {"hour": 6, "minute": 0})
        self.assertIsNone(android["metric_aliases"][0]["apple_selection_id"])
        self.assertEqual(android["metric_aliases"][0]["semantic_id"], "android.hrv_rmssd")
        candidate = copy.deepcopy(self.payload)
        candidate["future_optional"] = {"bounded_note": "ignored"}
        candidate["profile"]["presentation"]["future_optional"] = [1, 2, 3]
        self.validate(candidate)

    def test_writer_extension_is_required_but_foreign_extension_may_be_null(self) -> None:
        candidate = copy.deepcopy(self.payload)
        candidate["platform_extensions"]["android"] = None
        self.validate(candidate)

        candidate["platform_extensions"]["apple"] = None
        self.assert_rejected(candidate)

    def test_future_registry_metric_is_preserved_for_compatibility_analysis(self) -> None:
        candidate = copy.deepcopy(self.payload)
        candidate["metric_registry"]["registry_sha256"] = "0" * 64
        candidate["profile"]["metrics"]["enabled_ids"].append("future_metric")
        candidate["profile"]["metrics"]["enabled_ids"].sort()
        candidate["metric_aliases"].append(
            {
                "semantic_id": "future_metric",
                "equivalence": "platform_exact_or_unavailable",
                "apple_selection_id": None,
                "android_selection_id": "future_metric",
            }
        )
        candidate["metric_aliases"].sort(key=lambda item: item["semantic_id"])
        self.validate(candidate)

        known = copy.deepcopy(self.payload)
        known["metric_registry"]["registry_sha256"] = "0" * 64
        known["metric_aliases"][0]["android_selection_id"] = "historical_selection"
        self.validate(known)

    def test_future_schema_versions_and_missing_required_fields_are_rejected(self) -> None:
        for value in (0, 2, "1", None):
            candidate = copy.deepcopy(self.payload)
            candidate["schema_version"] = value
            self.assert_rejected(candidate)
        candidate = copy.deepcopy(self.payload)
        del candidate["profile"]["schedule"]
        self.assert_rejected(candidate)

    def test_sensitive_unknown_fields_and_authorization_values_are_rejected(self) -> None:
        for key in ("health_records", "source_data", "analytics", "email", "api_key"):
            candidate = copy.deepcopy(self.payload)
            candidate["profile"][key] = "not portable"
            self.assert_rejected(candidate)
        for value in ("Bearer abc123", "Basic dXNlcjpwYXNz", "Authorization: secret"):
            candidate = copy.deepcopy(self.payload)
            candidate["future_optional"] = value
            self.assert_rejected(candidate)

    def test_contradictory_schedule_representations_are_rejected(self) -> None:
        candidate = copy.deepcopy(self.payload)
        candidate["platform_extensions"]["apple"]["schedule"]["frequency"] = "weekly"
        self.assert_rejected(candidate)

        candidate = copy.deepcopy(self.payload)
        candidate["platform_extensions"]["apple"]["schedule"]["desired_target"] = "connected_mac"
        candidate["profile"]["schedule"]["desired_target"] = "api_endpoint"
        self.assert_rejected(candidate)

    def test_operational_schedule_and_credential_fields_are_rejected(self) -> None:
        for key in ("enabled", "enabled_at", "last_run", "operation_id", "engine_pin"):
            candidate = copy.deepcopy(self.payload)
            candidate["profile"]["schedule"][key] = True
            self.assert_rejected(candidate)
        candidate = copy.deepcopy(self.payload)
        candidate["profile"]["api_endpoint"]["token"] = "secret"
        self.assert_rejected(candidate)

    def test_unsafe_paths_are_rejected(self) -> None:
        for value in (
            "/absolute",
            "C:/windows",
            "../escape",
            "nested/../escape",
            "nested//empty",
            "nested\\windows",
            "content://grant",
            "%2e%2e/escape",
            "nested/%252e%252e/escape",
        ):
            candidate = copy.deepcopy(self.payload)
            candidate["profile"]["export"]["folder_template"] = value
            self.assert_rejected(candidate)
        for value in (".", ".."):
            candidate = copy.deepcopy(self.payload)
            candidate["profile"]["export"]["filename_template"] = value
            self.assert_rejected(candidate)

    def test_unsafe_endpoints_are_rejected(self) -> None:
        mutations = (
            ("scheme", "http"),
            ("host", "user@setup.invalid"),
            ("host", "bad..example"),
            ("host", "-bad.example"),
            ("path", "//network-path"),
            ("path", "/ingest?token=secret"),
            ("path", "/ingest%3Ftoken"),
        )
        for field, value in mutations:
            candidate = copy.deepcopy(self.payload)
            candidate["profile"]["api_endpoint"][field] = value
            self.assert_rejected(candidate)

    def test_metric_alias_tampering_and_categories_are_rejected(self) -> None:
        candidate = copy.deepcopy(self.payload)
        candidate["metric_aliases"][0]["android_selection_id"] = "wrong"
        self.assert_rejected(candidate)
        candidate = copy.deepcopy(self.payload)
        candidate["profile"]["metrics"]["enabled_categories"] = ["activity"]
        self.assert_rejected(candidate)

    def test_generic_depth_collection_string_and_file_bounds_are_rejected(self) -> None:
        candidate = copy.deepcopy(self.payload)
        nested: dict[str, object] = {}
        candidate["future_optional"] = nested
        for _ in range(17):
            child: dict[str, object] = {}
            nested["next"] = child
            nested = child
        self.assert_rejected(candidate)

        candidate = copy.deepcopy(self.payload)
        candidate["future_optional"] = list(range(257))
        self.assert_rejected(candidate)

        candidate = copy.deepcopy(self.payload)
        candidate["future_optional"] = "x" * 65_537
        self.assert_rejected(candidate)

        candidate = copy.deepcopy(self.payload)
        candidate["future_optional"] = "x" * validate.SHARED_SETUP_MAX_BYTES
        self.assert_rejected(candidate)


if __name__ == "__main__":
    unittest.main()
