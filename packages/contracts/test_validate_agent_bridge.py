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

    def test_every_wire_discriminator_has_old_peer_rejection(self):
        schema = json.loads((HERE / "direct-protocol/v4/envelope.schema.json").read_text())
        for branch in schema["oneOf"]:
            kind = branch["properties"]["type"]["const"]
            self.assertIn("v4-envelope-" + kind, CASES)
            self.assertEqual(CASES["old-peer-never-new-case-" + kind]["expected"], "unsupported_capability")

    def test_schemas_reproducible_and_closed(self):
        build = runpy.run_path(str(HERE / "agent-bridge/v1/build_schemas.py"))
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

if __name__ == "__main__": unittest.main()
