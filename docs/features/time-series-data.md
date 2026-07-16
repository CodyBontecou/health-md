# Lossless Health Records

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** Export → Lossless Health Records
- **Compatibility key:** `includeGranularData`
- **Source files:** `HealthMd/iOS/Views/ExportTabView.swift`, `HealthMd/Shared/Managers/HealthKitManager.swift`, `HealthMd/Shared/Managers/HealthKitRecordCatalog.swift`, `HealthMd/Shared/Models/HealthKitRecord.swift`, `HealthMd/Shared/Export/HealthKitRecordArchiveSerializer.swift`

## What it does

**Lossless Health Records** keeps every selected public HealthKit source record alongside the existing daily summaries. It preserves exact identity, timestamps, provenance, metadata, values, relationships, diagnostics, and dense series rather than limiting export to a handful of compatibility arrays.

The setting is on by default for new installs. Health.md preserves an explicit off choice from an existing install; off means summary-only output with `raw_capture_status: not_requested`.

The old internal setting name remains `includeGranularData` (persisted as `advancedExportSettings.includeGranularData`) for settings, sync, and API compatibility. User-facing docs and UI call the feature Lossless Health Records.

## Who it is for

- Users building a durable personal HealthKit archive.
- Developers who need exact samples and query diagnostics.
- People reconstructing intraday charts, workouts, correlations, clinical data, or record graphs.
- Users who want individual-entry files tied to real source identity.

Turn it off when concise summaries are sufficient. Lossless exports can be much larger and final serialization can use substantial memory.

## Setup

1. Open **Export**.
2. Leave **Lossless Health Records** enabled.
3. Choose the metrics you want under **Health Metrics**.
4. Select JSON for the complete embedded archive, CSV for canonical JSON rows, and/or Markdown/Bases for summaries plus diagnostics.
5. Export one day first and inspect `raw_capture_status`.

## Format behavior

| Format | Lossless behavior |
|---|---|
| JSON | Embeds authoritative `healthkit_record_archive` (`healthmd.healthkit_records` v1). |
| CSV | Emits the archive manifest and one canonical JSON row per UUID-backed/external record, plus failures and warnings. |
| Markdown | Keeps daily summaries and adds capture counts/diagnostics; does not dump records. |
| Obsidian Bases | Keeps summary properties and lossless counts/status; does not dump records. |
| Individual entries | Derives source-event notes from canonical records whenever an archive exists. |

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
- clinical/FHIR, CDA, verifiable clinical, and vision records;
- attachment metadata and exact available bytes/checksums.

Availability depends on the selected metrics, device/OS, source apps, public API support, and authorization.

## Completeness diagnostics

`raw_capture_status` is one of:

- `complete`: all planned supported branches completed, including valid empty results;
- `partial`: at least one branch failed, was cancelled, skipped, unsupported, or incomplete;
- `not_requested`: the setting was off;
- `legacy_unavailable`: an older stored record or connected peer lacked the archive.

The query manifest distinguishes `success` with zero records from `unsupported`, `skipped`, `cancelled`, and `failure`. Health.md never reports partial capture as complete. Successful sibling records remain available when one child query fails.

## Day ownership and identity

Canonical records belong to the day containing their source start timestamp in the captured timezone. Health.md does not clip records crossing midnight. The sleep summary retains its noon-to-noon compatibility window, so use archive ownership for raw event reconstruction.

Repeated query views merge only by original UUID. External records merge only by documented external identity. Similar values or timestamps remain separate records.

## Special access

Most types use ordinary HealthKit read authorization. Medications and vision prescriptions use per-object selectors; CDA and verifiable records use user-selection queries; WorkoutKit plans use a separate capability path. Unsupported APIs and intentionally skipped authorization appear honestly in the manifest.

HealthKit read privacy can make denied access look like a successful empty query. Health.md cannot distinguish what Apple intentionally hides.

## Exact bytes and practical limits

Canonical JSON base64-encodes exact binary values. Available attachments include SHA-256 checksums. Health.md preserves source URLs but never fetches them.

Current exports are snapshots, not an anchored deletion ledger: they do not include tombstones for records deleted between exports. Health.md uses public APIs only and does not infer sleep schedules, ECG leads, blood-pressure sessions, or other unavailable data.

Connected iPhone/Mac transfer is bounded and checksum validated: chunk data is capped at 512 KiB (transport framing adds encoding overhead), count at 8,192, and declared transfer size at 2 GiB. This fixes the old unbounded whole-payload transport behavior. Capture and final JSON/CSV serialization can still consume substantial memory, so smaller ranges are safer for routes, ECGs, clinical bytes, or attachments.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Only summaries appear | Lossless Health Records is off or source is legacy | Check `raw_capture_status`, enable the setting, and re-export. |
| Archive is complete but empty | The public queries succeeded with no readable records | This can be valid; also review HealthKit permissions. |
| Archive is partial | A requested branch failed/cancelled/skipped/was unsupported | Inspect the query manifest, warnings, and partial failures. |
| Markdown has no raw objects | Markdown intentionally shows summaries and diagnostics only | Export JSON or CSV. |
| Files are very large | Dense series/routes/binary data were retained | Export fewer days or disable lossless capture when summaries suffice. |
| Connected transfer is rejected | Declared size/frame limits or version capability failed | Update both apps and retry a smaller range. |
| Individual entry is missing | Canonical source query did not return that event | Do not rely on a daily average as a replacement; inspect manifest status. |

## Video outline

- **Suggested title:** Create a Lossless Apple Health Archive with Health.md
- **Hook:** “Daily summaries stay readable, while JSON keeps the exact public records behind them.”
- **Demo flow:** compare off/on, inspect a canonical record and query manifest, show Markdown diagnostics, demonstrate exact ownership and a partial child query, then discuss file size.

## Implementation notes

- `ExportTabView` labels `AdvancedExportSettings.includeGranularData` as **Lossless Health Records**.
- `HealthKitRecordCatalog` is the reviewed selection/authorization/dependency graph.
- `HealthKitManager.fetchHealthData(for:includeGranularData:metricSelection:)` keeps summaries unchanged and attaches a `HealthKitRecordArchive` when enabled.
- `SystemHealthStoreAdapter` and its canonical/specialized extensions map public HealthKit/WorkoutKit values.
- `HealthKitRecordArchiveSerializer` owns deterministic public JSON/CSV serialization.
- `ConnectedTransfer` provides bounded, checksum-validated iPhone/Mac transport.
