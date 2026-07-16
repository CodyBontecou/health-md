# Individual entry filename and path matrix

All paths below were generated with the production `IndividualTrackingSettings.folderPath`, `IndividualEntryExporter.filename`, and file export collision resolver. Dates and UUIDs are fixed synthetic fixtures in UTC.

## Canonical UUID-backed paths

| Fixture | Metric | Generated relative path | Identity behavior |
|---|---|---|---|
| canonical quantity | `weight` | `entries/body_measurements/2026_07_14_0915_weight_weight_71000000-0000-0000-0000-000000000001.md` | UUID suffix from canonical source identity |
| canonical category | `symptom_headache` | `entries/symptoms/2026_07_14_0916_symptom_headache_symptom_headache_71000000-0000-0000-0000-000000000002.md` | UUID suffix from canonical source identity |
| canonical State of Mind | `state_of_mind_entries` | `entries/mindfulness/2026_07_14_0917_state_of_mind_entries_state_of_mind_entries_71000000-0000-0000-0000-000000000003.md` | UUID suffix from canonical source identity |
| canonical blood-pressure correlation | `blood_pressure` | `entries/vitals/2026_07_14_0918_blood_pressure_blood_pressure_71000000-0000-0000-0000-000000000004.md` | UUID suffix from canonical source identity |
| canonical medication dose | `medications` | `entries/medications/2026_07_14_0919_medications_medications_71000000-0000-0000-0000-000000000007.md` | UUID suffix from canonical source identity |
| canonical workout | `workouts` | `entries/workouts/2026_07_14_0920_workouts_workouts_71000000-0000-0000-0000-000000000008.md` | UUID suffix from canonical source identity |

Canonical filenames always include the lowercased original HealthKit UUID. Re-exporting the same canonical record therefore resolves to the same path, and distinct records in the same minute remain distinct without order-dependent suffixes.

## UUID-free compatibility collisions

| Fixture | Metric | Filename requested for every sample | Resolved relative path | Collision behavior |
|---|---|---|---|---|
| legacy compatibility collision | `blood_glucose` | `entries/vitals/2026_07_14_0915_blood_glucose.md` | `entries/vitals/2026_07_14_0915_blood_glucose.md` | base path reserved by the first sample |
| legacy compatibility collision | `blood_glucose` | `entries/vitals/2026_07_14_0915_blood_glucose.md` | `entries/vitals/2026_07_14_0915_blood_glucose_15000.md` | seconds and milliseconds suffix resolves the same-minute collision |
| legacy compatibility collision | `blood_glucose` | `entries/vitals/2026_07_14_0915_blood_glucose.md` | `entries/vitals/2026_07_14_0915_blood_glucose_15000_2.md` | numeric suffix resolves an identical timestamp suffix collision |

UUID-free compatibility entries keep the configured minute-precision base filename for the first sample. Later collisions receive the production seconds-and-milliseconds suffix, followed by a numeric suffix only when that suffix is also reserved during the export run.
