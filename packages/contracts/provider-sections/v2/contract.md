# Typed WHOOP provider sections v2

Status: canonical. New Apple `healthmd.health_data` v10 captures use `providers.whoop.schema_version: 2`. Historical [WHOOP v1](../../proposals/provider-sections-v1/contract.md) and its fixture remain frozen and readable; retained v1 captures may appear in a newly rendered v10 record without being silently upgraded.

The [v2 schema](provider-sections-v2.schema.json) retains v1's resource, provenance, relationship, capture-state, error, warning, sleep, workout-zone, and body-snapshot meanings. The only new typed measurement is `cycles[].step_count`.

## Physiological-cycle steps

- Source: WHOOP public v2 `Cycle.step_count`, added 2026-09-23, using existing `read:cycles`. No new OAuth permission or re-consent is required.
- Identity: WHOOP physiological-cycle steps, **not civil-day Apple Health or Health Connect steps**. This is a `platform_distinct` mapping relative to the primary daily-step statistic; it is not a shared-registry alias.
- Unit/type: `count`, exact nonnegative integer, maximum `2147483647` (the upstream `int32` domain).
- Zero is a known measurement. Missing, upstream `null`, negative, fractional, Boolean, string, or out-of-domain values are unavailable and omitted, never converted to zero. Upstream null can mean incomplete device wear.
- Counts are independent of cycle score availability. An in-progress cycle retains explicit `end_time: null` and any available count without being labeled a completed civil day.
- Cycle IDs and start/end timestamps remain the measurement's provenance. Fetch time is not measurement time.
- Multiple cycles remain separate records. Do not sum, prorate, deduplicate by civil date, or copy these values into primary `activity.steps`, `steps`, or roll-ups.

## Formats and selection

JSON retains `providers.whoop.cycles[].step_count`. Markdown labels the column `Steps (cycle)` and explains the time-frame difference. Bases/frontmatter and scalar CSV use `whoop_cycle_step_count` only when exactly one cycle exists and its count is available. Structured CSV cycle rows retain every count. Scalar CSV labels it `Physiological-Cycle Steps`, category `WHOOP Cycle`, unit `count`, with the cycle start timestamp.

The data dictionary declares no roll-up rule for this scalar. WHOOP remains supplementation of retained Apple Health days, never a provider-only daily producer. The existing **Cycles & Strain** resource switch controls capture, typed counts, and native cycle sidecars; Apple Health steps are selected independently. Disabling cycles omits them, rather than fetching then redacting fields. Selected native responses retain whole payloads and relationship IDs.

Native `healthmd.external_provider_daily` v1 sidecars, API envelopes v1/v2, and direct-protocol wire versions do not change. Workout `score.zone_durations` remains canonical input; legacy `score.zone_duration` is considered only when the canonical key is absent, never blended with canonical null/partial data.

Android already preserves native cycle fields in selected raw snapshots. Typed physiological-cycle steps and matching independent resource controls are explicitly planned for a separately reviewed Android provider profile; frozen Android daily v4/v5 and civil-day steps are unchanged.

## Compatibility and rollout

Apple readers accept WHOOP v1 and v2. A v1 section cannot acquire typed step counts by defaulting its version to v2 during selection or decoding. Unknown typed versions are not interpreted as v2. Historical fixtures/signatures are not regenerated.

See the [Apple v10 migration](../../apple-export/v10/contract.md) for consumer and pinned-job requirements. Receiver/plugin source support must be released before enabling v10 writers for those consumers. This source change does not deploy a receiver, publish a plugin, release an app, or verify a live WHOOP member account.
