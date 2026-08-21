# Clinician Report V1 architecture

## Product boundary

Clinician Report is an interactive, patient-controlled document workflow. It reads already-authorized health data, builds a descriptive report model in memory, renders a PDF on the device, and shares only after an explicit user action. It does not use Health.md networking, scheduled exports, API destinations, direct-device transport, analytics payloads, diagnostic thresholds, risk scores, or clinical interpretation.

The report is a first-class option on the existing Export screen, but it is **not** another `ExportFormat`. Existing formats are durable daily export contracts with scheduling, destination, and schema-version behavior. Treating PDF as one of those formats would incorrectly couple this one-report-per-range workflow to the public Apple v7 / Android v4-v5 daily schemas and recurring export machinery.

The footer link to `healthmd.app/practice` is informational only. Clinician Report does not issue or accept a Health.md Practice request, use the Practice common-instruction or practice-variant versions, capture an acceptance-time request timezone, create a Practice packet, upload to a clinician tenant, or establish Practice `opened`/`acknowledged`/`reviewed` facts. Its internal PDF/report model must not be used as evidence that the separately governed Practice protocol or mobile contract is implemented or qualified.

## Existing seams

- Apple capture stays in `HealthKitManager.fetchHealthData(for:includeGranularData:metricSelection:timeZone:)`. Report reads request only the selected report metrics, pin the current timezone for the operation, and request granular data so canonical HealthKit record provenance and trustworthy blood-pressure correlation membership remain available.
- Android capture stays behind `HealthRepository.fetchHealthDataRange(..., includeGranularData = true, pinnedCalendarDays = true)`. Health Connect period aggregation accepts local date-times but cannot take the report's pinned `ZoneId`, so report mode skips period aggregates for activity, heart, vitals, and body. Instant-filtered granular reads supply resting heart rate, heart/vital readings, paired blood pressure, and latest daily weight; steps use a deduplicating `AggregateRequest` for each exact half-open zoned local day, including 23/25-hour DST days.
- Existing `UnitConverter` implementations remain the only weight/temperature/distance conversion authority. Report code may add report-specific glucose presentation because the current product has no glucose unit preference or converter.
- Existing export date controls are not mutated. Clinician Report owns an ephemeral 7/30/90/custom configuration because its presets and one-document semantics differ from daily exports.

## Layers

Each platform keeps four explicit layers with matching concepts:

1. **Configuration** — inclusive local-calendar start/end dates, selected report metrics, detail level, unit preference, and optional patient-entered display name. The name is ephemeral in V1 and is not persisted.
2. **Report data source** — adapts existing HealthKit / Health Connect capture models into report readings. It never queries from UI or renderer code.
3. **Normalized report model and generator** — `ClinicianReportData`, metric summaries, facts, source labels, missingness disclosure, and optional tabular readings. The model contains presentation-ready text plus structured rows, but no PDF APIs.
4. **Native PDF renderer** — UIKit/Core Graphics on Apple and PDFBox-Android on Android. Renderers consume only the normalized report model, paginate tables, and know nothing about HealthKit or Health Connect. Apple drives Core Graphics' native tagged-PDF API from the presentation-ready model. Android uses PDFBox's low-level logical-structure APIs because the platform `android.graphics.pdf.PdfDocument` canvas cannot author marked content, a structure tree, or a parent tree.

This separation allows a future HTML renderer, print renderer, or versioned interchange adapter to consume the same normalized report without reimplementing aggregation. The V1 model is internal and must not be presented as a FHIR or EHR contract.

## Implemented surfaces

- Android domain and aggregation: `domain/clinicianreport/ClinicianReportModels.kt`, `ClinicianReportGenerator.kt`, and `ClinicianReportCopy.kt`.
- Android capture, PDF, and lifecycle: `data/clinicianreport/`, `presentation/clinicianreport/`, the restricted clinician-report `FileProvider`, and a Settings-screen navigation entry. Android report/UI/document vocabulary is explicit for `en`, `ar`, `bn`, `zh-Hans`, `de`, `es`, `fr`, `hi`, `ja`, `kk`, `nl`, `pa-Guru`, `pt-BR`, `ro`, `ru`, and `uk`; the 152-key manifest covers workflow/document copy, all 42 normalized Android workout types, and the respiratory-rate unit.
- Apple domain and capture: `HealthMd/Shared/ClinicianReport/`, using a report-specific `MetricSelectionState` and sequential, timezone-pinned `HealthKitManager` fetches.
- Apple PDF and workflow: `HealthMd/iOS/ClinicianReport/`, presented as a Settings-tab sheet. UIKit-only files are excluded from the synchronized macOS target. Apple report/UI/document vocabulary is resource-backed for `en`, `de`, `es`, `fr`, `it`, `ja`, `ko`, `nl`, `pt-BR`, and `zh-Hans`; one locale is snapshotted for capture warnings, normalization, preview, PDF layout, metadata, and tags.
- Both preview surfaces consume the same immutable normalized report value later passed to their native PDF renderer. Report configuration, including display name, is not persisted or added to export history.

## V1 metric rules

| Metric | Summary rules | Individual readings | Provenance |
| --- | --- | --- | --- |
| Blood pressure | reading count, data days, coverage, mean systolic/diastolic, component ranges, latest pair | timestamp, paired systolic/diastolic, source | only trustworthy native correlation/record pairs; no timestamp heuristic |
| Resting heart rate | data days, coverage, median, range, latest | daily values when exact samples are unavailable | source only when retained by capture |
| Heart rate | reading count, data days, median, range, latest | timestamp/value/source | source record/package when available |
| Weight | daily value count, data days, first, latest, change | daily values | source only when retained by capture; otherwise omitted |
| Blood glucose | reading count, data days, median, range, latest | timestamp/value/source | source record/package when available |
| Oxygen saturation | reading count, data days, median, range, latest | timestamp/value/source | source record/package when available |
| Respiratory rate | reading count, data days, median, range, latest | timestamp/value/source | source record/package when available |
| Body temperature | reading count, data days, median, range, latest | timestamp/value/source | source record/package when available |
| Sleep duration | nights with data, coverage, median duration | session/day duration | source when retained; sessions crossing midnight belong to the existing platform day convention |
| Steps | days with data, coverage, total, daily average | daily totals | source omitted for multi-device aggregate totals unless capture provides trustworthy attribution |
| Workouts | session count, total duration, breakdown by type | start, type, duration, source | workout source when available |

The expected-day denominator is the inclusive count of local calendar dates in the requested range. “No data” never means the event did not occur; report copy says only that no data was available to Health.md for the selected period.

## Range, time, identity, and deduplication

- Normalize the requested range to local calendar days and use a half-open instant interval `[start-of-first-day, start-of-day-after-last-day)` for samples.
- Group coverage with the same pinned timezone used for report generation, including across DST transitions.
- Include samples exactly at the lower bound and exclude samples exactly at the upper bound.
- Deduplicate only with stable source identity (HealthKit UUID / Health Connect identity) where available. Do not drop separate records merely because values and timestamps match.
- Apple blood pressure is emitted only from a blood-pressure correlation and its referenced systolic/diastolic components. Android uses the already-paired `BloodPressureSample` produced from one `BloodPressureRecord`.

## Privacy and lifecycle

All reads, normalization, preview, PDF rendering, and temporary-file handling are local. V1 adds no report upload, background job, clinician account, recipient workflow, export-history entry, or health-valued analytics. Sharing or saving begins only from an explicit user action. Once preparation or PDF rendering starts, the operation owns an immutable configuration snapshot: configuration stays readable and scrollable but its controls and ViewModel mutation paths remain disabled until success, failure, or explicit cancellation, while Apple Close and Android Back cancel and exit without confirmation. Android share/save suggestions use the locale-neutral filename form `<localized-title>_<ISO-start>_<ISO-end>.pdf`; the ephemeral display name is never included.

Apple writes each report into a private owner directory with `0700` directory and `0600` file permissions. A reference-owned artifact lease remains alive through `UIActivityViewController` and removes the temporary file when ownership ends. Android writes under the narrowly granted `cacheDir/clinician-reports` path. Unshared or superseded partial artifacts are deleted; the Android PDF writer polls the request-generation continuation callback before and after setup, during every page transition and report section, for every table row and text-raster path, before footer/final structure serialization, and around `PDDocument.save`. Cancellation throws without publishing and the file store removes the partial file. A completed Android file is published by same-directory atomic rename, never by exposing a partially copied `.pdf`; generation, deletion, and explicit save-copy operations share one store lock so cache cleanup cannot remove the private source during a save. A PDF exposed through `ACTION_SEND` is still retained until a later generation/cache cleanup so an external consumer does not lose its granted URI before opening it. The footer practice URL is isolated behind a report-copy constant.

## Contract/version decision

Clinician Report does not alter Apple export schema v7, Android frozen v4 or analytical v5, the shared metric registry, direct protocol, or any interoperability fixture. Therefore no public schema or protocol version bump is required. Report models are internal application models and PDF bytes are user-facing documents, not Health.md machine-export contracts.

## Validation status

Synthetic tests cover range normalization, DST day length and half-open boundaries, empty reports, median/means, stable-ID versus identity-less deduplication, daily aggregate semantics, units, strict blood-pressure pairing, manual/missing provenance, stale preview races, cancellation, cache cleanup, and large tables.

Available validation completed on the Linux implementation host:

- Android focused clinician-report/timezone suite: 40 tests discovered—39 passed and the property-gated dense tagged-renderer benchmark was intentionally skipped. The suite covers Linux PDFBox generation and semantic parsing, exact MCID-to-ParentTree/MCR ownership, hierarchy and repeated headers, footer coordinates, complex scripts, pinned-zone capture/clamping, effective filename ranges, cancellation cleanup, and packaged dependency attribution.
- Android full unit suite: 892 tests discovered—891 passed and the same property-gated renderer benchmark was intentionally skipped; the suite includes the focused tests above.
- Android `lintDebug`, `assembleDebug`, and `compileDebugAndroidTestKotlin` pass with `:healthmd-core:prepareRustDebug` excluded because NDK `27.1.12297006` is unavailable.
- Android release R8/minification and `assembleRelease` pass with only the two exact safe optional JPEG 2000 suppressions (`com.gemalto.jp2.JP2Decoder` and `JP2Encoder`). PDFBox-Android's packaged consumer rules retain reflected security handlers and `pdmodel.documentinterchange` classes. A synthetic one-day smoke keystore was used only to exercise packaging on Linux; the resulting test artifact is not a release-signing qualification. The smoke release APK is 14,509,401 bytes.
- Repository contract validator: 10 contracts, 14 fixtures, 7 packaging mirrors, 2 inventories, 3 output profiles, and 24 product capabilities validated.
- Protected-file diff: no Apple export schema, Android export profile, contract fixture, shared Rust/UniFFI, metric-registry, or direct-protocol file changed.

The Apple string catalog is Linux-validated against a reviewed 194-key manifest: all ten supported locales must have an explicit translated value and exact positional-placeholder parity. The Android resource validator independently enforces exactly 152 report keys across all 16 Android locales, exact placeholder parity, no orphan report resources, and a one-to-one mapping for all 42 Android `WorkoutType` cases. Android Robolectric localization tests exercise Arabic, Bengali, Hindi, Gurmukhi Punjabi, Simplified Chinese, Japanese, Kazakh, Romanian, Russian, Ukrainian, German, and Brazilian Portuguese, including unsupported-locale English resolution, RTL, warnings, provenance, units, dates, and numbers.

Android's Linux renderer tests generate and parse real multipage Letter and A4 output. They verify `/StructTreeRoot`, `/MarkInfo`, Catalog `/Lang`, display-title preference, Info/XMP metadata, page `/StructParents`, balanced `BDC`/`EMC`, real `/Artifact` marked content absent from the structure tree, embedded Geist fonts, and ordered Document/Sect/H1/H2/H3/P/Table/TR/TH/TD roles. Every semantic BDC property-list MCID is resolved to the exact slot in that page's ParentTree array; that exact structure element must own one MCR with matching `/Pg` and `/MCID`, and every semantic slot is referenced once. Tests also enforce table/TR/TH/TD hierarchy, unmixed header/data rows, repeated header order across page continuations, a footer divider exactly 38 points above the physical bottom, and complex-script image appearance with localized `/ActualText`. No `pdfuaid` is emitted and no PDF/UA claim is made. The normalized dense generator benchmark ran nine measured iterations after three warmups for the exact 90-day, 12,960-heart-reading, 13,950-table-row, 11-section synthetic input: 93.696 ms minimum and 114.368 ms median. The property-gated tagged renderer generated the same report three times on Linux: 336 pages, 20,069,223 bytes, 3,965.411 ms minimum and 4,587.764 ms median. Both are diagnostic only and enforce no timing threshold.

Not run on this host: execution of the compiled Android device PDF instrumentation test, iOS/macOS compilation and tests, iOS simulator UI tests, native share-to-Files/chooser journeys, and manual Letter/A4 artifact inspection. Apple tag serialization and assistive-technology behavior therefore still require simulator/device validation. PDF byte-for-byte snapshots are intentionally avoided because native PDF metadata and fonts are not stable.

## Completion audit

| Objective contract | Concrete evidence | Final status |
| --- | --- | --- |
| Standalone, local-first workflow with exactly 11 metrics, inclusive 7/30/90/custom ranges, two detail levels, and ephemeral display name | Platform configuration/models, capture adapters, generator tests, navigation/UI tests, private artifact stores | Verified on Android; Apple implementation statically reviewed on Linux |
| Descriptive facts only, conservative pairing/provenance/deduplication, existing converters, glucose `mg/dL` | Generator/adapter tests and the metric-rules table above | Verified |
| Complete platform-locale vocabulary with no report fallback | Android 152-key × 16-locale validator; Apple 194-key × 10-locale validator; locale/workout/unit/placeholder tests; locale-neutral filenames | Verified |
| Genuine tagged PDFs rather than metadata-only claims | Android parsed MCID/ParentTree/MCR/hierarchy/artifact tests; Apple Core Graphics tag-stack implementation and structural tests; no `pdfuaid` | Android verified on Linux; Apple static-only pending Apple-host execution |
| One Android `ZoneId` through range filtering and grouping | Repository/provider flag forwarding; pinned granular grouping; exact per-day steps aggregation; Pacific/Chatham 23/25-hour and non-default-zone tests | Verified |
| Dense deterministic 90-day Linux benchmark | Exact 90 days, 12,960 HR readings, 13,950 rows, 11 sections; nine generator and three tagged-renderer measurements with structural assertions and no timing threshold | Verified |
| Local privacy, cancellation, temporary-file safety, explicit share/save | No report networking/analytics; private directories; cancellation tokens; Android atomic publish/save lock; Apple lease ownership; explicit UI actions | Verified in automated/static scope; native journeys remain device-only |
| Public contracts remain unchanged | Contract validator plus protected-path diff audit | Verified |

No missing code-semantic deliverable remains under the stated Linux boundary. The native Apple and Android assistive-technology, viewer, print, and share/save checks listed below remain validation receipts rather than unimplemented feature work.

## Known V1 limitations

- Existing daily aggregate fields can lose exact source identity for some metrics (notably daily weight and resting heart rate on Android). The report omits unsupported source claims rather than guessing.
- HealthKit can make a denied read indistinguishable from a successful empty query. Apple copy therefore describes data as unavailable to Health.md rather than claiming a measurement did not occur.
- Android report capture forwards the report's pinned timezone through the repository/provider boundary. Because Health Connect's period-group request has no `ZoneId`, report mode does not use it for activity, heart, vitals, or body: granular records are grouped from pinned instants, and steps are aggregated over each exact zoned local-day instant range. Legacy non-report callers retain period aggregation and the system-default API fallback.
- Pulse is not joined to blood pressure unless the source model provides a trustworthy association; current normalized models do not, so the V1 blood-pressure table omits pulse.
- Glucose is explicitly `mg/dL` only in V1.
- Android uses Apache-2.0 `com.tom-roush:pdfbox-android:2.0.27.0`, the latest Maven Central release, solely for on-device PDF authoring. Its exact Apache 2.0 license, upstream PDFBox/PDFBox-Android NOTICE, repository/version attribution, and non-endorsement statement are packaged under `assets/licenses/` and verified through the packaged asset API. Its obsolete Bouncy Castle transitives are excluded because the existing direct-protocol workspace already supplies current `bcprov-jdk18on`. The app does not accept external PDFs through this feature and performs no report networking.
- Android PDFs contain a genuine logical structure tree and page marked content. Geist is subset-embedded for covered scripts. Arabic, Indic, and CJK strings are shaped with Android's system fallback into cached text-only images whose semantic element carries the exact localized `/ActualText` and MCID. Footer, rules, and shading are `/Artifact` content absent from the logical tree. RTL reports position logical first columns on the right while retaining deterministic structure order. This is tagged PDF, not a PDF/UA conformance claim.
- Apple PDFs use genuine Core Graphics logical tags in deterministic draw order: Document, sections, H1/H2/H3, paragraphs, Table, TR, TH, and TD. Localized title/subject/keywords are written to the PDF Info dictionary; localized title, description, language, keywords, and creator are also written as XMP; the document structure carries its resolved supported language. At page transitions, active child semantics are closed before the prior-page footer and reopened as continuation siblings on the next page, so marked content never crosses a page boundary and the footer's empty-ActualText `NonStruct` node remains directly beneath Document. Dividers and table shading create no separate logical nodes. This implementation is described only as tagged PDF—not PDF/UA—and needs emitted-file, screen-reader, and human reading-order review on supported Apple OS versions.
- Android tagged structure, metadata, multilingual fallback, and dense rendering are verified under Robolectric/PDFBox on Linux, but TalkBack/PDF-viewer reading order, physical-device memory/performance, print fidelity, and manual Letter/A4/share/save journeys still require device review. The compiled instrumentation smoke test remains the native `PdfRenderer` check.
- PDF/UA is not claimed on either platform. Formal conformance would require a pinned PDF/UA validator profile plus the Matterhorn human checks, including assistive-technology review; structure-tree presence alone is not treated as conformance.
- The normalized model is conceptually aligned across platforms but is not a versioned shared-Rust interchange contract. Moving aggregation into Rust should happen only with coarse FFI inputs/results and differential fixtures, not by changing public export schemas.
