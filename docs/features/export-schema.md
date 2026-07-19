# Export schema contract

Health.md exports are durable public files for Obsidian, scripts, spreadsheets, archives, and downstream automation. The exhaustive user/developer contract, complete generated examples, and field inventories are indexed in the [Health.md export reference](../reference/index.md). JSON, CSV, and Obsidian Bases always identify their schema. Markdown identifies it in frontmatter when the user-controlled **Include Metadata** setting is on (the default); turning that setting off removes the entire Markdown frontmatter block:

- Markdown frontmatter when **Include Metadata** is on, and Obsidian Bases frontmatter:
  ```yaml
  schema: healthmd.health_data
  schema_version: 7
  raw_capture_status: complete
  time_context:
    calendar_timezone: America/Los_Angeles
    timestamp_timezone: UTC
  ```
- JSON:
  ```json
  {
    "schema": "healthmd.health_data",
    "schema_version": 7,
    "raw_capture_status": "complete",
    "time_context": {
      "calendar_timezone": "America/Los_Angeles",
      "timestamp_timezone": "UTC"
    }
  }
  ```
- CSV metadata and diagnostic rows:
  ```csv
  Date,Category,Metric,Value,Unit,Timestamp
  2026-07-15,Metadata,schema,healthmd.health_data,,
  2026-07-15,Metadata,schema_version,7,,
  2026-07-15,Raw HealthKit,Raw Capture Status,complete,status,
  ```

## Version 7 live schema

`schema_version: 7` is the current Health.md daily export contract. Versions 5 and 6 and their signature fixtures remain historical and must not be rewritten.

Version 7 carries forward the complete lossless source representation introduced by v6 and corrects three public summary contracts:

- `vo2_max` is a latest measurement, not a period maximum. Its period headline follows the latest daily source value even when that value is lower than an earlier measurement.
- CSV extended summary categories, including cycling, vitamins, minerals, reproductive health, and other health, populate canonical `Unit` values from the production data dictionary instead of dropping them.
- Roll-up date labels are rendered in the calendar timezone used to build the period, so ISO weekly output labels Monday through Sunday and agrees with its `YYYY-Www` period ID.

**Lossless Health Records is on by default for new installs.** An existing explicit off choice is preserved. Turning it off produces summary-only daily exports and `raw_capture_status: not_requested`; Health.md does not silently turn it back on. The internal compatibility setting and persisted key remain `includeGranularData` and `advancedExportSettings.includeGranularData`.

## Summary and source layers

A v7 daily record has two complementary layers:

1. Existing `sleep`, `activity`, `heart`, `vitals`, `body`, `nutrition`, `mindfulness`, `mobility`, `hearing`, `workouts`, and medication summaries remain convenient for reading, charts, and roll-ups.
2. JSON `healthkit_record_archive` is the authoritative source layer. It uses `schema: healthmd.healthkit_records` and `schema_version: 1`.

The archive is the complete public representation Health.md captured from the selected HealthKit APIs. Downstream tools that need source identity, exact samples, or relationships should read it instead of treating summary arrays as authoritative.

Format roles are intentional:

- **JSON** embeds the full archive.
- **CSV** writes the same canonical objects as RFC 4180-safe JSON rows: `Archive Manifest`, `Raw HealthKit Record`, `Raw HealthKit External Record`, query failures, warnings, and partial failures. Canonical JSON and CSV record UUIDs must match.
- **Markdown and Obsidian Bases** keep daily summaries readable and do not dump the archive. Their shared frontmatter exposes capture status, source-record count, failed-query count, warning count, and archive schema. Markdown additionally renders external-record, query-status, and medication-inventory counts in its compact diagnostics section.
- **Individual Entry Tracking** derives source-event files from canonical records whenever an archive is present. Compatibility summaries are not substituted for a failed or empty canonical query.

## Canonical archive contract

Each UUID-backed HealthKit record preserves, when the public API provides it:

- original HealthKit UUID, object-type identifier, and record kind;
- exact UTC start and end timestamps plus `has_undetermined_duration`;
- source name, bundle identifier, version, product type, and operating-system major/minor/patch;
- every public `HKDevice` field;
- recursively typed metadata, including null, string, Boolean, signed and unsigned integers, floating point, date, binary data, URL, quantity, array, dictionary, and an explicit unsupported-value description;
- exact quantity values and canonical units, quantity sample subclass/kind, count, min/average/max/most-recent/sum statistics, and series children with owning-sample identity;
- category raw values and known symbolic values without discarding unknown raws;
- structured payloads, binary references, and unknown future payload kinds;
- UUID and external-identity relationships, including cross-day owner hints;
- direct/dependency metric attribution and the reason the object was retained.

The archive also includes:

- deterministic daily ownership metadata;
- a query manifest with operation, type, selected metrics, interval, status, record count, and safe error details;
- integrity warnings;
- medication inventory records;
- UUID-free `external_records` for public values that are not `HKObject`s.

Health.md never fabricates an HKObject UUID, source revision, or device for an external value. Activity summaries, profile characteristics, attachments, and WorkoutKit schedules use only their public external identity. Clinical records preserve the public `HKClinicalRecord` UUID but label its documented instability; when FHIR identity fields are available, a separate stable content identity is included and does not disguise the unstable UUID.

## Capture and query completeness

Top-level `raw_capture_status` and archive `capture_status` use these values:

| Status | Meaning |
|---|---|
| `complete` | Every planned, supported request completed without a failed, cancelled, skipped, or unsupported branch. A complete archive may contain zero records. |
| `partial` | At least one requested branch failed, was cancelled, skipped, unsupported, or otherwise could not be captured. Retained siblings remain valid. |
| `not_requested` | Lossless Health Records was explicitly off for this export. No archive is present. |
| `legacy_unavailable` | The record came from an older app/peer that could not provide the archive. |

Query-manifest status is separate:

- `success` with `record_count: 0` means a successful empty query;
- `unsupported` means the API or capability is unavailable on this runtime;
- `skipped` means Health.md intentionally did not query, commonly because separate authorization was not granted;
- `cancelled` records user or request cancellation;
- `failure` includes a structured error.

No partial capture may be labeled complete. Errors are isolated where possible: one failed waveform, attachment, route, or specialized query does not discard successful sibling records.

HealthKit protects read privacy. For many types, a denied read can be indistinguishable from a successful empty result. Health.md reports what the public API returns; it cannot override that privacy behavior.

## Day ownership and deduplication

Canonical source records use one strict rule: a record belongs to the captured calendar day when its **source start date** falls in that day's half-open interval in the captured IANA timezone. Raw start/end timestamps are never clipped to day boundaries, even when a record spans midnight.

This differs from the established sleep compatibility summary. Daily sleep summaries retain their noon-to-noon journaling behavior so an evening sleep session remains attached to the night users expect. Consumers reconstructing raw events must use archive ownership, not infer ownership from the summary window.

Repeated query views are merged only by the same original UUID. UUID-free public values are merged only by the same documented external identity. Similar values, timestamps, or payloads are never enough to deduplicate distinct records.

## Public coverage

Subject to the selected metrics, runtime API availability, and authorization, v7 source capture covers:

- all currently catalogued ordinary quantity and category types, including reproductive and pregnancy types;
- discrete, cumulative, and series quantity samples with exact public statistics and child points;
- category values with raw and known symbolic values;
- blood-pressure and food correlations with their component graph;
- full workouts, routes and locations, events, activities, all public statistics, associated quantity/category/specialized samples, effort relationships, and attached or scheduled WorkoutKit plans;
- ECG waveforms, audiograms, heartbeat series, GAD-7/PHQ-9 scored assessments, and State of Mind;
- medication inventory and dose events;
- Activity summaries and profile characteristics;
- clinical/FHIR records, CDA documents, verifiable clinical records, and vision prescriptions;
- attachment metadata and exact available attachment bytes.

This is public-API completeness, not access to Apple's private database. Health.md does not infer unavailable sleep schedules, alarms, ECG leads, measurement sessions, or other private fields.

## Special authorization and capability behavior

Most selected HealthKit types use the normal read-authorization flow. Some types behave differently:

- medications and vision prescriptions use Apple's per-object selectors and are opt-in;
- CDA documents and verifiable clinical records use user-selection queries that may be cancelled;
- WorkoutKit schedules use a separate read-only capability path with no HealthKit authorization prompt;
- unavailable runtime APIs are `unsupported`; deliberately unrequested special access is `skipped` rather than a false successful-empty result.

Metric selection controls both direct records and required relationship dependencies. Archive records retain direct/dependency attribution so selecting Workouts, blood pressure, or food does not silently claim every child type as a directly selected metric.

## Exact binary data and URLs

Binary metadata, FHIR JSON, CDA bytes, verifiable records, WorkoutKit representations, and available attachments are base64 encoded by canonical JSON. Attachment records include exact byte availability and SHA-256 checksums when bytes were read. An empty available attachment has the checksum of empty data; unavailable bytes do not get a fabricated checksum.

Source URLs are preserved as strings. Health.md never fetches them, follows them, or treats remote content as captured data.

## Summary correctness notes

- Blood-pressure summaries retain daily average/minimum/maximum values. The canonical archive contains actual correlation pairs and Health.md does not infer sessions or average nearby readings.
- VO2 Max may use the latest historical measurement through the end of the requested day. Its UUID, source start/end, carry-forward flag, and age are exported so it cannot masquerade as an in-day reading. The v7 dictionary labels `vo2_max` as `latest`; weekly/monthly/yearly headline values select the latest daily value rather than the largest value.
- **Stand Time** is summed duration in minutes from `HKQuantityTypeIdentifierAppleStandTime`. **Stand Hours** is the count of distinct stood hours from Apple Stand Hour category records. They are not interchangeable.
- Vitamin/mineral summaries and the v7 data dictionary label microgram values `µg`; milligram summaries use `mg`. Canonical HealthKit quantity payloads preserve the reviewed HealthKit query unit string (`mcg` for those microgram source types).

## Time and unit contract

`time_context.calendar_timezone` is the captured IANA timezone used for daily boundaries and human-readable clock fields. `time_context.timestamp_timezone` is always `UTC`. Complete source timestamps use RFC 3339 UTC with a fixed nine-digit fractional component in canonical rows. `HKTimeZone` metadata remains source metadata and may differ during travel.

Structured summary data uses stable canonical units regardless of Metric/Imperial display preference:

- frontmatter/Bases and JSON use the `units` map;
- CSV uses the `Unit` column, including data-dictionary units for extended cycling, vitamin, mineral, reproductive, and other summary rows;
- distance keys with explicit suffixes identify their own units;
- Markdown prose may use the selected display units;
- Markdown has no machine-readable schema or `units` map when **Include Metadata** is off.

See [Date, Time, and Units](./date-time-units.md) and [Data Dictionary and Roll-up Rules](./data-dictionary.md).

## API Endpoint envelope

API Endpoint export wraps ordinary v7 daily records in `healthmd.api_export`. The daily record version is declared by `daily_record_schema_version`; each `records` item still contains its own schema/version and archive. Provider-specific sidecars can independently advance the API envelope version without changing `healthmd.health_data`.

## Practical limits

- Health.md can preserve only data exposed by public HealthKit and WorkoutKit APIs on the running OS.
- Current exports are snapshots. They do not include historical deletion tombstones from earlier snapshots.
- Lossless files can be large, especially with routes, ECG voltage measurements, series, FHIR/CDA data, or attachments.
- Current connected iPhone/Mac jobs use stable checksum-chained corpus sessions with 32–64 MiB partitions (48 MiB default), a 64 MiB independently decoded item cap, and 512 KiB frames. Aggregate sessions can exceed 2 GiB; mixed-version peers retain the legacy 2 GiB single-payload cap. These are transport changes only and do not change daily export schema keys or versions.
- API Endpoint exports use sequential batches bounded by 7 calendar days and an 8 MiB encoded-body target by default. A single daily record is indivisible and can exceed that target; the API envelope and daily schemas are unchanged.
- HealthKit capture and final JSON/CSV serialization can still use substantial memory. Export smaller date ranges when working with dense records or attachments.

## Migrating from v5 or v6

Existing v5 and v6 files remain valid historical exports. Do not relabel them as v7. Re-export v6 periods when consumers need the corrected VO2 Max `latest` rule, populated extended-category CSV units, or calendar-timezone-correct roll-up date labels; v6 dictionaries described `vo2_max` as a maximum.

For a consistent archive, update Health.md and its Obsidian integration, then re-export the dates you need. Re-exporting is especially important when downstream tools need canonical source records, corrected day ownership, exact quantities, VO2 provenance and roll-ups, Stand Time/Stand Hours separation, or corrected micronutrient units.

Downstream parser guidance:

1. Branch on top-level `schema` and `schema_version`; accept v5, v6, and v7 during migration.
2. Treat summary objects as convenient projections, not source-event identity.
3. In v6 and v7, inspect `raw_capture_status` before deciding whether an archive should exist.
4. Parse `healthkit_record_archive.schema` and its independent `schema_version`.
5. Treat typed metadata as tagged values; preserve unknown tags and raw enum values.
6. Use UUID/external identity for deduplication and `ownership.owner_date` for raw day assignment.
7. Check every query result and diagnostic. Never interpret `partial` as complete or missing fields as zero.
8. Use CSV canonical JSON rows without lossy cell parsing; RFC 4180 fields may contain commas, quotes, and newlines.

## Schema version policy and guardrail

`HealthMdExportSchema.version` is the production daily schema integer. Version 7 is current; versions 1 through 6 are historical. The committed v5 and v6 signatures remain preserved; v7 has its own versioned fixture.

Bump the daily schema when a public key, type, meaning, unit, aggregation, JSON structure, CSV contract, reserved frontmatter field, or downstream dictionary rule changes. Do not bump for byte-compatible internal refactors.

`HealthMdTests/Export/ExportSchemaSignatureTests.swift` fingerprints JSON paths, CSV rows/headers, Markdown/Bases frontmatter, and the data dictionary. A shipped version's fixture must never be rewritten merely to silence CI.

## Intentional schema change workflow

1. Change the exporter or metric mapping.
2. Decide whether the public schema changed.
3. If it changed, bump `HealthMdExportSchema.version`.
4. Run `make update-export-schema-signature`.
5. Review the new versioned fixture; do not overwrite a shipped fixture.
6. Run exporter contract tests and a mixed v5/v6/v7 export smoke test.

A release smoke test should cover local iPhone, API, and Connected Mac outputs; summary-only and lossless settings; Markdown/Bases readability; canonical JSON/CSV parity; and an updated downstream Obsidian parser.
