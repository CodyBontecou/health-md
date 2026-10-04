"""Synthetic agent-bridge foundation tests; no native conformance or health reads."""
import copy
import importlib.util
import json
import runpy
import sys
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
import validate

SPEC = importlib.util.spec_from_file_location("agent_bridge_validation", HERE / "agent-bridge/v1/validation.py")
V = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(V)
BUNDLE = json.loads((HERE / "agent-bridge/v1/fixtures/conformance.json").read_text())
CASES = {case["id"]: case for case in BUNDLE["cases"]}

class AgentBridgeTests(unittest.TestCase):
    def check(self, case):
        V.validate_case(case, ROOT, validate.validate_json_schema_subset)

    def test_all_positive_negative_vectors(self):
        for case in BUNDLE["cases"]:
            with self.subTest(case=case["id"]):
                if case["expected"] == "valid": self.check(case)
                else:
                    with self.assertRaises(V.Invalid) as caught: self.check(case)
                    self.assertEqual(str(caught.exception), case["expected"])

    def test_fixture_entry_point_and_canonical_vectors(self):
        V.validate_fixture(ROOT, HERE / "agent-bridge/v1/fixtures/conformance.json", validate.validate_json_schema_subset, validate.fail)

    def test_every_fixed_operation_has_request_response_and_negative(self):
        operations = {"metric_catalog", "metric_series", "sleep_session_listing", "workout_listing", "coverage", "period_comparison", "workout_sleep_alignment", "source_record_listing", "derive_packet"}
        for operation in operations:
            for prefix in ("query-request-", "query-response-", "query-unknown-member-", "query-response-wrong-peer-"):
                self.assertIn(prefix + operation, CASES)
        self.assertGreaterEqual(sum(c["expected"] != "valid" for c in BUNDLE["cases"]), 80)

    def test_projection_product_is_not_daily_policy_or_transient_rpc(self):
        intent = CASES["projection-product-explicit-intent"]["value"]
        self.assertNotIn("settings_policy", intent)
        self.assertEqual(intent["product"]["product_id"], "android_source_projection_v1")
        schema = json.loads((HERE / "direct-protocol/v4/envelope.schema.json").read_text())
        kinds = {x["properties"]["type"]["const"] for x in schema["oneOf"]}
        self.assertNotIn("projection_request", kinds); self.assertNotIn("projection_response", kinds)
        catalog = V.projection_catalog()
        self.assertEqual(catalog["implementation_state"], "planned")
        self.assertFalse(catalog["contains_health_values"])

    def test_projection_approved_selectors_are_the_durable_execute_fingerprint(self):
        execute = CASES["projection-product-approved-execute"]["value"]
        job = CASES["projection-journal-before-first-health-read"]["value"]
        manifest = CASES["projection-manifest-under-execute-fingerprint"]["value"]
        self.assertEqual(job["execute"], execute)
        self.assertEqual(job["request_sha256"], V.digest(execute))
        self.assertEqual(manifest["request_sha256"], V.digest(execute))
        self.assertFalse(job["capture_started"])
        for key in ("object_ids", "field_ids", "detail"):
            altered = copy.deepcopy(execute)
            request = altered["plan"]["intent"]["product"]["request"]
            request[key] = "summary" if key == "detail" else []
            self.assertNotEqual(V.digest(altered), V.digest(execute))
        self.assertTrue(all(n == 0 for n in execute["plan"]["side_effects"].values()))

    def test_projection_intraday_observations_keep_time_identity_and_native_semantics(self):
        case = CASES["projection-intraday-child-point-not-average"]; self.check(case)
        point = case["value"]["selected_series"][0]
        self.assertEqual(point["field_id"], "heart_rate.samples.bpm")
        self.assertEqual(point["selection_metric_id"], "heart_rate_avg")
        self.assertEqual(point["observation_kind"], "point")
        self.assertNotIn("end", point); self.assertNotIn("statistic", point); self.assertNotIn("metric_id", point)
        self.assertEqual(point["identity"]["identity_kind"], "derived_child")
        self.assertEqual(point["start"]["precision"], "source_nanoseconds")
        for key in ("start", "identity"):
            broken = copy.deepcopy(case); broken["value"]["selected_series"][0].pop(key)
            with self.assertRaisesRegex(V.Invalid, "invalid_request"): self.check(broken)
        self.assertEqual(CASES["query-response-metric_series"]["value"]["items"][0]["type"], "metric")

    def test_projection_generic_carriage_and_resume_never_reinterpret_or_recapture(self):
        case = CASES["projection-v2-generic-carriage-v4-authority"]; self.check(case)
        base = case["value"]["base_artifact_manifest"]
        self.assertEqual(base["kind"], "generated_file")
        self.assertEqual(base["schema"], {"id": "healthmd.source_data_projection", "major": 1})
        self.assertNotIn("product_id", base); self.assertNotIn("profile", base)
        self.check(CASES["projection-resume-no-replan-recapture-or-preference-lookup"])
        self.check(CASES["projection-ndjson-resume-no-second-append"])
        missing = CASES["projection-resume-missing-spool-never-recaptures"]
        with self.assertRaisesRegex(V.Invalid, "spool_missing_restart_required"): self.check(missing)

    def test_every_wire_discriminator_has_old_peer_rejection(self):
        schema = json.loads((HERE / "direct-protocol/v4/envelope.schema.json").read_text())
        for branch in schema["oneOf"]:
            kind = branch["properties"]["type"]["const"]
            self.assertIn("v4-envelope-" + kind, CASES)
            self.assertEqual(CASES["old-peer-never-new-case-" + kind]["expected"], "unsupported_capability")

    def test_schemas_reproducible_and_closed(self):
        build = runpy.run_path(str(HERE / "agent-bridge/v1/build_schemas.py"))
        self.assertEqual(V.projection_catalog(), build["PROJECTION_CATALOG"])
        expected = [(HERE / "agent-bridge/v1/agent.schema.json", build["schema"](build["D"], build["BRIDGE_ROOTS"], "agent-bridge/v1/agent")),
                    (HERE / "agent-bridge/v1/query.schema.json", build["schema"](build["Q"], build["QUERY_ROOTS"], "agent-bridge/v1/source-query")),
                    (HERE / "direct-protocol/v4/envelope.schema.json", build["WIRE"])]
        for path, value in expected:
            self.assertEqual(json.loads(path.read_text()), value)
            def walk(node):
                if isinstance(node, dict):
                    if "$ref" in node:
                        self.assertTrue(node["$ref"].startswith("#/$defs/"))
                        self.assertIn(node["$ref"][8:], value["$defs"])
                    if node.get("type") == "object":
                        self.assertIs(node["additionalProperties"], False)
                        self.assertTrue(set(node["required"]) <= set(node["properties"]))
                    if node.get("type") == "array": self.assertIn("maxItems", node)
                    for child in node.values(): walk(child)
                elif isinstance(node, list):
                    for child in node: walk(child)
            walk(value)

    def test_json_preflight_duplicate_float_nonfinite_unicode_depth(self):
        for raw in [b'{"schema_version":1,"schema_version":2}', b'{"x":NaN}', b'{"x":1.0}', b'{"x":"\\ud800"}', b'[' * 26 + b'0' + b']' * 26, b' ' * 2097153]:
            with self.subTest(kind=len(raw)):
                with self.assertRaises(V.Invalid): V.parse(raw)

    def test_no_hidden_inheritance_and_unknown_nested_fields(self):
        case = copy.deepcopy(CASES["intent-request-owned-summary"])
        settings = case["value"]["settings_policy"]["settings"]
        del settings["dictionary"]
        with self.assertRaisesRegex(V.Invalid, "invalid_request"): self.check(case)
        case = copy.deepcopy(CASES["intent-request-owned-summary"])
        case["value"]["settings_policy"]["settings"]["presentation"]["frontmatter"]["credential"] = "synthetic"
        with self.assertRaisesRegex(V.Invalid, "invalid_request"): self.check(case)

    def test_all_available_never_resolves_health_bounds(self):
        case = CASES["all-available-logical-no-date-discovery"]
        self.check(case)
        plan = case["value"]
        self.assertEqual(plan["resolved_dates"], {"type": "all_available"})
        self.assertEqual(plan["predicted_paths"], [])
        self.assertIn("history_bounds_unresolved", plan["limitations"])
        self.assertTrue(all(type(n) is int and n == 0 for n in plan["side_effects"].values()))

    def test_template_bounds_and_expanded_collision(self):
        for path in ["x" * 256, "/".join(["x"] * 17), "lpt1.json", "a ", "{record_id}"]:
            case = copy.deepcopy(CASES["intent-request-owned-summary"])
            case["value"]["settings_policy"]["settings"]["folder_template"] = path
            with self.assertRaises(V.Invalid): self.check(case)
        self.assertEqual(CASES["zero-health-plan-year-json"]["value"]["predicted_paths"], ["2000/2000-01-01.json", "2000/2000-01-02.json"])

    def test_civil_boundaries_not_fixed_24_hours(self):
        zone = ZoneInfo("America/Los_Angeles")
        for day, hours in [("2000-04-02", 23), ("2000-10-29", 25)]:
            start = datetime.strptime(day, "%Y-%m-%d").replace(tzinfo=zone)
            end = start + timedelta(days=1)
            self.assertEqual((end.astimezone(timezone.utc) - start.astimezone(timezone.utc)).total_seconds(), hours * 3600)
        # This is a civil-boundary specification test, not native SDK sleep execution.

    def test_cursor_scope_controls_and_separate_key(self):
        case = CASES["authenticated-dataset-cursor"]
        claims = V.cursor_verify(case["value"], bytes.fromhex(case["context"]["synthetic_key_hex"]), case["context"]["expected"], case["context"]["now"])
        self.assertEqual(claims["position"], 1)
        with self.assertRaisesRegex(V.Invalid, "cursor_invalid"):
            V.cursor_verify(case["value"], bytes(reversed(range(32))), case["context"]["expected"], case["context"]["now"])
        request = CASES["query-request-metric_series"]["value"]
        altered = copy.deepcopy(request); altered["page"]["max_items"] -= 1
        self.assertNotEqual(V.query_scope_hash(request), V.query_scope_hash(altered))
        altered = copy.deepcopy(request); altered["request_id"] = "00000000-0000-4000-8000-000000000099"; altered["page"]["cursor"] = "synthetic"
        self.assertEqual(V.query_scope_hash(request), V.query_scope_hash(altered))

    def test_reviewed_catalog_never_promotes_support_or_equates_distinct_metrics(self):
        catalog = json.loads((HERE / "agent-bridge/v1/reviewed-query-catalog.json").read_text())
        V.schema_check(catalog, "query", validate.validate_json_schema_subset)
        self.assertNotEqual(catalog["provider_availability"], "available")
        rows = {r["metric_id"]: r for r in catalog["metrics"]}
        for row in rows.values(): self.assertIn(row["availability"], {"planned", "unavailable"})
        self.assertEqual(rows["hrv"]["availability"], "unavailable")
        self.assertEqual(rows["android.hrv_rmssd"]["registry_equivalence"], "platform_distinct")
        self.assertNotEqual(rows["android.skin_temperature"]["unit"], rows["wrist_temperature"]["unit"])
        self.assertEqual(rows["sleep_core"]["registry_equivalence"], "mapped_alias")
        self.assertEqual(rows["sleep_core"]["availability"], "unavailable")
        self.assertEqual(rows["android.medical_resources"]["availability"], "unavailable")

    def test_integer_count_overflow_and_mixed_units_rejected(self):
        case = copy.deepcopy(CASES["query-response-metric_series"])
        case["value"]["items"][0]["value"]["value"] = 9007199254740992
        with self.assertRaisesRegex(V.Invalid, "invalid_request"): self.check(case)
        case = copy.deepcopy(CASES["query-response-period_comparison"])
        case["value"]["items"][0]["second"]["unit"] = "ms"
        with self.assertRaises(V.Invalid): self.check(case)

    def test_response_page_and_truncation_bounds(self):
        case = copy.deepcopy(CASES["query-response-metric_series"])
        case["value"]["coverage"]["missing_count"] = 65
        with self.assertRaisesRegex(V.Invalid, "invalid_request"): self.check(case)
        case = copy.deepcopy(CASES["query-response-metric_series"])
        case["context"]["request"]["page"]["max_bytes"] = 1024
        case["value"]["query_sha256"] = V.query_scope_hash(case["context"]["request"])
        case["value"]["limitations"] = ["x" * 128] * 64
        # Duplicate limitations are rejected even before the byte limit.
        with self.assertRaises(V.Invalid): self.check(case)

    def test_mutation_cannot_use_export_authority(self):
        case = copy.deepcopy(CASES["control-native_profile-update"])
        case["context"]["authority"]["rights"] = ["export_execute"]
        with self.assertRaisesRegex(V.Invalid, "approval_required"): self.check(case)
        case = copy.deepcopy(CASES["control-local_recipe-run"])
        case["context"]["authority"]["rights"] = ["recipe_mutate"]
        with self.assertRaisesRegex(V.Invalid, "approval_required"): self.check(case)

    def test_bootstrap_and_future_scope_destination_journeys(self):
        first = ["export-discovery-before-plan", "bootstrap-first-plan-request", "zero-health-plan-year-json", "bootstrap-first-approval-request", "approved-execution"]
        future = ["bootstrap-future-scope-host-destination-first-plan", "bootstrap-future-scope-host-destination-new-plan",
                  "bootstrap-future-scope-host-destination-new-approval-request", "bootstrap-future-scope-host-destination-approved-execute"]
        for name in first + future: self.check(CASES[name])
        old = CASES["approved-execution"]; new = CASES[future[-1]]
        old_plan, new_plan = old["value"]["plan"], new["value"]["plan"]
        self.assertEqual(old_plan["authority_references"], new_plan["authority_references"])
        self.assertEqual(old_plan["effective_settings"], new_plan["effective_settings"])
        self.assertNotEqual(old_plan["scope_sha256"], new_plan["scope_sha256"])
        self.assertNotEqual(old_plan["intent"]["destination"], new_plan["intent"]["destination"])
        self.assertEqual(old["context"]["stored_native_delegations"], new["context"]["stored_native_delegations"])
        self.assertEqual(old["context"]["stored_host_delegations"], new["context"]["stored_host_delegations"])
        self.assertTrue(all(n == 0 for n in old_plan["side_effects"].values()))
        self.assertTrue(all(n == 0 for n in new_plan["side_effects"].values()))
        # Oracle validation leaves private snapshot inputs unchanged; native zero-call tracing is still required.
        snapshot = copy.deepcopy(new)
        self.check(new)
        self.assertEqual(snapshot, new)

    def test_derivation_is_pure_bounded_and_not_configuration_authority(self):
        case = CASES["bootstrap-future-scope-host-destination-approved-execute"]
        context = copy.deepcopy(case["context"]); plan = case["value"]["plan"]
        snapshot = copy.deepcopy(context)
        for slot in ("native", "host"):
            ref = plan["authority_references"][slot]
            stored = context["stored_" + slot + "_delegations"][ref["authority_id"]]
            authority = V.derived_export_authority(stored, plan, context["authority"])
            self.assertEqual(authority["authority_id"], stored["authority_id"])
            self.assertEqual(authority["scope_sha256"], plan["scope_sha256"])
            self.assertEqual(authority["destination_binding_ids"], [plan["intent"]["destination"]["binding_id"]])
            self.assertNotIn("native_configuration_mutate", authority["rights"])
            self.assertNotIn("native_schedule_mutate", authority["rights"])
        self.assertEqual(context, snapshot)
        self.assertEqual(CASES["bootstrap-export-delegation-not-configuration-authority"]["expected"], "approval_required")

    def test_discovery_references_are_sanitized_and_not_grant_minting(self):
        discovery = CASES["export-discovery-before-plan"]["value"]
        for reference in discovery["authority_references"]:
            self.assertEqual(set(reference), {"authority_id", "issuer", "grant_revision", "grant_sha256"})
            self.assertEqual(reference["issuer"], "native_source")
        case = copy.deepcopy(CASES["bootstrap-first-plan-request"])
        case["value"]["host_authority_reference"]["grant_sha256"] = "f" * 64
        with self.assertRaisesRegex(V.Invalid, "approval_required"): self.check(case)
        case = copy.deepcopy(CASES["bootstrap-first-plan-request"])
        case["context"]["stored_host_delegations"] = {}
        with self.assertRaisesRegex(V.Invalid, "approval_required"): self.check(case)
        case = copy.deepcopy(CASES["approved-execution"])
        case["context"]["stored_native_delegations"] = {}
        with self.assertRaisesRegex(V.Invalid, "approval_required"): self.check(case)

    def test_all_control_domains_have_candidate_bound_approval_journey(self):
        for domain in ("local_recipe", "native_profile", "host_schedule", "native_schedule", "native_destination"):
            for suffix in ("plan-request", "plan-response", "approval-request", "approval-response"):
                self.check(CASES["control-journey-" + domain + "-" + suffix])
            self.check(CASES["control-" + domain + "-plan"])
            self.check(CASES["control-" + domain + "-update"])
            plan = CASES["control-journey-" + domain + "-plan-response"]["value"]
            approved = CASES["control-journey-" + domain + "-approval-response"]["value"]
            self.assertIn("value", plan["proposal"])
            self.assertEqual(plan["proposal_sha256"], V.digest(plan["proposal"]))
            self.assertEqual(approved["binding"], V.control_binding(plan))
            self.assertEqual(set(plan["side_effects"]), {"health_reads", "earliest_date_reads", "content_preview_reads", "output_writes", "quota_consumed", "settings_mutations", "credential_enrollments", "wake_enrollments"})
            self.assertTrue(all(type(n) is int and n == 0 for n in plan["side_effects"].values()))

    def test_native_read_plan_does_not_require_unlock_or_mutation_grant(self):
        case = copy.deepcopy(CASES["control-journey-native_profile-plan-request"])
        self.assertEqual(case["context"]["planning_authority"]["configuration_protection"], "locked")
        self.assertNotIn("native_configuration_mutate", case["context"]["planning_authority"]["rights"])
        self.check(case)
        self.check(CASES["control-planning-while-native-protection-locked"])
        case = copy.deepcopy(CASES["control-native_profile-update"])
        case["context"]["authority"] = case["context"]["planning_authority"]
        with self.assertRaisesRegex(V.Invalid, "approval_required"): self.check(case)
        case = copy.deepcopy(CASES["control-journey-native_profile-approval-request"])
        case["context"].pop("native_or_host_decision_binding_sha256")
        with self.assertRaisesRegex(V.Invalid, "approval_required"): self.check(case)

    def test_rehashed_proposal_never_replaces_issued_control_plan(self):
        case = copy.deepcopy(CASES["control-rehashed-client-boxes-not-issued-authority"])
        V.control_plan_checks(case["value"]["operation"]["plan"], ROOT)
        with self.assertRaisesRegex(V.Invalid, "approval_required"): self.check(case)
        case = copy.deepcopy(CASES["control-native_schedule-update"])
        case["value"]["operation"]["value"]["enabled"] = True
        with self.assertRaisesRegex(V.Invalid, "binding_changed"): self.check(case)

    def test_control_receipt_and_replay_are_bound_not_reapplied(self):
        self.check(CASES["control-bound-mutation-receipt"])
        case = copy.deepcopy(CASES["control-bound-mutation-receipt"])
        del case["value"]["mutation_binding"]
        with self.assertRaisesRegex(V.Invalid, "invalid_request"): self.check(case)
        for domain in ("local_recipe", "native_profile", "host_schedule", "native_schedule", "native_destination"):
            case = CASES["control-exact-retry-stored-receipt-only-" + domain]
            self.assertEqual(case["context"]["now"], case["value"]["operation"]["plan"]["expires_at"])
            self.check(case)

    def test_source_projection_manifest_profile_media_and_exact_bytes(self):
        for suffix in ("json", "ndjson"):
            case = CASES["durable-source-projection-profile-" + suffix]
            self.check(case)
            artifact = case["value"]["artifacts"][0]
            self.assertEqual(artifact["profile"], "android-source-projection-v1")
            documents = case["context"]["artifact_documents"][artifact["artifact_id"]]
            for document in documents:
                self.assertEqual(document["schema"], "healthmd.source_data_projection")
                self.assertEqual(document["schema_version"], 1)
                self.assertIs(document["is_complete_daily_document"], False)
            if suffix == "json": self.assertEqual(len(documents), 1)
        for detail in ("selected_time_series", "native_records"):
            self.check(CASES["projection-artifact-detail-" + detail])
        case = copy.deepcopy(CASES["durable-source-projection-profile-json"])
        case["value"]["artifacts"][0]["profile"] = "android-provider-native-snapshot-v1"
        with self.assertRaisesRegex(V.Invalid, "invalid_request"): self.check(case)

    def test_source_specific_identity_metadata_never_defaults_unavailable_fields(self):
        apple = CASES["apple-native-identity-without-android-metadata"]
        self.check(apple)
        identity = apple["value"]["items"][0]["identity"]
        for field in ("last_modified", "client_record_id", "client_record_version"):
            self.assertNotIn(field, identity)
            self.assertEqual(identity["metadata_status"][field], "not_exposed_by_source")
        hc = CASES["hc-null-client-id-omitted-native-version-zero-retained"]
        self.check(hc)
        identity = hc["value"]["items"][0]["identity"]
        self.assertNotIn("client_record_id", identity)
        self.assertEqual(identity["metadata_status"]["client_record_id"], "absent")
        self.assertEqual(identity["client_record_version"], 0)
        self.assertEqual(identity["metadata_status"]["client_record_version"], "available")
        for field in ("last_modified", "client_record_id", "client_record_version"):
            case = CASES["hc-identity-missing-" + field + "-not-zero"]
            self.check(case)
            self.assertNotIn(field, case["value"]["items"][0]["identity"])

    def test_native_type_identifiers_are_not_semantic_ids_or_aliases(self):
        catalog = json.loads((HERE / "agent-bridge/v1/reviewed-query-catalog.json").read_text())
        rows = {r["metric_id"]: r for r in catalog["metrics"]}
        self.assertEqual(rows["heart_rate_avg"]["native_record_type"], "androidx.health.connect.client.records.HeartRateRecord")
        for unavailable in ("hrv", "wrist_temperature", "clinical_medication_records"):
            self.assertNotIn("native_record_type", rows[unavailable])
        identity = CASES["apple-native-identity-without-android-metadata"]["value"]["items"][0]["identity"]
        self.assertEqual(identity["record_type"], "HKQuantityTypeIdentifierStepCount")
        case = copy.deepcopy(CASES["query-response-metric_series"])
        case["value"]["items"][0]["metric_id"] = "HKQuantityTypeIdentifierStepCount"
        with self.assertRaisesRegex(V.Invalid, "invalid_request"): self.check(case)
        case = copy.deepcopy(CASES["apple-native-identity-without-android-metadata"])
        case["value"]["items"][0]["identity"]["record_type"] = "steps"
        with self.assertRaisesRegex(V.Invalid, "unsupported_metric"): self.check(case)

    def test_derived_child_provenance_is_not_parent_metadata_or_native_uuid(self):
        case = CASES["hc-derived-child-no-fabricated-system-metadata"]
        self.check(case)
        identity = case["value"]["items"][0]["identity"]
        self.assertEqual(identity["identity_kind"], "derived_child")
        self.assertEqual(identity["record_type"], "androidx.health.connect.client.records.HeartRateRecord$Sample")
        self.assertIn("parent_record_id", identity)
        self.assertIn("parent_record_type", identity)
        for field in ("last_modified", "client_record_id", "client_record_version"):
            self.assertNotIn(field, identity)
            self.assertEqual(identity["metadata_status"][field], "not_exposed_by_source")

    def test_timestamp_precision_and_binary64_provenance_round_trip(self):
        item = CASES["apple-native-identity-without-android-metadata"]["value"]["items"][0]
        self.assertEqual(item["start"]["precision"], "source_binary64_seconds")
        V.time_checks(item["start"])
        for bits, epoch, nano in [("bfe0000000000000", -1, 500000000), ("0000000000000000", 0, 0)]:
            V.time_checks({"epoch_second": epoch, "nanosecond": nano, "source_offset_seconds": None,
                           "precision": "source_binary64_seconds", "source_binary64_bits": bits})
        for precision, nano in [("source_milliseconds", 1), ("source_seconds", 1)]:
            with self.assertRaisesRegex(V.Invalid, "invalid_request"):
                V.time_checks({"epoch_second": 0, "nanosecond": nano, "precision": precision, "source_offset_seconds": None})
        case = copy.deepcopy(CASES["apple-native-identity-without-android-metadata"])
        case["value"]["items"][0]["start"]["source_binary64_bits"] = "7ff8000000000000"
        with self.assertRaisesRegex(V.Invalid, "invalid_request"): self.check(case)

if __name__ == "__main__": unittest.main()
