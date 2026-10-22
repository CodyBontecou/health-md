"""Behavior tests for the proposal only; native adapters do not exist yet."""
from dataclasses import replace
from datetime import datetime, timezone
import json
import unittest

from reference import Plan, Request, completed_dates, select


class ReceiverCoverageTests(unittest.TestCase):
    def setUp(self):
        self.request = Request.at("occurrence-1", "scope-1", "America/Los_Angeles",
                                  ["2026-03-06", "2026-03-07", "2026-03-08"],
                                  datetime(2026, 3, 9, 15, tzinfo=timezone.utc))
        self.binding = "a" * 64  # synthetic keyed digest; not a credential

    def response(self, days, **changes):
        value = self.request.wire()
        value.update(schema="healthmd.receiver_coverage.response", completed_dates=days)
        value.update(changes)
        return json.dumps(value)

    def choose(self, response, **settings):
        return select(self.request, self.binding, policy="missing_days", response=response, **settings)

    def test_empty_receiver_selects_full_window(self):
        plan = self.choose(self.response([]))
        self.assertEqual(plan.selected, self.request.candidates)
        self.assertEqual(plan.coverage_status, "valid")

    def test_partial_receiver_preserves_explicit_hole_below_highest_date(self):
        plan = self.choose(self.response(["2026-03-06", "2026-03-08"]))
        self.assertEqual(plan.selected, ("2026-03-07",))

    def test_current_receiver_selects_nothing_without_refresh(self):
        plan = self.choose(self.response(list(self.request.candidates)))
        self.assertEqual(plan.selected, ())
        self.assertEqual(plan.residual, ())

    def test_malformed_response_falls_back_to_full_without_trusting_high_watermark(self):
        cases = ["", "not json", "null", "[]", '{"highest_date":"2026-03-08"}',
                 self.response(["2026-02-30"]), self.response(["2026-03-7"]),
                 self.response(["2026-03-07", "2026-03-07"]),
                 self.response(["2026-03-08", "2026-03-06"]),
                 self.response([None]), self.response([["2026-03-07"]]),
                 self.response("2026-03-08"), self.response([])[:-1],
                 self.response([], schema_version=True), self.response([], schema_version=2),
                 self.response([], highest_date="2026-03-08"),
                 self.response([], scope_id="other-scope"),
                 self.response([], request_id="stale-occurrence"),
                 self.response([], calendar_timezone="UTC"),
                 self.response([], start="2026-03-05"),
                 self.response([], end_exclusive="2026-03-10"),
                 self.response([])[:-1] + ',"schema_version":1}',
                 " " * (64 * 1024 + 1), "[" * 1100 + "]" * 1100]
        for body in cases:
            with self.subTest(body=body[:100]):
                plan = self.choose(body)
                self.assertEqual(plan.selected, self.request.candidates)
                self.assertEqual(plan.coverage_status, "fallback_full")

    def test_future_today_and_outside_window_are_never_coverage(self):
        for day in ("2026-03-05", "2026-03-09", "2026-03-10", "2099-01-01"):
            with self.subTest(day=day):
                self.assertEqual(self.choose(self.response([day])).coverage_status, "fallback_full")

    def test_unavailable_receiver_falls_back_not_empty_success(self):
        plan = self.choose(None)
        self.assertEqual(plan.selected, self.request.candidates)
        self.assertEqual(plan.coverage_status, "fallback_full")

    def test_default_full_lookback_ignores_receiver(self):
        plan = select(self.request, self.binding, response=self.response(list(self.request.candidates)))
        self.assertEqual(plan.selected, self.request.candidates)
        self.assertEqual(plan.coverage_status, "not_requested")

    def test_correction_policy_reexports_recent_completed_snapshots(self):
        plan = self.choose(self.response(list(self.request.candidates)), refresh_recent_days=2)
        self.assertEqual(plan.selected, ("2026-03-07", "2026-03-08"))

    def test_correction_window_uses_calendar_days_not_count_of_sparse_candidates(self):
        sparse = replace(self.request, candidates=("2026-03-01", "2026-03-08"))
        body = sparse.wire()
        body.update(schema="healthmd.receiver_coverage.response", completed_dates=list(sparse.candidates))
        plan = select(sparse, self.binding, policy="missing_days", response=json.dumps(body), refresh_recent_days=2)
        self.assertEqual(plan.selected, ("2026-03-08",))

    def test_today_refresh_is_independent_of_completed_coverage(self):
        plan = self.choose(self.response(list(self.request.candidates)), today_refresh=True)
        self.assertEqual(plan.selected, ("2026-03-09",))
        self.assertEqual(plan.request.wire()["end_exclusive"], "2026-03-09")

    def test_frozen_zone_handles_dst_and_midnight_not_utc_day(self):
        request = Request.at("occurrence-2", "scope-1", "America/Los_Angeles", ["2026-03-07"],
                             datetime(2026, 3, 9, 6, 30, tzinfo=timezone.utc))
        self.assertEqual(request.today, "2026-03-08")
        plan = select(request, self.binding, today_refresh=True)
        self.assertEqual(plan.selected, ("2026-03-07", "2026-03-08"))
        with self.assertRaises(ValueError):
            Request.at("occurrence-2", "scope-1", "UTC", ["2026-03-08"], datetime(2026, 3, 9))

    def test_retry_roundtrip_remains_exact_and_keeps_original_selection(self):
        plan = self.choose(self.response(["2026-03-07"]))
        decoded = Plan.from_json(plan.to_json())
        self.assertEqual(decoded, plan)
        residual = decoded.resume(self.binding, ["2026-03-06"])
        self.assertEqual(residual.residual, ("2026-03-08",))
        self.assertEqual(residual.selected, ("2026-03-06", "2026-03-08"))
        self.assertEqual(residual.request, plan.request)
        self.assertEqual(Plan.from_json(residual.to_json()), residual)
        self.assertEqual(residual.resume(self.binding, ["2026-03-06"]).residual, residual.residual)
        self.assertEqual(residual.resume(self.binding, ["2026-03-08"]).residual, ())

    def test_retry_rejects_coupled_march_6_omission_without_losing_pending_evidence(self):
        plan = self.choose(self.response(["2026-03-07"]), refresh_recent_days=1)
        original_json = plan.to_json()
        self.assertEqual(plan.selected, ("2026-03-06", "2026-03-08"))
        value = json.loads(original_json)
        value["selected"] = value["residual"] = ["2026-03-08"]
        corrupted_json = json.dumps(value)
        alternative = self.choose(self.response(["2026-03-06", "2026-03-07"]), refresh_recent_days=1)
        self.assertEqual(alternative.selected, ("2026-03-08",))
        self.assertNotEqual(value, json.loads(alternative.to_json()))
        self.assertEqual(Plan.from_json(alternative.to_json()).resume(self.binding, ["2026-03-08"]).residual, ())
        with self.assertRaises(ValueError):
            Plan.from_json(corrupted_json).resume(self.binding, ["2026-03-08"])
        self.assertEqual(plan.to_json(), original_json)
        restored = Plan.from_json(original_json).resume(self.binding, ["2026-03-08"])
        self.assertEqual(restored.selected, ("2026-03-06", "2026-03-08"))
        self.assertEqual(restored.residual, ("2026-03-06",))

    def test_endpoint_account_or_credential_change_blocks_retry(self):
        plan = self.choose(None)
        with self.assertRaisesRegex(ValueError, "destination changed"):
            plan.resume("b" * 64)
        self.assertEqual(plan.residual, self.request.candidates)

    def test_acknowledgement_cannot_remove_unselected_dates(self):
        plan = self.choose(self.response(["2026-03-07"]))
        with self.assertRaises(ValueError):
            plan.resume(self.binding, ["2026-03-07"])

    def test_invalid_persisted_plan_does_not_expand_or_drop_refresh(self):
        plan = self.choose(self.response(["2026-03-07"]), today_refresh=True)
        for changes in ({"residual": ["2026-03-07"]}, {"selected": ["2026-03-06", "2026-03-08"]},
                        {"destination_binding": "https://example.invalid/secret"},
                        {"schema_version": 3}, {"schema_version": True},
                        {"policy": "highest_date"}, {"refresh_recent_days": True},
                        {"today_refresh": "false"}):
            with self.subTest(changes=changes):
                value = json.loads(plan.to_json())
                value.update(changes)
                with self.assertRaises(ValueError):
                    Plan.from_json(json.dumps(value))

    def test_saved_coverage_is_required_and_invalid_evidence_is_not_retry_fallback(self):
        plan = self.choose(self.response(["2026-03-07"]), refresh_recent_days=1)
        saved = plan.to_json()
        cases = [None, "", "null", {}, self.response(["2026-03-07"], request_id="other-occurrence"),
                 self.response(["2026-03-07"], scope_id="other-scope"),
                 self.response(["2026-03-07"], calendar_timezone="UTC"),
                 self.response(["2026-03-07"], start="2026-03-05"),
                 self.response(["2026-03-07"], end_exclusive="2026-03-10"),
                 self.response(["2026-03-07"], schema_version=2),
                 self.response(["2026-03-07"], schema_version=True),
                 self.response(["2026-03-07"], highest_date="2026-03-08"),
                 self.response(["2026-03-09"]), self.response(["2026-03-08", "2026-03-06"]),
                 self.response(["2026-03-07"] * 31),
                 self.response(["2026-03-07"])[:-1] + ',"schema_version":1}',
                 " " * (64 * 1024 + 1)]
        for evidence in cases:
            with self.subTest(evidence=str(evidence)[:100]):
                value = json.loads(saved)
                value["coverage_response"] = evidence
                with self.assertRaises(ValueError):
                    Plan.from_json(json.dumps(value)).resume(self.binding)
        self.assertEqual(Plan.from_json(saved).resume(self.binding).residual, ("2026-03-06", "2026-03-08"))

    def test_maximum_valid_coverage_is_normalized_and_empty_selection_survives_retry(self):
        request = Request.at("occurrence-30", "scope-1", "UTC",
                             [f"2026-03-{day:02d}" for day in range(1, 31)],
                             datetime(2026, 3, 31, 15, tzinfo=timezone.utc))
        body = request.wire()
        body.update(schema="healthmd.receiver_coverage.response", completed_dates=list(request.candidates))
        response = json.dumps(body)
        response += " " * (64 * 1024 - len(response.encode("utf-8")))
        plan = select(request, self.binding, policy="missing_days", response=response)
        self.assertEqual(plan.coverage_status, "valid")
        self.assertLess(len(plan.coverage_response.encode("utf-8")), 64 * 1024)
        retry = Plan.from_json(plan.to_json()).resume(self.binding)
        self.assertEqual(retry.selected, ())
        self.assertEqual(retry.residual, ())
        self.assertEqual(retry, plan)

    def test_full_and_fallback_plans_cannot_acquire_coverage_on_retry(self):
        for plan in (select(self.request, self.binding, today_refresh=True),
                     self.choose(None, refresh_recent_days=1, today_refresh=True)):
            with self.subTest(status=plan.coverage_status):
                saved = plan.to_json()
                self.assertIsNone(json.loads(saved)["coverage_response"])
                decoded = Plan.from_json(saved).resume(self.binding, ["2026-03-06"])
                self.assertEqual(decoded.selected, ("2026-03-06", "2026-03-07", "2026-03-08", "2026-03-09"))
                self.assertEqual(decoded.residual, ("2026-03-07", "2026-03-08", "2026-03-09"))
                self.assertEqual(Plan.from_json(decoded.to_json()), decoded)
                value = json.loads(saved)
                value["coverage_response"] = self.response(list(self.request.candidates))
                with self.assertRaises(ValueError):
                    Plan.from_json(json.dumps(value)).resume(self.binding)
                value = json.loads(saved)
                value["selected"] = value["residual"] = ["2026-03-08", "2026-03-09"]
                with self.assertRaises(ValueError):
                    Plan.from_json(json.dumps(value)).resume(self.binding)

    def test_saved_coverage_is_bound_to_frozen_request_and_selection_policy(self):
        plan = self.choose(self.response(["2026-03-07"]), refresh_recent_days=1, today_refresh=True)
        saved = plan.to_json()
        request_changes = ({"request_id": "other-occurrence"}, {"scope_id": "other-scope"},
                           {"calendar_timezone": "UTC"}, {"today": "2026-03-10"},
                           {"candidates": ["2026-03-07", "2026-03-08"]},
                           {"candidates": ["2026-03-06", "2026-03-07"]})
        for changes in request_changes:
            with self.subTest(request=changes):
                value = json.loads(saved)
                value["request"].update(changes)
                with self.assertRaises(ValueError):
                    Plan.from_json(json.dumps(value)).resume(self.binding)
        for changes in ({"refresh_recent_days": 2}, {"today_refresh": False}, {"policy": "full_lookback"},
                        {"coverage_status": "fallback_full"}, {"coverage_status": "unrecognized"}):
            with self.subTest(policy=changes):
                value = json.loads(saved)
                value.update(changes)
                with self.assertRaises(ValueError):
                    Plan.from_json(json.dumps(value)).resume(self.binding)
        decoded = Plan.from_json(saved)
        with self.assertRaisesRegex(ValueError, "destination changed"):
            decoded.resume("b" * 64)
        self.assertEqual(decoded.to_json(), saved)

    def test_retry_keeps_original_hole_correction_and_today_despite_newer_coverage(self):
        plan = self.choose(self.response(["2026-03-07"]), refresh_recent_days=1, today_refresh=True)
        saved = plan.to_json()
        later_request = replace(self.request, request_id="occurrence-2", today="2026-03-10")
        newer = later_request.wire()
        newer.update(schema="healthmd.receiver_coverage.response", completed_dates=list(later_request.candidates))
        next_plan = select(later_request, self.binding, policy="missing_days", response=json.dumps(newer),
                           refresh_recent_days=1, today_refresh=True)
        self.assertEqual(next_plan.selected, ("2026-03-08", "2026-03-10"))
        retry = Plan.from_json(saved).resume(self.binding, ["2026-03-08"])
        self.assertEqual(retry.selected, ("2026-03-06", "2026-03-08", "2026-03-09"))
        self.assertEqual(retry.residual, ("2026-03-06", "2026-03-09"))
        self.assertEqual(retry.request, self.request)
        self.assertEqual(retry.coverage_response, plan.coverage_response)
        retry = Plan.from_json(retry.to_json()).resume(self.binding, ["2026-03-09"])
        self.assertEqual(retry.residual, ("2026-03-06",))
        self.assertEqual(retry.selected, plan.selected)
        self.assertEqual(Plan.from_json(retry.to_json()).resume(self.binding, ["2026-03-06"]).residual, ())
        self.assertEqual(plan.to_json(), saved)

    def test_evidence_less_v1_and_unrecognized_v2_fields_require_explicit_recovery(self):
        plan = self.choose(self.response(["2026-03-07"]))
        saved = plan.to_json()
        self.assertEqual(json.loads(saved)["schema_version"], 2)
        for version, keep_evidence in ((1, False), (1, True), (2, False)):
            with self.subTest(version=version, keep_evidence=keep_evidence):
                value = json.loads(saved)
                value["schema_version"] = version
                if not keep_evidence:
                    value.pop("coverage_response")
                with self.assertRaises(ValueError):
                    Plan.from_json(json.dumps(value)).resume(self.binding)
        value = json.loads(saved)
        value["unknown"] = "not a supported migration"
        with self.assertRaises(ValueError):
            Plan.from_json(json.dumps(value)).resume(self.binding)
        self.assertEqual(Plan.from_json(saved).resume(self.binding), plan)

    def test_invalid_configuration_is_not_network_fallback(self):
        for count in (-1, 31, True):
            with self.assertRaises(ValueError):
                self.choose(None, refresh_recent_days=count)
        with self.assertRaises(ValueError):
            select(self.request, self.binding, policy="highest_observed")

    def test_parser_returns_only_explicit_completed_dates(self):
        self.assertEqual(completed_dates(self.request, self.response(["2026-03-08"])), {"2026-03-08"})


if __name__ == "__main__":
    unittest.main()
