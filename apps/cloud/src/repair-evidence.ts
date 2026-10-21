// Evidence classification for a proposed owner-confirmed missing-export request.
// This is NOT an export planner or a trigger. No mobile link is enabled until
// the supplemental non-replacement path and native device grant exist.
export type RetainedDayStatus = "not_uploaded" | "available" | "unsupported_profile" |
  "filtered_profile" | "read_limit";

export interface RetainedDayEvidence {
  date: string;
  status: RetainedDayStatus;
  values: Record<string, number | null>;
  exportId?: string;
  source?: string;
  dailyVersion?: number;
}

export type ReadingEvidence = "observed" | "no_uploaded_day" |
  "value_unavailable_in_uploaded_summary" | "unsupported_profile" |
  "excluded_by_filter" | "outside_bounded_read";
export type RepairDisposition = "new_day_snapshot" | "supplement_required" | "not_actionable";

export interface DayRepairEvidence {
  date: string;
  disposition: RepairDisposition;
  metrics: Record<string, ReadingEvidence>;
}

/**
 * Null in an uploaded summary is not proof that HealthKit/Health Connect lacks
 * a value, nor proof that the exporter excluded the metric. Existing snapshots
 * may never be partially replaced. Only reviewed Apple-v8 chart fields are
 * accepted as input; other platforms need independently reviewed adapters.
 */
export function classifyAppleRepairEvidence(
  days: readonly RetainedDayEvidence[], metricIds: readonly string[],
): DayRepairEvidence[] {
  return days.map((day) => {
    const metrics: Record<string, ReadingEvidence> = Object.create(null) as Record<string, ReadingEvidence>;
    for (const id of metricIds) {
      const value = day.values[id];
      metrics[id] = day.status === "not_uploaded" ? "no_uploaded_day" :
        day.status === "filtered_profile" ? "excluded_by_filter" :
        day.status === "unsupported_profile" ? "unsupported_profile" :
        day.status === "read_limit" ? "outside_bounded_read" :
        typeof value === "number" && Number.isFinite(value) ? "observed" :
          "value_unavailable_in_uploaded_summary";
    }
    // Source/schema filtering and bounded reads cannot justify a new export.
    // A present day is always a complete-snapshot replacement hazard, even if
    // every selected metric is null or a user chooses the 'entire day' option.
    const disposition: RepairDisposition = day.status === "not_uploaded" ? "new_day_snapshot" :
      day.status === "available" ? "supplement_required" : "not_actionable";
    return { date: day.date, disposition, metrics };
  });
}
