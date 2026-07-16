# Canonical Apple Health records

When Lossless Health Records is enabled, daily JSON embeds `healthmd.healthkit_records` version 1. CSV emits the same canonical objects as RFC 4180-safe JSON cells.

The archive is Health.md's complete representation of what selected public HealthKit and WorkoutKit APIs returned. It is not a copy of Apple's private Health database.

## Archive envelope

| Field | Type | Meaning |
|---|---|---|
| `schema` | string | `healthmd.healthkit_records`. |
| `schema_version` | integer | Canonical archive version, currently `1`. |
| `capture_status` | enum string | Archive-authoritative capture status. |
| `ownership` | object | Owner date, exact interval, calendar/timezone, and assignment rule. |
| `records` | array | Deterministically ordered UUID-backed records. |
| `external_records` | array | Optional UUID-free public values with documented external identities. |
| `query_manifest` | object | Every planned query branch and its result. |
| `integrity_warnings` | array | Non-fatal integrity observations. |
| `medication_inventory` | array | Public medication inventory objects without fabricated HKObject identity. |

A generated archive and exhaustive path/type inventory are available at:

- [`generated/core/canonical-archive.json`](./generated/core/canonical-archive.json)
- [`generated/core/canonical-json-fields.md`](./generated/core/canonical-json-fields.md)

## UUID-backed record

Every element of `records` can contain:

| Field | Type | Meaning |
|---|---|---|
| `original_uuid` | UUID string | Original public HealthKit object UUID. |
| `object_type_identifier` | string | HealthKit object/data type identifier. |
| `record_kind` | string | Stable Health.md kind, with unknown future kinds preserved. |
| `selected_metric_ids` | string array | Combined direct/dependency metric IDs retained for compatibility. |
| `included_because` | string | `selected_metric`, `relationship_dependency`, or a preserved future reason. |
| `metric_attribution` | object | Explicit `direct_metric_ids` and `dependency_metric_ids`. |
| `start_date` | RFC 3339 UTC | Exact public source start timestamp. |
| `end_date` | RFC 3339 UTC | Exact public source end timestamp. |
| `has_undetermined_duration` | boolean | Whether HealthKit marks duration as undetermined. |
| `source_revision` | object | Source app/device revision and OS provenance. |
| `device` | object | Optional public `HKDevice` fields. |
| `metadata` | object | Recursively typed public metadata values. |
| `payload` | tagged object | Exact record payload variant. |
| `relationships` | array | UUID or external-identity graph edges. |

Records are deduplicated only by the same original UUID. Repeated query views can enrich the same canonical record without promoting a relationship dependency to a directly selected record.

## Record kinds

The serializer recognizes these public kinds and preserves unknown future values:

- `quantity`
- `category`
- `correlation`
- `workout`
- `workout_route`
- `heartbeat_series`
- `activity_summary`
- `characteristic`
- `clinical`
- `verifiable_clinical_record`
- `audiogram`
- `electrocardiogram`
- `vision_prescription`
- `state_of_mind`
- `medication_dose_event`
- `scored_assessment`
- `document`
- `attachment`
- implementation-preserved future/other kinds

A record kind describes the source object family. The payload tag describes how its exported data is encoded.

## Payload variants

### Quantity

A `quantity` payload can contain:

| Field | Meaning |
|---|---|
| `type` | `quantity`. |
| `value`, `unit` | Exact primary value and canonical unit. |
| `sample_subclass` | Public quantity sample subclass when available. |
| `sample_kind` | Discrete, cumulative, series, or another preserved kind. |
| `count` | Number of source/statistical values represented. |
| `minimum`, `average`, `maximum`, `most_recent`, `sum` | Optional exact quantity objects, each with value/unit. |
| `most_recent_date_interval` | Exact start/end associated with the most recent statistic. |
| `series` | Optional child points with quantity, date interval, owning UUID, and owning type. |

Use each payload's unit as exported. Canonical HealthKit microgram quantities can use the reviewed `mcg` source/query unit string, while the daily summary dictionary labels equivalent microgram-scale fields `µg`; neither should be interpreted as `mg`.

### Category

A `category` payload contains the signed raw value and an optional known symbolic value. Unknown raw values are retained even when the running app cannot name them.

### Correlation

A `correlation` payload contains deterministically ordered component UUIDs. Relationship edges provide graph semantics. Blood pressure and food use correlations rather than time-proximity inference.

### Structured

A `structured` payload contains a stable `kind` and a dictionary of recursively typed fields. Specialized HealthKit and WorkoutKit domains use this form when a fixed scalar payload is insufficient.

### Binary artifact reference

A `binary_artifact_reference` contains an identifier and optional media type, filename, byte count, and SHA-256 checksum. The referenced data can also appear as typed base64 fields where the public API returns bytes.

### Unknown

An `unknown` payload preserves an unrecognized kind and typed fields so future public values are not silently discarded.

## Typed metadata

Every metadata value is a tagged object. Consumers must branch on `type` rather than coercing all values to strings.

| `type` | Additional fields | Representation |
|---|---|---|
| `null` | None | Explicit source null. |
| `string` | `value` | Unicode string. |
| `bool` | `value` | Boolean. |
| `signed_integer` | `value` | Signed integer. |
| `unsigned_integer` | `value` | Unsigned integer. |
| `floating_point` | `value` | Number; non-finite values follow serializer policy. |
| `date` | `value` | Canonical UTC timestamp. |
| `data` | `value` | Base64 string. |
| `url` | `value` | Preserved URL string; Health.md does not fetch it. |
| `quantity` | `value`, `unit`, `raw_description` | Public metadata quantity. |
| `array` | `value` | Array of tagged metadata values. |
| `dictionary` | `value` | String-keyed tagged metadata values. |
| `unsupported` | `type_name`, `description` | Explicit representation of a public value that cannot be encoded as a known case. |

Unknown metadata must not cause the entire record to disappear.

## Source revision and device

`source_revision` includes:

- source name;
- bundle identifier;
- optional version and product type;
- optional OS major, minor, and patch versions.

`device` can include every public `HKDevice` field:

- name;
- manufacturer;
- model;
- hardware, firmware, and software versions;
- local identifier;
- UDI device identifier.

Health.md omits fields the public API does not provide. It never invents source/device provenance for external records.

## Relationships

Each relationship contains:

| Field | Meaning |
|---|---|
| `target.type` | `uuid` or `external_identifier`. |
| `target.value` | Target identity. |
| `role` | Domain role such as parent, component, route, or attachment. |
| `kind` | Relationship kind. |
| `target_owner_date` | Optional cross-day owner hint for resolving another daily archive. |

Owner hints do not change source timestamps. A relationship can reference an object owned by another daily file.

## External records

Some public values are not `HKObject`s. They appear under `external_records` with:

- a deterministic `external_identifier`;
- `external_identity_kind` describing how that identity was formed;
- object type, record kind, selected metrics, and attribution;
- recursively typed fields;
- relationships to UUID or external identities.

Examples include Activity summaries, profile characteristics, attachments, and WorkoutKit schedules. Health.md does not disguise these as UUID-backed HealthKit records.

## Specialized domain coverage

Subject to selection, authorization, runtime availability, and public API limits, the archive covers:

| Domain | Canonical representation |
|---|---|
| Ordinary quantities/categories | Exact quantity/category payloads, provenance, metadata, series/statistics. |
| Blood pressure and food | Correlation records plus exact component graph. |
| Workouts | Workout identity, events, activities, statistics, routes/locations, associated samples, effort edges, attachments, and plans. |
| State of Mind | Exact kind, valence, labels, associations, UUID, timing, and provenance. |
| Medication | Inventory external identities and source dose events. |
| ECG | Classification/measurements and waveform data exposed publicly. |
| Heartbeat series | Public heartbeat time-series values. |
| Audiograms | Sensitivity points and public related fields. |
| Scored assessments | GAD-7 and PHQ-9 public score/classification fields. |
| Clinical/FHIR | Clinical UUID, FHIR resources/identity, source fields, and documented UUID stability limits. |
| Documents | CDA/verifiable content and public metadata. |
| Vision | Public prescription fields and per-object identity. |
| Attachments | Metadata, byte availability, exact available bytes, and checksum. |
| Characteristics | Date of birth, biological sex, blood type, skin type, wheelchair use when readable. |
| Activity summary | Public ring/activity-summary values under external identity. |
| WorkoutKit | Scheduled plans available through the separate public capability. |

The generated metric catalog identifies every currently reviewed metric and whether it has a daily summary or archive-only representation. [`generated/core/specialized-records.md`](./generated/core/specialized-records.md) showcases each specialized domain's canonical object and observed field paths/types.

## Ownership

`ownership` records the exact half-open calendar interval. A UUID-backed record belongs to the daily archive whose interval contains its **source start date**. Start/end are never clipped, even when the record spans midnight.

Do not reconstruct ownership by parsing the top-level filename alone. Use `ownership.owner_date` and its captured timezone.

## Public API limits

Health.md cannot export data Apple does not expose publicly. Current snapshots do not include deletion tombstones. Private sleep schedules, alarms, ECG lead internals, and similar unavailable fields are not inferred.
