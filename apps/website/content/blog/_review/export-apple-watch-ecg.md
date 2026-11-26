# Apple Watch ECG export claim verification

Verified: 2026-11-26 by Claude (agent), method: traced.

No device run, no real ECG, no screenshots. Claims traced to repo docs, generated fixtures and Apple pages. The Apple Developer pages could not be read in full by the fetch tool; those claims follow the issue brief's sourcing and are stated at the level the brief gives.

## Claims

- [x] PDF steps (Health → Browse → Heart → Electrocardiograms (ECG) → chart → Export a PDF for Your Doctor → Share to print or share) read from https://support.apple.com/en-us/120278 on 2026-11-26. "One recording at a time" is inferred from tapping a single result's chart.
- [x] HKElectrocardiogram properties and single lead similar to Lead I, read via HKElectrocardiogramQuery: Apple Developer pages listed in the brief; also `SystemHealthStoreAdapter+SpecializedRecords.swift` queries classification, average HR, symptoms status, sampling frequency and voltage measurements.
- [x] ECG is "Source archive only" in `docs-src/src/content/docs/reference/generated/core/metric-catalog.md`; Lossless Health Records is Apple-only (`export.md`, `format.md`); JSON embeds the archive, CSV emits canonical objects as JSON cells (`reference/canonical-healthkit-records.md`); no archive when off (`reference/export-formats.md`).
- [x] JSON sample uses only field names/values from `reference/generated/core/specialized-records.md` ECG fixture (record_kind, object_type_identifier, start_date, payload.kind/type/fields, average_heart_rate, classification, voltage_measurements), shortened and fictional.
- [x] Short date ranges for ECGs: `api-endpoint.md`. Integrity warnings exist (`reference/query-manifests-and-diagnostics.md`); the missing-voltage/count-mismatch examples follow the brief's diagnostics source. ECG lead internals not inferred; empty result can equal denied read access (same diagnostics doc).
- [x] Privacy: local folder export; payloads not pasted into reports (`cli.md` warning); Cloud pilot separate, opt-in, single-owner, not generally available. No medical, accuracy or diagnostic claims.
- [x] XML export: no claim about ECG contents; linked to the existing XML guide.
