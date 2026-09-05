#!/usr/bin/env python3
"""Focused acceptance and rejection tests for shared-setup v2 validation."""

from __future__ import annotations

import copy
import json
import tempfile
import unittest
from pathlib import Path
from typing import Any

import validate


ROOT = Path(__file__).resolve().parents[2]
APPLE_V2_FIXTURE = ROOT / "packages/contracts/shared-setup/v2/fixtures/apple-shared-setup-v2.json"
ANDROID_V2_FIXTURE = ROOT / "packages/contracts/shared-setup/v2/fixtures/android-shared-setup-v2.json"
TRANSACTION_SCENARIO_FIXTURE = ROOT / "packages/contracts/shared-setup/v2/fixtures/transaction-scenarios-v1.json"
METRIC_REGISTRY = ROOT / "packages/healthmd-core-rust/crates/healthmd-core/registry/metric-registry-v1.json"


class SharedSetupV2ValidationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.apple = json.loads(APPLE_V2_FIXTURE.read_text(encoding="utf-8"))
        self.android = json.loads(ANDROID_V2_FIXTURE.read_text(encoding="utf-8"))
        self.transaction_payload = json.loads(
            TRANSACTION_SCENARIO_FIXTURE.read_text(encoding="utf-8")
        )
        self.transaction = self.transaction_payload["scenario"]

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

    def validate_transaction_scenario(self, payload: object) -> bytes:
        encoded = validate.canonical_json(payload) + b"\n"
        with tempfile.NamedTemporaryFile(suffix=".json") as handle:
            handle.write(encoded)
            handle.flush()
            validate.validate_shared_setup_transaction_scenario_fixture(
                ROOT, Path(handle.name)
            )
        return encoded

    def assert_transaction_scenario_rejected(self, payload: object) -> None:
        with self.assertRaises(validate.ContractValidationError):
            self.validate_transaction_scenario(payload)

    def build_transaction(
        self,
        selection: list[str],
        mode: str,
        *,
        existing_state: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        selected = set(selection)
        return validate.build_shared_setup_transaction_candidate(
            self.transaction["source_document"],
            (
                existing_state
                if existing_state is not None
                else self.transaction["existing_state"]
            ),
            selection,
            mode,
            {
                bundle_id: native_id
                for bundle_id, native_id in self.transaction["generated_profile_ids"].items()
                if bundle_id in selected
            },
            {
                bundle_id: native_id
                for bundle_id, native_id in self.transaction["generated_schedule_ids"].items()
                if bundle_id in selected
            },
            {
                bundle_id: semantic_ids
                for bundle_id, semantic_ids in self.transaction["unsupported_semantic_ids"].items()
                if bundle_id in selected
            },
        )

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

    def test_dispatch_rejects_every_version_except_strict_integer_v2(self) -> None:
        self.validate(self.apple)

        # Version 1 was removed by deliberate owner decision; a well-formed
        # v1-shaped document fails closed as unsupported before versioned
        # decoding rather than being read as a v1 document.
        v1_shaped = {
            "schema": "healthmd.shared_setup",
            "schema_version": 1,
            "created_by": {"platform": "apple", "app_version": "1.0"},
            "metric_registry": copy.deepcopy(self.apple["metric_registry"]),
            "profile": {
                "name": "Removed Version 1 Shape",
                "metrics": {"enabled_ids": []},
            },
            "metric_aliases": [],
            "platform_extensions": {"apple": None, "android": None},
        }
        self.assert_rejected(v1_shaped)

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

    def test_transaction_scenario_is_canonical_and_has_exact_add_replace_results(self) -> None:
        self.assertEqual(
            TRANSACTION_SCENARIO_FIXTURE.read_bytes(),
            validate.canonical_json(self.transaction_payload) + b"\n",
        )
        self.validate_transaction_scenario(self.transaction_payload)
        self.assertEqual(
            self.transaction["caller_selection"],
            ["profile-003", "profile-001"],
        )
        self.assertEqual(
            self.transaction["normalized_selection"],
            ["profile-001", "profile-003"],
        )
        source = self.transaction["source_document"]
        self.assertEqual(source["active_profile"], "profile-003")
        self.assertTrue(source["profiles"][0]["schedule"]["activation_requested"])
        self.assertIsNone(source["profiles"][2]["schedule"])

        add_state = self.transaction["expected_add_state"]
        self.assertEqual(
            [row["profile_id"] for row in add_state["profiles"]],
            [
                "native-existing-profile-001",
                "native-existing-profile-002",
                "native-import-profile-101",
                "native-import-profile-103",
            ],
        )
        self.assertEqual(
            [row["name"] for row in add_state["profiles"]],
            ["Café", "CAFÉ 2", "cAFÉ 3", "Cloud Future"],
        )
        self.assertEqual(
            add_state["active_profile_id"], "native-existing-profile-002"
        )

        replace_state = self.transaction["expected_replace_state"]
        self.assertEqual(
            [row["profile_id"] for row in replace_state["profiles"]],
            ["native-import-profile-101", "native-import-profile-103"],
        )
        self.assertEqual(
            [row["name"] for row in replace_state["profiles"]],
            ["cAFÉ", "Cloud Future"],
        )
        self.assertEqual(
            replace_state["active_profile_id"], "native-import-profile-103"
        )
        self.assertEqual(
            self.transaction["expected_unmodified_local_environment"],
            self.transaction["local_environment"],
        )

        manifest = json.loads(
            (ROOT / "packages/contracts/manifest.json").read_text(encoding="utf-8")
        )
        shared_setup = next(
            contract
            for contract in manifest["contracts"]
            if contract["id"] == "healthmd.shared_setup"
        )
        self.assertEqual(shared_setup["version"], 2)
        self.assertEqual(shared_setup["status"], "deferred")
        self.assertIn(
            "packages/contracts/shared-setup/v2/fixtures/transaction-scenarios-v1.json",
            [fixture["path"] for fixture in shared_setup["fixtures"]],
        )

    def test_transaction_selection_rejects_empty_duplicate_unknown_and_invalid_ids(self) -> None:
        source = self.transaction["source_document"]
        invalid_selections: tuple[object, ...] = (
            [],
            ["profile-001", "profile-001"],
            ["profile-999"],
            [""],
            ["profile-001", None],
        )
        for selection in invalid_selections:
            with self.subTest(selection=selection):
                with self.assertRaises(validate.ContractValidationError):
                    validate.normalize_shared_setup_transaction_selection(
                        source, selection
                    )

    def test_transaction_active_profile_fallback_handles_omitted_source_active(self) -> None:
        replace = self.build_transaction(["profile-001"], "replace")
        self.assertEqual(
            replace["active_profile_id"], "native-import-profile-101"
        )

        dangling = copy.deepcopy(self.transaction["existing_state"])
        dangling["active_profile_id"] = "native-dangling-profile-999"
        add = self.build_transaction(
            ["profile-001"], "add", existing_state=dangling
        )
        self.assertEqual(add["active_profile_id"], "native-import-profile-101")

        source_active_selected = self.build_transaction(
            ["profile-003", "profile-001"], "replace"
        )
        self.assertEqual(
            source_active_selected["active_profile_id"],
            "native-import-profile-103",
        )

    def test_transaction_name_collisions_use_unicode_casefold_and_deterministic_suffixes(self) -> None:
        add = self.build_transaction(["profile-001"], "add")
        imported = add["profiles"][-1]
        self.assertEqual(imported["name"], "cAFÉ 3")

        source = copy.deepcopy(self.transaction["source_document"])
        source["profiles"][0]["name"] = "STRASSE"
        existing = copy.deepcopy(self.transaction["existing_state"])
        existing["profiles"][0]["name"] = "Straße"
        candidate = validate.build_shared_setup_transaction_candidate(
            source,
            existing,
            ["profile-001"],
            "add",
            {"profile-001": "native-import-profile-101"},
            {"profile-001": "native-import-schedule-101"},
            {"profile-001": []},
        )
        self.assertEqual(candidate["profiles"][-1]["name"], "STRASSE 2")

    def test_transaction_schedule_request_stays_disabled_and_runtime_empty(self) -> None:
        source_profile = self.transaction["source_document"]["profiles"][0]
        self.assertTrue(source_profile["schedule"]["activation_requested"])

        add = self.transaction["expected_add_state"]
        imported = next(
            row
            for row in add["schedules"]
            if row["profile_id"] == "native-import-profile-101"
        )
        self.assertEqual(
            imported,
            {
                "schedule_id": "native-import-schedule-101",
                "profile_id": "native-import-profile-101",
                "is_enabled": False,
                "enabled_at": None,
                "progress": None,
                "history": [],
                "pending_work": None,
                "worker_id": None,
            },
        )
        self.assertTrue(add["schedules"][0]["is_enabled"])
        self.assertEqual(
            self.transaction["expected_replace_state"]["schedules"],
            [imported],
        )

        confused = copy.deepcopy(self.transaction_payload)
        confused_import = next(
            row
            for row in confused["scenario"]["expected_add_state"]["schedules"]
            if row["profile_id"] == "native-import-profile-101"
        )
        confused_import["is_enabled"] = True
        self.assert_transaction_scenario_rejected(confused)

    def test_transaction_imports_are_unbound_blocked_and_cannot_inherit_destinations(self) -> None:
        for state_name in ("expected_add_state", "expected_replace_state"):
            state = self.transaction[state_name]
            imported = [
                row
                for row in state["profiles"]
                if row["settings_source_bundle_id"] is not None
            ]
            self.assertEqual(
                [row["destination_intent"] for row in imported],
                ["api_endpoint", "cloud"],
            )
            self.assertTrue(
                all(
                    row["folder_binding_id"] is None
                    and row["api_endpoint_binding_id"] is None
                    for row in imported
                )
            )
            self.assertTrue(
                {row["profile_id"] for row in imported}.issubset(
                    state["blocked_profile_ids"]
                )
            )

        inherited = copy.deepcopy(self.transaction_payload)
        imported = next(
            row
            for row in inherited["scenario"]["expected_add_state"]["profiles"]
            if row["profile_id"] == "native-import-profile-101"
        )
        imported["api_endpoint_binding_id"] = "native-endpoint-binding-002"
        self.assert_transaction_scenario_rejected(inherited)

    def test_transaction_preserves_foreign_extension_and_unsupported_meaning_per_profile(self) -> None:
        source_profile = self.transaction["source_document"]["profiles"][2]
        self.assertIsNotNone(source_profile["platform_extensions"]["android"])
        add_row = next(
            row
            for row in self.transaction["expected_add_state"]["sidecar"]["profiles"]
            if row["profile_id"] == "native-import-profile-103"
        )
        self.assertEqual(add_row["source_bundle_id"], "profile-003")
        self.assertEqual(add_row["source_profile"], source_profile)
        self.assertEqual(
            add_row["unsupported_semantic_ids"],
            ["future.recovery_score"],
        )

        lost_foreign = copy.deepcopy(self.transaction_payload)
        lost_row = next(
            row
            for row in lost_foreign["scenario"]["expected_add_state"]["sidecar"]["profiles"]
            if row["profile_id"] == "native-import-profile-103"
        )
        lost_row["source_profile"]["platform_extensions"]["android"] = None
        self.assert_transaction_scenario_rejected(lost_foreign)

        lost_unsupported = copy.deepcopy(self.transaction_payload)
        lost_row = next(
            row
            for row in lost_unsupported["scenario"]["expected_replace_state"]["sidecar"]["profiles"]
            if row["profile_id"] == "native-import-profile-103"
        )
        lost_row["unsupported_semantic_ids"] = []
        self.assert_transaction_scenario_rejected(lost_unsupported)

    def test_transaction_rollback_and_undo_are_exact_verified_and_one_shot(self) -> None:
        existing = self.transaction["existing_state"]
        rollback = self.transaction["expected_failed_apply_rollback"]
        self.assertEqual(
            validate.canonical_json(rollback["state"]),
            validate.canonical_json(existing),
        )
        self.assertTrue(rollback["verification_required"])
        self.assertTrue(rollback["previous_undo_restored"])

        for state_name in ("expected_add_state", "expected_replace_state"):
            restored = validate.undo_shared_setup_transaction_candidate(
                self.transaction[state_name]
            )
            self.assertEqual(restored, existing)
            self.assertIsNone(restored["undo_snapshot"])
            with self.assertRaises(validate.ContractValidationError):
                validate.undo_shared_setup_transaction_candidate(restored)

        corrupted = copy.deepcopy(self.transaction_payload)
        corrupted["scenario"]["expected_failed_apply_rollback"]["state"][
            "active_profile_id"
        ] = "native-existing-profile-001"
        self.assert_transaction_scenario_rejected(corrupted)

        replayable = copy.deepcopy(self.transaction_payload)
        replayable["scenario"]["expected_undo"]["second_attempt"] = "allowed"
        self.assert_transaction_scenario_rejected(replayable)

    def test_transaction_native_and_sensitive_state_cannot_leak_into_public_artifacts(self) -> None:
        local_native_values: set[str] = set()

        def collect(value: object) -> None:
            if isinstance(value, dict):
                for child in value.values():
                    collect(child)
            elif isinstance(value, list):
                for child in value:
                    collect(child)
            elif isinstance(value, str) and value.startswith(("native-", "local-")):
                local_native_values.add(value)

        collect(self.transaction)
        for name, public_payload in (
            ("scenario source", self.transaction["source_document"]),
            ("canonical Apple", self.apple),
            ("canonical Android", self.android),
        ):
            validate.validate_shared_setup_public_artifact_isolation(
                public_payload,
                local_native_values,
                name,
            )

        leaked_id = copy.deepcopy(self.transaction["source_document"])
        leaked_id["future_optional"] = {
            "reference": "native-import-profile-101"
        }
        with self.assertRaises(validate.ContractValidationError):
            validate.validate_shared_setup_public_artifact_isolation(
                leaked_id,
                local_native_values,
                "leaked native ID",
            )

        arbitrary_native_id = copy.deepcopy(self.apple)
        arbitrary_native_id["future_optional"] = "native-unlisted-profile-999"
        with self.assertRaises(validate.ContractValidationError):
            validate.validate_shared_setup_public_artifact_isolation(
                arbitrary_native_id,
                local_native_values,
                "arbitrary native ID",
            )

        prohibited_fields = {
            "credentials": "synthetic-secret",
            "folder_grant": "synthetic-grant",
            "native_path": "/private/synthetic/setup",
            "runtime_timestamp": "synthetic-runtime-time",
            "export_history": ["synthetic-history"],
            "health_data": {"steps": 1},
            "operation_id": "synthetic-operation",
        }
        for key, value in prohibited_fields.items():
            with self.subTest(key=key):
                candidate = copy.deepcopy(self.apple)
                candidate["future_optional"] = {key: value}
                with self.assertRaises(validate.ContractValidationError):
                    validate.validate_shared_setup_public_artifact_isolation(
                        candidate,
                        local_native_values,
                        f"prohibited {key}",
                    )

        leaked_uri = copy.deepcopy(self.android)
        leaked_uri["future_optional"] = "content://synthetic/local-grant"
        with self.assertRaises(validate.ContractValidationError):
            validate.validate_shared_setup_public_artifact_isolation(
                leaked_uri,
                local_native_values,
                "prohibited URI",
            )


if __name__ == "__main__":
    unittest.main()
