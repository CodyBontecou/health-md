#!/usr/bin/env python3
"""Focused acceptance and rejection tests for shared-setup v1/v2 validation."""

from __future__ import annotations

import copy
import hashlib
import json
import tempfile
import unittest
from pathlib import Path
from typing import Any

import validate


ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "packages/contracts/shared-setup/v1/fixtures/shared-setup-v1.json"
ANDROID_FIXTURE = ROOT / "packages/contracts/shared-setup/v1/fixtures/android-shared-setup-v1.json"
APPLE_V2_FIXTURE = ROOT / "packages/contracts/shared-setup/v2/fixtures/apple-shared-setup-v2.json"
ANDROID_V2_FIXTURE = ROOT / "packages/contracts/shared-setup/v2/fixtures/android-shared-setup-v2.json"
METRIC_REGISTRY = ROOT / "packages/healthmd-core-rust/crates/healthmd-core/registry/metric-registry-v1.json"
V1_IMMUTABLE_SHA256 = {
    "packages/contracts/shared-setup/v1/contract.md": "a7ab1e660fce30288e3f4fbad42aa16fba87062e30e76ee4a3ae6e7b5a52b40a",
    "packages/contracts/shared-setup/v1/shared-setup.schema.json": "0f2a9367b52d1c3c15d950dd6a3c4ca494214b2dc32a3105cc71576e60d0ad60",
    "packages/contracts/shared-setup/v1/fixtures/shared-setup-v1.json": "4101ba35c58ed25af60ff8b540ed03e6e230153748fef52bbd70dece9b68f751",
    "packages/contracts/shared-setup/v1/fixtures/android-shared-setup-v1.json": "817e30ce6c3e1c7d2a74502608b7bc0cb203058b7aa5de1c3c9bef7c6c27ede5",
}


def project_onto_current_metric_registry(payload: dict[str, Any]) -> dict[str, Any]:
    """Build an exact current-registry projection without rewriting historical fixtures."""
    candidate = copy.deepcopy(payload)
    registry_bytes = METRIC_REGISTRY.read_bytes()
    registry = json.loads(registry_bytes)
    registry_metrics = {metric["semantic_id"]: metric for metric in registry["metrics"]}
    enabled_ids = candidate["profile"]["metrics"]["enabled_ids"]

    candidate["metric_registry"] = {
        "schema": registry["schema"],
        "registry_version": registry["registry_version"],
        "registry_sha256": hashlib.sha256(registry_bytes).hexdigest(),
    }
    candidate["metric_aliases"] = [
        {
            "semantic_id": semantic_id,
            "equivalence": registry_metrics[semantic_id]["equivalence"],
            "apple_selection_id": _backed_selection_id(registry_metrics[semantic_id], "apple"),
            "android_selection_id": _backed_selection_id(registry_metrics[semantic_id], "android"),
        }
        for semantic_id in enabled_ids
    ]
    return candidate


def _backed_selection_id(metric: dict[str, Any], platform: str) -> str | None:
    binding = metric[platform]
    return binding["selection_id"] if binding["status"] == "backed" else None


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

    def test_v1_authorities_and_fixtures_remain_byte_immutable(self) -> None:
        for raw_path, expected in V1_IMMUTABLE_SHA256.items():
            self.assertEqual(hashlib.sha256((ROOT / raw_path).read_bytes()).hexdigest(), expected)

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

    def test_canonical_fixtures_pin_the_current_metric_registry(self) -> None:
        registry_bytes = METRIC_REGISTRY.read_bytes()
        registry = json.loads(registry_bytes)
        expected = {
            "schema": registry["schema"],
            "registry_version": registry["registry_version"],
            "registry_sha256": hashlib.sha256(registry_bytes).hexdigest(),
        }
        for fixture in (FIXTURE, ANDROID_FIXTURE):
            payload = json.loads(fixture.read_text(encoding="utf-8"))
            self.assertEqual(payload["metric_registry"], expected)

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
        candidate = project_onto_current_metric_registry(self.payload)
        self.validate(candidate)
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


class SharedSetupV2ValidationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.apple = json.loads(APPLE_V2_FIXTURE.read_text(encoding="utf-8"))
        self.android = json.loads(ANDROID_V2_FIXTURE.read_text(encoding="utf-8"))

    def validate(self, payload: object, *, writer: bool = False) -> bytes:
        encoded = validate.canonical_json(payload) + b"\n"
        self.validate_bytes(encoded, writer=writer)
        return encoded

    def validate_bytes(self, encoded: bytes, *, writer: bool = False) -> None:
        with tempfile.NamedTemporaryFile(suffix=".healthmdconfig") as handle:
            handle.write(encoded)
            handle.flush()
            if writer:
                validate.validate_shared_setup_writer_fixture(ROOT, Path(handle.name))
            else:
                validate.validate_shared_setup_fixture(ROOT, Path(handle.name))

    def assert_rejected(self, payload: object, *, writer: bool = False) -> None:
        with self.assertRaises(validate.ContractValidationError):
            self.validate(payload, writer=writer)

    def assert_bytes_rejected(self, encoded: bytes, *, writer: bool = False) -> None:
        with self.assertRaises(validate.ContractValidationError):
            self.validate_bytes(encoded, writer=writer)

    @staticmethod
    def referenced_ids(payload: dict[str, Any]) -> set[str]:
        return {
            semantic_id
            for profile in payload["profiles"]
            for semantic_id in (
                profile["metrics"]["enabled_ids"]
                + list(profile["individual_entries"]["metrics"])
            )
        }

    def test_canonical_writer_fixtures_cover_frozen_platform_modes(self) -> None:
        for fixture, payload in (
            (APPLE_V2_FIXTURE, self.apple),
            (ANDROID_V2_FIXTURE, self.android),
        ):
            self.assertEqual(
                fixture.read_bytes(),
                validate.canonical_json(payload) + b"\n",
            )
            self.validate(payload, writer=True)
            self.assertEqual(
                [row["semantic_id"] for row in payload["metric_aliases"]],
                sorted(self.referenced_ids(payload)),
            )

        apple_policies = {
            (
                profile["export"]["compatibility_detail"],
                profile["platform_extensions"]["apple"]["export"]["healthkit_source_archive"],
            )
            for profile in self.apple["profiles"]
        }
        self.assertEqual(
            apple_policies,
            {
                ("summary", "none"),
                ("selected_time_series", "none"),
                ("summary", "canonical_v1"),
                ("selected_time_series", "canonical_v1"),
            },
        )
        for profile in self.apple["profiles"]:
            apple_export = profile["platform_extensions"]["apple"]["export"]
            self.assertIn("generate_range_summary", apple_export)
            self.assertNotIn("rollups", apple_export)
            self.assertNotIn("include_granular_data", profile["export"])

        android_exports = [
            profile["platform_extensions"]["android"]["export"]
            for profile in self.android["profiles"]
        ]
        self.assertEqual({item["mode"] for item in android_exports}, {"compatibility", "raw_snapshot"})
        self.assertEqual(
            set(android_exports[0]["legacy_data_types"]),
            {
                "sleep", "activity", "heart", "vitals", "body", "nutrition",
                "mobility", "reproductive_health", "mindfulness", "workouts",
                "planned_workouts", "medical_resources",
            },
        )
        self.assertEqual(
            set(android_exports[0]["raw_snapshot"]),
            {"format", "scope", "include_exercise_routes", "page_size"},
        )

    def test_profile_order_bundle_references_names_and_array_order_are_exact(self) -> None:
        candidate = copy.deepcopy(self.apple)
        candidate["profiles"][0], candidate["profiles"][1] = (
            candidate["profiles"][1], candidate["profiles"][0]
        )
        self.assert_rejected(candidate)

        candidate = copy.deepcopy(self.apple)
        candidate["profiles"][0]["bundle_id"] = "native-profile-123"
        self.assert_rejected(candidate)

        candidate = copy.deepcopy(self.apple)
        candidate["active_profile"] = "profile-099"
        self.assert_rejected(candidate)

        candidate = copy.deepcopy(self.apple)
        candidate["profiles"][0]["name"] = " Summary"
        self.assert_rejected(candidate)

        candidate = copy.deepcopy(self.apple)
        candidate["profiles"][1]["name"] = candidate["profiles"][0]["name"].swapcase()
        self.assert_rejected(candidate)

        candidate = copy.deepcopy(self.apple)
        candidate["profiles"][3]["export"]["formats"] = ["markdown", "csv"]
        self.assert_rejected(candidate)

        candidate = copy.deepcopy(self.apple)
        candidate["profiles"][0]["metrics"]["enabled_ids"].reverse()
        self.assert_rejected(candidate)

    def test_alias_ledger_is_the_exact_union_including_disabled_individual_rows(self) -> None:
        candidate = copy.deepcopy(self.android)
        candidate["metric_aliases"] = [
            row for row in candidate["metric_aliases"] if row["semantic_id"] != "heart_rate_avg"
        ]
        self.assertFalse(
            self.android["profiles"][0]["individual_entries"]["metrics"]["heart_rate_avg"]["enabled"]
        )
        self.assert_rejected(candidate)

        candidate = copy.deepcopy(self.android)
        candidate["metric_aliases"].append(copy.deepcopy(candidate["metric_aliases"][0]))
        self.assert_rejected(candidate)

        candidate = copy.deepcopy(self.android)
        registry = json.loads(METRIC_REGISTRY.read_text(encoding="utf-8"))
        metric = next(item for item in registry["metrics"] if item["semantic_id"] == "hrv")
        candidate["metric_aliases"].append(
            {
                "semantic_id": "hrv",
                "equivalence": metric["equivalence"],
                "apple_selection_id": metric["apple"]["selection_id"],
                "android_selection_id": None,
            }
        )
        candidate["metric_aliases"].sort(key=lambda row: row["semantic_id"])
        self.assert_rejected(candidate)

        candidate = copy.deepcopy(self.android)
        candidate["metric_aliases"][0]["apple_selection_id"] = "wrong"
        self.assert_rejected(candidate)

        candidate = copy.deepcopy(self.android)
        candidate["profiles"][0]["metrics"]["enabled_categories"] = ["activity"]
        self.assert_rejected(candidate)

    def test_one_through_one_hundred_profiles_are_accepted_and_101_is_rejected(self) -> None:
        candidate = copy.deepcopy(self.apple)
        template = candidate["profiles"][0]
        candidate["profiles"] = []
        for index in range(1, 101):
            profile = copy.deepcopy(template)
            profile["bundle_id"] = f"profile-{index:03d}"
            profile["name"] = f"Synthetic Profile {index:03d}"
            candidate["profiles"].append(profile)
        candidate["active_profile"] = "profile-100"
        referenced = self.referenced_ids(candidate)
        candidate["metric_aliases"] = [
            row for row in candidate["metric_aliases"] if row["semantic_id"] in referenced
        ]
        self.validate(candidate)

        too_many = copy.deepcopy(candidate)
        extra = copy.deepcopy(template)
        extra["bundle_id"] = "profile-101"
        extra["name"] = "Synthetic Profile 101"
        too_many["profiles"].append(extra)
        self.assert_rejected(too_many)

        empty = copy.deepcopy(self.apple)
        empty["profiles"] = []
        self.assert_rejected(empty)

    def test_v2_generic_preflight_and_four_mibibyte_bound_apply_to_unknown_input(self) -> None:
        candidate = copy.deepcopy(self.apple)
        candidate["future_optional"] = {"bounded_note": "ignored", "values": [1, 2, 3]}
        candidate["profiles"][0]["future_optional"] = {"enabled_later": False}
        self.validate(candidate)
        self.assert_rejected(candidate, writer=True)

        candidate = copy.deepcopy(self.apple)
        nested: dict[str, object] = {}
        candidate["future_optional"] = nested
        for _ in range(21):
            child: dict[str, object] = {}
            nested["next"] = child
            nested = child
        self.assert_rejected(candidate)

        candidate = copy.deepcopy(self.apple)
        candidate["future_optional"] = list(range(513))
        self.assert_rejected(candidate)

        candidate = copy.deepcopy(self.apple)
        candidate["future_optional"] = "x" * 65_537
        self.assert_rejected(candidate)

        candidate = copy.deepcopy(self.apple)
        candidate["x" * 65_537] = True
        self.assert_rejected(candidate)

        candidate = copy.deepcopy(self.apple)
        candidate["future_optional"] = [[0] * 512 for _ in range(512)]
        self.assert_rejected(candidate)

        candidate = copy.deepcopy(self.android)
        candidate["future_padding"] = {
            f"future_{index:03d}": "x" * 65_536 for index in range(63)
        }
        encoded = validate.canonical_json(candidate) + b"\n"
        self.assertGreater(len(encoded), 4_000_000)
        self.assertLessEqual(len(encoded), validate.SHARED_SETUP_V2_MAX_BYTES)
        self.validate_bytes(encoded)
        oversized = encoded + b" " * (
            validate.SHARED_SETUP_V2_MAX_BYTES - len(encoded) + 1
        )
        self.assert_bytes_rejected(oversized)

    def test_dispatch_accepts_only_strict_integer_v1_or_v2(self) -> None:
        self.validate(self.apple)
        for fixture in (FIXTURE, ANDROID_FIXTURE):
            validate.validate_shared_setup_fixture(ROOT, fixture)

        for value in (0, 1, 3, "2", 2.0, True, None):
            candidate = copy.deepcopy(self.apple)
            candidate["schema_version"] = value
            self.assert_rejected(candidate)

        candidate = copy.deepcopy(self.apple)
        candidate["schema"] = "healthmd.shared_setup.v2"
        self.assert_rejected(candidate)

    def test_sensitive_runtime_native_and_obsolete_fields_or_strings_fail_closed(self) -> None:
        for key in (
            "native_profile_id",
            "nativeProfileId",
            "health_records",
            "healthRecords",
            "destination_fingerprint",
            "destinationFingerprint",
            "timezone",
            "calendarTimeZone",
            "rollups",
            "include_granular_data",
            "includeGranularData",
            "raw_snapshot",
        ):
            candidate = copy.deepcopy(self.apple)
            candidate[key] = "not portable"
            self.assert_rejected(candidate)

        candidate = copy.deepcopy(self.apple)
        candidate["profiles"][1]["schedule"]["enabled"] = True
        self.assert_rejected(candidate)

        candidate = copy.deepcopy(self.apple)
        candidate["profiles"][2]["destination"]["api_endpoint"]["token"] = "secret"
        self.assert_rejected(candidate)

        for value in (
            "Bearer abc123",
            "Authorization: secret",
            "content://synthetic/native-grant",
            "-----BEGIN PRIVATE KEY-----",
        ):
            candidate = copy.deepcopy(self.apple)
            candidate["future_optional"] = value
            self.assert_rejected(candidate)

    def test_destination_endpoint_and_schedule_contradictions_are_rejected(self) -> None:
        candidate = copy.deepcopy(self.apple)
        candidate["profiles"][0]["destination"]["api_endpoint"] = copy.deepcopy(
            candidate["profiles"][2]["destination"]["api_endpoint"]
        )
        self.assert_rejected(candidate)

        candidate = copy.deepcopy(self.apple)
        candidate["profiles"][0]["destination"] = {
            "kind": "api_endpoint",
            "api_endpoint": None,
        }
        self.validate(candidate)

        candidate = copy.deepcopy(self.apple)
        candidate["profiles"][1]["platform_extensions"]["apple"]["schedule"] = None
        self.assert_rejected(candidate)

        candidate = copy.deepcopy(self.apple)
        candidate["profiles"][0]["platform_extensions"]["apple"]["schedule"] = {
            "frequency": "daily",
            "custom_unit": "days",
            "today_refresh_requested": False,
            "today_refresh_interval_hours": 3,
        }
        self.assert_rejected(candidate)

        candidate = copy.deepcopy(self.apple)
        candidate["profiles"][1]["platform_extensions"]["apple"]["schedule"]["frequency"] = "weekly"
        self.assert_rejected(candidate)

        candidate = copy.deepcopy(self.apple)
        candidate["profiles"][3]["platform_extensions"]["apple"]["schedule"]["custom_unit"] = "weeks"
        self.assert_rejected(candidate)

        for value in ("2025-02-30", "2025-2-01"):
            candidate = copy.deepcopy(self.apple)
            candidate["profiles"][1]["schedule"]["cadence"]["anchor_date"] = value
            self.assert_rejected(candidate)

        candidate = copy.deepcopy(self.apple)
        candidate["profiles"][1]["schedule"]["activation_requested"] = False
        self.validate(candidate)

    def test_platform_extensions_are_exact_typed_per_profile_and_remain_distinct(self) -> None:
        candidate = copy.deepcopy(self.apple)
        candidate["profiles"][0]["platform_extensions"]["apple"] = None
        self.assert_rejected(candidate)

        candidate = copy.deepcopy(self.android)
        candidate["profiles"][0]["platform_extensions"]["android"] = None
        self.assert_rejected(candidate)

        for value in (1, 2.0, True):
            candidate = copy.deepcopy(self.apple)
            candidate["profiles"][0]["platform_extensions"]["apple"]["extension_version"] = value
            self.assert_rejected(candidate)

        candidate = copy.deepcopy(self.android)
        candidate["metric_registry"]["registry_version"] = 1.0
        self.assert_rejected(candidate)

        candidate = copy.deepcopy(self.apple)
        del candidate["profiles"][0]["platform_extensions"]["apple"]["export"]["generate_range_summary"]
        self.assert_rejected(candidate)

        candidate = copy.deepcopy(self.android)
        del candidate["profiles"][0]["platform_extensions"]["android"]["export"]["legacy_data_types"]["sleep"]
        self.assert_rejected(candidate)

        candidate = copy.deepcopy(self.android)
        candidate["profiles"][1]["platform_extensions"]["android"]["export"]["raw_snapshot"]["page_size"] = 5001
        self.assert_rejected(candidate)

        candidate = copy.deepcopy(self.android)
        foreign = copy.deepcopy(self.apple["profiles"][0]["platform_extensions"]["apple"])
        foreign["export"]["healthkit_source_archive"] = "canonical_v1"
        candidate["profiles"][1]["platform_extensions"]["apple"] = foreign
        self.validate(candidate)
        self.assertEqual(
            candidate["profiles"][1]["platform_extensions"]["android"]["export"]["mode"],
            "raw_snapshot",
        )
        self.assertEqual(
            candidate["profiles"][1]["platform_extensions"]["apple"]["export"]["healthkit_source_archive"],
            "canonical_v1",
        )

    def test_future_registry_ids_are_bounded_report_only_but_current_evidence_is_exact(self) -> None:
        candidate = copy.deepcopy(self.android)
        candidate["metric_registry"]["registry_sha256"] = "0" * 64
        candidate["profiles"][1]["metrics"]["enabled_ids"].append("future_metric")
        candidate["profiles"][1]["metrics"]["enabled_ids"].sort()
        candidate["metric_aliases"].append(
            {
                "semantic_id": "future_metric",
                "equivalence": "platform_exact_or_unavailable",
                "apple_selection_id": None,
                "android_selection_id": "future_metric",
            }
        )
        candidate["metric_aliases"].sort(key=lambda row: row["semantic_id"])
        self.validate(candidate)

        current = copy.deepcopy(candidate)
        current["metric_registry"] = copy.deepcopy(self.android["metric_registry"])
        self.assert_rejected(current)

    def test_v2_paths_and_endpoints_are_safe_components(self) -> None:
        for value in (
            "/absolute",
            "C:/windows",
            "../escape",
            "nested/../escape",
            "nested//empty",
            "nested\\windows",
            "content://grant",
            "%2e%2e/escape",
        ):
            candidate = copy.deepcopy(self.apple)
            candidate["profiles"][0]["export"]["folder_template"] = value
            self.assert_rejected(candidate)

        candidate = copy.deepcopy(self.apple)
        candidate["profiles"][2]["destination"]["api_endpoint"]["path"] = "/upload?token=x"
        self.assert_rejected(candidate)

        candidate = copy.deepcopy(self.apple)
        candidate["profiles"][2]["destination"]["api_endpoint"]["host"] = "user@setup.invalid"
        self.assert_rejected(candidate)


if __name__ == "__main__":
    unittest.main()
