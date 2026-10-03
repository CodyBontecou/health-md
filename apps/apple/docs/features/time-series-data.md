# Data Detail and Lossless Health Records

For exact object fields, payload variants, metadata tags, relationships, query results, and complete synthetic files, see the [Canonical Apple Health records reference](../reference/canonical-healthkit-records.md).

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** Export → Data Detail
- **Current settings:** `compatibilityDetail` and `healthKitSourceArchivePolicy`
- **Legacy migration key:** `includeGranularData`
- **Source files:** `HealthMd/iOS/Views/ExportTabView.swift`, `HealthMd/Shared/Managers/HealthKitManager.swift`, `HealthMd/Shared/Managers/HealthKitRecordCatalog.swift`, `HealthMd/Shared/Models/HealthKitRecord.swift`, `HealthMd/Shared/Export/HealthKitRecordArchiveSerializer.swift`

## What it does

**Data Detail** separates readable compatibility time-series from the canonical HealthKit source archive:

- **Summary** exports daily aggregates such as averages, minimums, and maximums.
- **Detailed Time-Series** additionally exports selected timestamped samples such as heart rate, HRV, blood oxygen, respiratory rate, blood pressure, blood glucose, and sleep stages. It does not capture the canonical archive.
- **Lossless Health Records** includes those readable series plus every selected public HealthKit source record, preserving exact identity, timestamps, provenance, metadata, values, relationships, diagnostics, and dense series.

The orthogonal durable policy also supports an archive-only state for automation and future advanced UI. The primary UI intentionally keeps the common choices progressive and simple.

New installs default to Summary. During migration, the historical combined `includeGranularData` value maps `true` to Lossless (time-series plus archive) and `false` or missing to Summary, preserving existing profiles and queued work. Exact new fields take precedence after migration.

> **Current App Store availability:** The Lossless Health Records export mode remains available for ordinary Apple Health samples. Clinical Health Records and Clinical Documents are temporarily excluded from current App Store builds, including authorization, metric selection, direct-query catalogs, and capture. Their schema representation remains reserved for compatibility and a future reviewed release.

## Who it is for

- **Detailed Time-Series:** people building intraday charts or preserving selected timestamped readings without a full source archive.
- **Lossless Health Records:** users building a durable personal HealthKit archive, developers who need exact source identity and query diagnostics, and users who want individual-entry files tied to canonical records.

Choose Summary when concise aggregates are sufficient. Lossless exports can be much larger and final serialization can use substantial memory; Detailed Time-Series is the lighter-weight option for charts and per-sample analysis.

## Setup

1. Open **Export**.
2. Under **Data Detail**, choose Summary, Detailed Time-Series, or Lossless Health Records.
3. Choose the metrics you want under **Health Metrics**; only selected metrics contribute compatible series or source records.
4. For Lossless, select JSON for the complete embedded archive, CSV for canonical JSON rows, and/or Markdown/Bases for summaries plus diagnostics.
5. Export one day first. `raw_capture_status` describes only canonical archive capture; Detailed Time-Series correctly reports `not_requested` while still including sample arrays.

## Format behavior

| Format | Detailed Time-Series | Lossless Health Records |
|---|---|---|
| JSON | Emits existing optional sample arrays in their summary sections. | Also embeds authoritative `healthkit_record_archive` (`healthmd.healthkit_records` v1). |
| CSV | Emits timestamped compatibility sample rows. | Also emits the archive manifest and canonical JSON rows for source records, failures, and warnings. |
| Markdown | Renders readable selected sample tables where supported. | Also adds compact archive counts/diagnostics; it does not dump canonical record JSON. |
| Obsidian Bases | Keeps compatible summary properties. | Also keeps archive counts/status; it does not dump records. |
| Individual entries | May use compatibility samples or aggregate fallbacks. | Derives source-event notes from canonical records whenever an archive exists. |

## What a canonical record preserves

For UUID-backed samples, Health.md keeps:

- original UUID, exact UTC start/end, and `has_undetermined_duration`;
- object type and record kind;
- source revision, bundle, product, OS version, and every public device field;
- recursively typed metadata, including exact integers, quantities, binary data, URLs, arrays, dictionaries, and unknown types;
- exact quantity/category payloads and raw enum values;
- parent/child/dependency relationships;
- direct and dependency metric attribution.

UUID-free public values use honest external identities and omit UUID/provenance fields that HealthKit does not expose.

## Coverage

Current selected-source capture includes:

- all catalogued ordinary quantity and category samples, including reproductive and pregnancy types;
- discrete, cumulative, and series quantities with public statistics/child points;
- blood-pressure and food correlations;
- full workouts, routes/locations, events, activities, statistics, associated samples, effort edges, and WorkoutKit plans;
- ECG waveforms, audiograms, heartbeat series, GAD-7/PHQ-9 assessments, and State of Mind;
- medication inventory and dose events;
- Activity summaries and profile characteristics;
- vision prescriptions;
- attachment metadata and exact available bytes/checksums.

The archive schema can still decode clinical/FHIR, CDA, and verifiable clinical records produced by earlier or future compatible builds. Current App Store builds do not request or capture those types.

Availability depends on the selected metrics, device/OS, source apps, public API support, build capabilities, and authorization.

## Completeness diagnostics

`raw_capture_status` is one of:

- `complete`: all planned supported branches completed, including valid empty results;
- `partial`: at least one branch failed, was cancelled, skipped, unsupported, or incomplete;
- `not_requested`: canonical archive capture was off; Detailed Time-Series may still be present;
- `legacy_unavailable`: an older stored record or connected peer lacked the archive.

The query manifest distinguishes `success` with zero records from `unsupported`, `skipped`, `cancelled`, and `failure`. Health.md never reports partial capture as complete. Successful sibling records remain available when one child query fails.

## Day ownership and identity

Canonical records belong to the day containing their source start timestamp in the captured timezone. Health.md does not clip records crossing midnight. The sleep summary retains its noon-to-noon compatibility window, so use archive ownership for raw event reconstruction.

Repeated query views merge only by original UUID. External records merge only by documented external identity. Similar values or timestamps remain separate records.

## Special access

Most available types use ordinary HealthKit read authorization. Medications and vision prescriptions use per-object selectors, while WorkoutKit plans use a separate capability path. Clinical, CDA, and verifiable-record query implementations remain dormant behind a source gate and are not included in current App Store builds. Unsupported APIs and intentionally skipped authorization appear honestly in the manifest.

HealthKit read privacy can make denied access look like a successful empty query. Health.md cannot distinguish what Apple intentionally hides.

## Exact bytes and practical limits

Canonical JSON base64-encodes exact binary values. Available attachments include SHA-256 checksums. Health.md preserves source URLs but never fetches them.

Current exports are snapshots, not an anchored deletion ledger: they do not include tombstones for records deleted between exports. Health.md uses public APIs only and does not infer sleep schedules, ECG leads, blood-pressure sessions, or other unavailable data.

Current connected iPhone/Mac exports use checksum-chained corpus sessions: 48 MiB default partition targets negotiated within 32–64 MiB, 64 MiB physical maximum, and 512 KiB transport frames. There is no 2 GiB aggregate session cap; older peers retain that legacy single-payload ceiling. iPhone and Mac spool one day/item at a time, though a single dense HealthKit day can still consume substantial capture/encoding memory.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Only summaries appear | Data Detail is set to Summary, the metric is unselected, or the source has no compatible readings | Choose Detailed Time-Series or Lossless, verify the metric selection, and re-export. |
| Archive is complete but empty | The public queries succeeded with no readable records | This can be valid; also review HealthKit permissions. |
| Archive is partial | A requested branch failed/cancelled/skipped/was unsupported | Inspect the query manifest, warnings, and partial failures. |
| Markdown has no raw objects | Markdown intentionally shows summaries and diagnostics only | Export JSON or CSV. |
| Files are very large | The canonical archive retained dense routes, waveforms, metadata, or binary data | Choose Detailed Time-Series instead of Lossless, or export fewer days. |
| Connected transfer is rejected | Declared size/frame limits or version capability failed | Update both apps and retry a smaller range. |
| Individual entry is missing | Canonical source query did not return that event | Do not rely on a daily average as a replacement; inspect manifest status. |

## Video outline

- **Suggested title:** Create a Lossless Apple Health Archive with Health.md
- **Hook:** “Daily summaries stay readable, while JSON keeps the exact public records behind them.”
- **Demo flow:** compare off/on, inspect a canonical record and query manifest, show Markdown diagnostics, demonstrate exact ownership and a partial child query, then discuss file size.

## Implementation notes

- `ExportTabView` presents three presets backed by the orthogonal `AppleExportDetailPolicy`.
- `ExportCompatibilityDetail.selected_time_series` controls compatibility sample queries; `HealthKitSourceArchivePolicy.canonical_v1` independently controls canonical archive capture.
- `HealthKitRecordCatalog` is the reviewed selection/authorization/dependency graph.
- `HealthKitManager.fetchHealthData(for:detailPolicy:metricSelection:)` splits these choices at the HealthKit query boundary, so Detailed Time-Series never invokes archive capture.
- `SystemHealthStoreAdapter` and its canonical/specialized extensions map public HealthKit/WorkoutKit values.
- `HealthKitRecordArchiveSerializer` owns deterministic public JSON/CSV serialization.
- `ConnectedTransfer` provides bounded, checksum-validated iPhone/Mac transport.
