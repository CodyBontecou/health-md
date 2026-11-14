import { describe, expect, it } from "vitest";
import { classifyAppleRepairEvidence, type RetainedDayEvidence } from "../src/repair-evidence";

describe("synthetic retained-export repair evidence (not a device-data claim)", () => {
  const fields = ["steps", "sleep_total"];
  it("distinguishes no upload from absent summary value and a measured zero", () => {
    const days: RetainedDayEvidence[] = [
      { date: "2026-04-01", status: "not_uploaded", values: { steps: null, sleep_total: null } },
      { date: "2026-04-02", status: "available", exportId: "synthetic-id",
        source: "ios", dailyVersion: 8, values: { steps: 0, sleep_total: null } },
    ];
    expect(classifyAppleRepairEvidence(days, fields)).toEqual([
      { date: "2026-04-01", disposition: "new_day_snapshot",
        metrics: { steps: "no_uploaded_day", sleep_total: "no_uploaded_day" } },
      { date: "2026-04-02", disposition: "supplement_required",
        metrics: { steps: "observed", sleep_total: "value_unavailable_in_uploaded_summary" } },
    ]);
  });
  it("does not suggest Apple measurements for Android, filtered, or budget-limited days", () => {
    const values = { steps: null };
    const days: RetainedDayEvidence[] = [
      { date: "2026-04-03", status: "unsupported_profile", source: "android", dailyVersion: 4, values },
      { date: "2026-04-04", status: "filtered_profile", source: "ios", dailyVersion: 8, values },
      { date: "2026-04-05", status: "read_limit", source: "ios", dailyVersion: 8, values },
    ];
    const result = classifyAppleRepairEvidence(days, ["steps"]);
    expect(result.map((day) => day.disposition)).toEqual(["not_actionable", "not_actionable", "not_actionable"]);
    expect(result.map((day) => day.metrics.steps)).toEqual([
      "unsupported_profile", "excluded_by_filter", "outside_bounded_read",
    ]);
  });
});
