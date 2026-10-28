// Synthetic gallery data only; never derive WHOOP metrics from Apple summaries.
const HOUR_MS = 3_600_000;
const MINUTE_MS = 60_000;
const zoneKeys = [
  "zone_zero_milliseconds", "zone_one_milliseconds", "zone_two_milliseconds",
  "zone_three_milliseconds", "zone_four_milliseconds", "zone_five_milliseconds",
];

export function withWhoopSamples(days, template) {
  if (template?.schema !== "healthmd.provider.whoop_daily" || template.schema_version !== 1) {
    throw new Error("WHOOP gallery samples require the reviewed WHOOP daily v1 fixture");
  }
  return days.map((day, index) => {
    const whoop = structuredClone(template);
    const midnight = Date.parse(`${day.date}T00:00:00Z`);
    const at = (milliseconds) => new Date(midnight + milliseconds).toISOString();
    const suffix = day.date.replaceAll("-", "");
    whoop.fetched_at = at(23 * HOUR_MS);
    // A current-profile singleton must not become a historical body series.
    delete whoop.body;
    whoop.resources = whoop.resources.filter(({ resource }) => resource !== "body");

    const cycle = whoop.cycles[0];
    cycle.id = `cycle-synthetic-${suffix}`;
    cycle.start_time = at(7 * HOUR_MS);
    cycle.end_time = at(22 * HOUR_MS);
    cycle.timezone_offset = "+00:00";
    cycle.strain_score = Number((4 + (index * 1.7) % 15).toFixed(1));

    const recovery = whoop.recoveries[0];
    recovery.cycle_id = cycle.id;
    recovery.sleep_id = `sleep-synthetic-${suffix}`;
    recovery.recovery_score_percent = 28 + (index * 17) % 69;
    recovery.hrv_rmssd_ms = Number((35 + (index * 2.3) % 35).toFixed(1));
    recovery.resting_heart_rate_bpm = 47 + index % 11;
    recovery.user_calibrating = index < 3;
    if (index % 20 === 19) {
      recovery.score_state = "PENDING_SCORE";
      for (const key of [
        "recovery_score_percent", "resting_heart_rate_bpm", "hrv_rmssd_ms",
        "spo2_percent", "skin_temperature_celsius", "user_calibrating",
      ]) delete recovery[key];
    }

    const sleep = whoop.sleep[0];
    sleep.id = recovery.sleep_id;
    sleep.cycle_id = cycle.id;
    sleep.timezone_offset = "+00:00";
    sleep.total_sleep_milliseconds = Math.round((6.2 + index % 8 * 0.25) * HOUR_MS) + 750;
    sleep.awake_milliseconds = (20 + index % 14) * MINUTE_MS + 250;
    sleep.no_data_milliseconds = 5 * MINUTE_MS;
    sleep.total_in_bed_milliseconds = sleep.total_sleep_milliseconds + sleep.awake_milliseconds + sleep.no_data_milliseconds;
    sleep.light_sleep_milliseconds = Math.round(sleep.total_sleep_milliseconds * 0.53);
    sleep.slow_wave_sleep_milliseconds = Math.round(sleep.total_sleep_milliseconds * 0.22);
    sleep.rem_sleep_milliseconds = sleep.total_sleep_milliseconds - sleep.light_sleep_milliseconds - sleep.slow_wave_sleep_milliseconds;
    sleep.end_time = at(7 * HOUR_MS);
    sleep.start_time = at(7 * HOUR_MS - sleep.total_in_bed_milliseconds);
    sleep.sleep_debt_need_milliseconds = index % 4 * 15 * MINUTE_MS;
    sleep.recent_strain_need_milliseconds = (10 + index % 5 * 5) * MINUTE_MS;
    sleep.recent_nap_adjustment_milliseconds = index % 6 === 1 ? -15 * MINUTE_MS : 0;
    sleep.sleep_performance_percent = 74 + (index * 7) % 27;
    sleep.sleep_consistency_percent = 63 + (index * 5) % 35;
    sleep.sleep_efficiency_percent = 85 + index % 12;

    if (index % 6 === 0) {
      const nap = structuredClone(sleep);
      nap.id = `nap-synthetic-${suffix}`;
      nap.is_nap = true;
      nap.start_time = at(13 * HOUR_MS);
      nap.end_time = at(13 * HOUR_MS + 25 * MINUTE_MS);
      nap.total_in_bed_milliseconds = 25 * MINUTE_MS;
      nap.total_sleep_milliseconds = 20 * MINUTE_MS;
      nap.awake_milliseconds = 5 * MINUTE_MS;
      nap.no_data_milliseconds = 0;
      nap.light_sleep_milliseconds = 15 * MINUTE_MS;
      nap.slow_wave_sleep_milliseconds = 0;
      nap.rem_sleep_milliseconds = 5 * MINUTE_MS;
      nap.sleep_cycle_count = 1;
      nap.disturbance_count = 1;
      nap.sleep_efficiency_percent = 80;
      for (const key of [
        "baseline_sleep_need_milliseconds", "sleep_debt_need_milliseconds",
        "recent_strain_need_milliseconds", "recent_nap_adjustment_milliseconds",
        "sleep_performance_percent", "sleep_consistency_percent",
      ]) delete nap[key];
      whoop.sleep.push(nap);
    }
    // Demonstrate missingness without drawing an invented zero or need marker.
    if (index % 11 === 5) delete sleep.sleep_consistency_percent;
    if (index % 13 === 4) delete sleep.sleep_debt_need_milliseconds;

    const workout = whoop.workouts[0];
    workout.id = `workout-synthetic-${suffix}`;
    workout.start_time = at(16 * HOUR_MS);
    workout.end_time = at(17 * HOUR_MS);
    workout.timezone_offset = "+00:00";
    workout.strain_score = Number((5 + (index * 1.3) % 13).toFixed(1));
    workout.percent_recorded = 80 + index % 20;
    // WHOOP's reported zone total can be shorter than elapsed workout time.
    zoneKeys.forEach((key) => {
      workout.zone_durations[key] = Math.round(workout.zone_durations[key] * workout.percent_recorded / 100);
    });
    if (index % 7 === 0) {
      const second = structuredClone(workout);
      second.id = `workout-second-synthetic-${suffix}`;
      second.start_time = at(19 * HOUR_MS);
      second.end_time = at(20 * HOUR_MS);
      second.sport_name = "cycling";
      second.strain_score = 7.2;
      whoop.workouts.push(second);
    }

    if (index % 15 === 8) {
      whoop.capture_status = "partial";
      whoop.recoveries = [];
      const resource = whoop.resources.find(({ resource }) => resource === "recovery");
      resource.status = "failure";
      resource.error = { code: "network_unavailable", message: "Synthetic recovery capture unavailable.", retryable: true };
    }
    const records = { cycles: whoop.cycles, recovery: whoop.recoveries, sleep: whoop.sleep, workouts: whoop.workouts };
    whoop.resources.forEach((resource) => { resource.record_count = records[resource.resource].length; });
    return { ...day, providers: { ...day.providers, whoop } };
  });
}
