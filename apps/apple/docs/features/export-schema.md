# Export schema contract

Health.md exports are durable public files for Obsidian, scripts, spreadsheets, archives, and downstream automation. The exhaustive user/developer contract, complete generated examples, and field inventories are indexed in the [Health.md export reference](../reference/index.md). JSON, CSV, and Obsidian Bases always identify their schema. Markdown identifies it in frontmatter when the user-controlled **Include Metadata** setting is on (the default); turning that setting off removes the entire Markdown frontmatter block:

- Markdown frontmatter when **Include Metadata** is on, and Obsidian Bases frontmatter:
  ```yaml
  schema: healthmd.health_data
  schema_version: 8
  raw_capture_status: complete
  time_context:
    calendar_timezone: America/Los_Angeles
    timestamp_timezone: UTC
  ```
- JSON:
  ```json
  {
    "schema": "healthmd.health_data",
    "schema_version": 8,
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
  2026-07-15,Metadata,schema_version,8,,
  2026-07-15,Raw HealthKit,Raw Capture Status,complete,status,
  ```

## Version 8 live schema

`schema_version: 8` is the current Health.md daily export contract. Versions 5, 6, and 7 and their signature fixtures remain historical and must not be rewritten.

Version 8 replaces weekly/monthly/yearly roll-up files with a single range summary per export:

- The roll-up period is `range`. Exactly one `healthmd.rollup_summary` file per format covers the requested export range, first selected day through last selected day.
- `period_id` is `<start>_to_<end>` (for example `2026-03-10_to_2026-03-15`), and files live under `Rollups/Range/`.
- `days_expected` is the inclusive day span of the requested range, so `coverage_percent` reflects the selection rather than a calendar expectation.
- Daily `healthmd.health_data` content is unchanged apart from the version label. Consumers of weekly/monthly/yearly files must regenerate summaries as ranges or pin to historical v7 files.

Version 8 carries forward the complete lossless source representation and the v7 summary corrections:

- `vo2_max` is a latest measurement, not a period maximum. Its period headline follows the latest daily source value even when that value is lower than an earlier measurement.
- CSV extended summary categories, including cycling, vitamins, minerals, reproductive health, and other health, populate canonical `Unit` values from the production data dictionary instead of dropping them.
- Roll-up date labels are rendered in the calendar timezone used to build the period, so range summaries label their first and last selected days in that timezone.

**Lossless Health Records is off by default for new installs.** Existing explicit on or off choices are preserved. The default summary-only daily export reports `raw_capture_status: not_requested`; enabling Lossless adds the canonical source archive. The internal compatibility setting and persisted key remain `includeGranularData` and `advancedExportSettings.includeGranularData`.

Clinical Health Records access is temporarily absent from current App Store builds. Those builds omit the managed entitlements, privacy prompt, metric-selection categories, direct-query catalog entries, and clinical capture. The v7 schema retains its clinical/FHIR/CDA/verifiable variants so historical files stay decodable and the capability can return in a future schema-compatible release.

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

Health.md never fabricates an HKObject UUID, source revision, or device for an external value. Activity summaries, profile characteristics, attachments, and WorkoutKit schedules use only their public external identity. For historical or future compatible clinical records, the schema preserves the public `HKClinicalRecord` UUID but labels its documented instability; when FHIR identity fields are available, a separate stable content identity is included and does not disguise the unstable UUID.

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
- vision prescriptions;
- attachment metadata and exact available attachment bytes.

The schema also retains clinical/FHIR, CDA, and verifiable clinical record variants for historical and future compatible producers, but current App Store builds do not request or capture those types.

This is public-API completeness, not access to Apple's private database. Health.md does not infer unavailable sleep schedules, alarms, ECG leads, measurement sessions, or other private fields.

## Special authorization and capability behavior

Most selected HealthKit types use the normal read-authorization flow. Some types behave differently:

- medications and vision prescriptions use Apple's per-object selectors and are opt-in;
- clinical records, CDA documents, and verifiable clinical records are source-gated off in current App Store builds;
- WorkoutKit schedules use a separate read-only capability path with no HealthKit authorization prompt;
- unavailable runtime APIs are `unsupported`; deliberately unrequested special access is `skipped` rather than a false successful-empty result.

Metric selection controls both direct records and required relationship dependencies. Archive records retain direct/dependency attribution so selecting Workouts, blood pressure, or food does not silently claim every child type as a directly selected metric.

## Exact binary data and URLs

Binary metadata, FHIR JSON, CDA bytes, verifiable records, WorkoutKit representations, and available attachments are base64 encoded by canonical JSON. Attachment records include exact byte availability and SHA-256 checksums when bytes were read. An empty available attachment has the checksum of empty data; unavailable bytes do not get a fabricated checksum.

Source URLs are preserved as strings. Health.md never fetches them, follows them, or treats remote content as captured data.

## Summary correctness notes

- Blood-pressure summaries retain daily average/minimum/maximum values. The canonical archive contains actual correlation pairs and Health.md does not infer sessions or average nearby readings.
- VO2 Max may use the latest historical measurement through the end of the requested day. Its UUID, source start/end, carry-forward flag, and age are exported so it cannot masquerade as an in-day reading. The v7 dictionary labels `vo2_max` as `latest`; range headline values select the latest daily value rather than the largest value.
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

API Endpoint export wraps ordinary v8 daily records in `healthmd.api_export`. The daily record version is declared by `daily_record_schema_version`; each `records` item still contains its own schema/version and archive. Provider-specific sidecars can independently advance the API envelope version without changing `healthmd.health_data`.

## Practical limits

- Health.md can preserve only data exposed by public HealthKit and WorkoutKit APIs on the running OS.
- Current exports are snapshots. They do not include historical deletion tombstones from earlier snapshots.
- Lossless files can be large, especially with routes, ECG voltage measurements, series, FHIR/CDA data, or attachments.
- Current connected iPhone/Mac jobs use peer-bound durable checksum-chained corpus sessions with 32–64 MiB partitions (48 MiB default) and 512 KiB frames. A logical day/item may span any number of physical partitions without a product-level item or corpus cap. A protected bounded iPhone journal and durable Mac frontier resume after reconnect/app relaunch without retransmitting committed gigabytes. Mixed-version peers retain the legacy 2 GiB single-payload cap. These are transport/lifecycle changes only and do not change daily export schema keys or versions.
- API Endpoint exports use sequential batches bounded by 7 calendar days and an 8 MiB encoded-body target by default. A single daily record is indivisible and can exceed that target; the API envelope and daily schemas are unchanged.
- HealthKit capture and final JSON/CSV serialization can still use substantial memory. Export smaller date ranges when working with dense records or attachments.

## Migrating from v5 or v6

Existing v5, v6, and v7 files remain valid historical exports. Do not relabel them as v8. Re-export when consumers need the corrected VO2 Max `latest` rule, populated extended-category CSV units, calendar-timezone-correct roll-up date labels, or the v8 range summary; v6 dictionaries described `vo2_max` as a maximum.

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

## Internal semantic-input migration boundary

Apple converts already-captured `HealthData` into bounded `healthmd.semantic_input` v1 batches for deterministic Rust filtering, typed reduction, and Apple range-summary planning. The session explicitly carries disabled frontmatter output keys and whether platform archive extensions may be retained, so previously captured data cannot bypass current output settings. This internal envelope is not `healthmd.health_data`, is never written to a destination, and does not change schema version 8. HealthKit querying/statistics, sleep day ownership, archive payloads, source/device metadata, localization, and daily/archive rendering remain native. The audited non-archive summary-only roll-up subset can select pure Rust rendering after its operation-wide gate; broader operations remain legacy or native-authoritative shadow. SDK-produced daily values cross as explicit aggregate facts so the migration does not recompute HealthKit statistics from raw samples.

## Internal render and artifact-plan migration boundary

A completed semantic result and frozen presentation snapshot may enter `healthmd.render_input` v1. The shared core renders destination-neutral Apple-v7 artifacts and returns validated relative paths, media types, write modes, exact bytes, byte counts, and checksums. Large archive JSON/CSV items and attachments use a bounded stream that never retains a second complete output buffer. Security-scoped URLs, destination reads, atomic writes, ZIP containers, API networking, credentials, and direct transport remain native.

Pre-cutover Swift renderer bytes are frozen independently under `packages/contracts/render-input/v1/fixtures/native-apple-v7.json`. This internal migration does not alter schema version 8. Release defaults remain legacy until the M6 rollout gates pass. Shadow keeps Swift authoritative, while the narrowly admitted summary-only roll-up path can use Rust authority without opening a native renderer; Apple daily and API Rust authority remain gated on independent exact v7 profile documents.

## Schema version policy and guardrail

`HealthMdExportSchema.version` is the production daily schema integer. Version 8 is current; versions 1 through 7 are historical. The committed v5, v6, and v7 signatures remain preserved; v8 has its own versioned fixture.

Bump the daily schema when a public key, type, meaning, unit, aggregation, JSON structure, CSV contract, reserved frontmatter field, or downstream dictionary rule changes. Do not bump for byte-compatible internal refactors.

`HealthMdTests/Export/ExportSchemaSignatureTests.swift` fingerprints JSON paths, CSV rows/headers, Markdown/Bases frontmatter, and the data dictionary. A shipped version's fixture must never be rewritten merely to silence CI.

The deterministic metric/profile inventory now comes from the shared Rust `metric-registry-v1.json`. Generated `HealthMetrics` and `HealthMetricExportMapping` regions preserve the existing native IDs, units, order, and keys; Swift continues to own HealthKit selectors, availability, permissions, persistence, localization, queries, and native-only rendering surfaces. UniFFI shadow tests compare the packaged registry to these generated projections. This internal authority change is byte-compatible and does not create v8.

## Intentional schema change workflow

1. Change the exporter or metric mapping.
2. Decide whether the public schema changed.
3. If it changed, bump `HealthMdExportSchema.version`.
4. Run `make update-export-schema-signature`.
5. Review the new versioned fixture; do not overwrite a shipped fixture.
6. Run exporter contract tests and a mixed v5/v6/v7 export smoke test.

A release smoke test should cover local iPhone, API, and Connected Mac outputs; summary-only and lossless settings; Markdown/Bases readability; canonical JSON/CSV parity; and an updated downstream Obsidian parser.
