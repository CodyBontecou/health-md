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
                        {"schema_version": 2}, {"schema_version": True},
                        {"policy": "highest_date"}, {"refresh_recent_days": True},
                        {"today_refresh": "false"}):
            with self.subTest(changes=changes):
                value = json.loads(plan.to_json())
                value.update(changes)
                with self.assertRaises(ValueError):
                    Plan.from_json(json.dumps(value))

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
