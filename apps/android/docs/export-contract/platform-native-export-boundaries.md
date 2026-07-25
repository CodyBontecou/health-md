# Platform-Native Export Boundaries

**Status:** product/export contract decision
**Last updated:** 2026-06-20
**Scope:** Health.md iOS/macOS HealthKit exports and Health.md Android Health Connect exports

Health.md does **not** promise perfect one-to-one parity between Apple HealthKit and Android Health Connect. The product exports the data each platform exposes, preserves platform-native semantics, and avoids fabricated empty fields for metrics that do not exist on the current platform.

## Product stance

- Keep a stable shared core where HealthKit and Health Connect expose comparable data with compatible units and meanings.
- Keep platform-native metrics when they represent real user-authorized data, even when the other platform has no equivalent.
- Do not alias metrics with different clinical/product meaning just to make picker counts match.
- Do not emit fake `null`, zero, or empty placeholder fields for unavailable platform data.
- Document platform-only metrics in the Android/iOS parity ledger and keep them selectable only on the platform that can read them.

## Shared cross-platform core

The export contract should continue to align common data such as:

- Sleep summaries and stages where both platforms expose sleep samples.
- Activity basics: steps, distance, calories, exercise minutes, flights, wheelchair/swimming metrics where available.
- Heart and respiratory summaries: heart rate, HRV, respiratory rate, oxygen saturation.
- Vitals and body measurements with comparable quantities: blood pressure, glucose, temperature, weight, height, body fat, BMI, lean mass.
- Nutrition nutrient totals where both APIs expose comparable nutrient quantities.
- Mindfulness session totals.
- Completed workouts and workout detail time series where both APIs expose the source data.

## iOS / HealthKit-native exports

These are valid Health.md iOS exports but should not be treated as Android defects when Health Connect has no equivalent:

| iOS data | iOS metric/schema examples | Android stance |
|---|---|---|
| HealthKit medication catalog and dose events | `medications`, medication dose events, taken/skipped counts | Not equivalent to Android PHR. Health Connect has no HealthKit-style daily medication dose-event catalog. |
| State of Mind / mood | `state_of_mind_entries`, `daily_mood`, `average_valence`, `momentary_emotions` | No standard Health Connect mood/state-of-mind record. Android exports mindfulness sessions only. |
| Apple Watch wrist temperature | `wrist_temperature` | Not equivalent to Android `skin_temperature`; keep separate. |
| Apple activity/ring signals | `stand_time`, `move_time`, `physical_effort` | No matching Health Connect records in the audited API. Android keeps `exercise_minutes` and activity intensity separately. |
| Apple mobility/running dynamics | walking double support/asymmetry/steadiness, six-minute walk, running stride/contact/vertical oscillation | No standard Health Connect equivalents in the audited API. |
| HealthKit hearing and symptom categories | headphone/environmental audio, per-symptom ids | No standard Health Connect equivalents in the audited API. |

## Android / Health Connect-native exports

These are valid Android exports but should not be treated as iOS defects when HealthKit has no equivalent first-class record:

| Android data | Android metric/schema examples | iOS stance |
|---|---|---|
| Activity intensity intervals | `activity_intensity_minutes`, moderate/vigorous totals, intensity entries | iOS has `exercise_time` and `physical_effort`, but not the same Health Connect activity-intensity record. |
| Planned exercise sessions | `planned_workouts`, planned-session title/notes/blocks/steps | iOS exports completed workouts; no matching planned workout export is currently modeled. |
| Menstruation period intervals | `menstruation_periods`, `menstruation_period_days`, period entries | iOS currently exports menstrual flow/spotting/etc.; period intervals are not modeled as the same metric. |
| Personal Health Record / FHIR resources | `medical_resources`, raw FHIR resource metadata/JSON | Not equivalent to HealthKit medication dose events. Treat as Android PHR data. |
| Nutrition meal records | `nutrition_meals`, meal name/type/timing, `energy_from_fat` | iOS nutrition is currently aggregate nutrient quantities; meal records are not modeled. |
| Health Connect contextual fields | glucose meal/specimen context, BP/temp measurement locations, mindfulness/sleep title/notes/source, VO2 max measurement method | iOS may preserve generic HealthKit metadata for some samples, but these are not first-class cross-platform schema fields today. |
| Android skin temperature | `skin_temperature`, baseline and deltas | Not equivalent to Apple Watch `wrist_temperature`; keep separate. |

## Explicit non-equivalences

- **Medications:** iOS HealthKit medication dose events answer “what dose was scheduled/taken/skipped and when?” Android Health Connect PHR resources answer “what clinical/FHIR resource was shared?” These may both include medication-related data, but they are different products and should not be merged under one cross-platform metric.
- **Mood:** iOS State of Mind has HealthKit-defined mood/emotion valence, labels, and associations. Android Health Connect does not expose a comparable mood record.
- **Temperature:** iOS wrist temperature and Android skin temperature deltas/baselines are separate sensor/data models.
- **Reproductive health:** iOS menstrual flow samples and Android menstruation period intervals answer related but different questions and should be exported under their native metric ids.
- **Workouts:** Completed workout sessions are shared-core; planned workouts are Android-native until an iOS equivalent is modeled.
- **Nutrition:** Nutrient totals are shared-core where units match; meal entries and Health Connect `energyFromFat` are Android-native.

## Maintenance rules

1. Add platform-only metrics as `android-only` or `apple-exclusive`/`health-connect-unavailable` in `docs/export-contract/android-ios-metric-parity-ledger.md`.
2. If a platform later exposes a true equivalent, move the metric into the shared/mapped set and update exporters/tests together.
3. Keep feature-gated medical or permission-sensitive data opt-in and documented separately from standard health metrics.
4. Preserve raw/generic metadata when available, but do not depend on metadata keys as stable cross-platform fields unless the export contract promotes them explicitly.
