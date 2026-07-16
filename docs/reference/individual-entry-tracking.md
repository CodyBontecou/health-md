# Individual Entry Tracking

Individual Entry Tracking creates a separate Markdown note for selected timestamped events in addition to the daily export.

Under schema v6, a present canonical archive is the sole authority for entry identity. Health.md does not turn a daily aggregate into a source event merely because a canonical query returned no records or failed.

## Authority rules

| Daily source state | Entry behavior |
|---|---|
| Canonical archive present | Emit selected direct UUID-backed records only. No aggregate fallback. |
| `not_requested` | Compatibility event arrays and marked aggregate fallbacks can be used. |
| `legacy_unavailable` | Compatibility event arrays and marked aggregate fallbacks can be used. |
| Requested archive failed/empty | Do not fabricate entries from summaries. |

Repeated views of one UUID produce at most one entry per directly selected metric. Relationship dependencies are not promoted into directly selected notes.

## Supported canonical views

- Ordinary quantity records
- Ordinary category records and symptoms
- State of Mind entries
- Workouts with UUID-matched readable presentation
- Blood-pressure correlations and actual components
- Medication dose events
- Other selected UUID-backed specialized/clinical records through their canonical payload

UUID-free external records stay in the daily JSON/CSV archive. Health.md does not fabricate an HKObject UUID so they can become ordinary source-entry notes.

## Default folder and filename

The default template is:

```text
{date}_{time}_{metric}
```

For a canonical source record, production appends the metric ID and lowercase UUID:

```text
entries/<category>/2026_03_15_1030_daily_mood_daily_mood_10000000-0000-0000-0000-000000000001.md
```

The metric appears twice with the default template because:

1. `{metric}` expands inside the user-configurable base template.
2. Health.md appends the canonical metric and UUID to guarantee stable source identity.

This is intentional. It prevents same-minute overwrites and keeps paths stable across partial reruns or one UUID tracked under multiple metrics.

For UUID-free compatibility entries, the base template remains unchanged. If multiple compatibility entries collide within one minute, Health.md adds a deterministic seconds/milliseconds suffix and then an index if needed.

The generated path matrix is at [`generated/individual/filename-path-matrix.md`](./generated/individual/filename-path-matrix.md).

## Common frontmatter

A non-workout entry begins with these fields when applicable:

| Field | Meaning |
|---|---|
| `date` | Calendar date rendered for the entry timestamp. |
| `time` | Local `HH:mm` presentation time. |
| `datetime` | Canonical UTC timestamp for UUID-backed records. |
| `type` | Lowercase category token. |
| `metric` | Health.md selected metric ID. |
| `value` | Primary presentation value derived from the canonical payload. |
| `unit` | Canonical unit when non-empty. |
| `source` | Source name when public provenance exists. |

Canonical extraction adds a stable field set that can include:

- `entry_kind`
- `original_uuid`
- `object_type_identifier`
- `record_kind`
- source start/end and undetermined-duration fields
- record/archive schema identifiers and versions
- selected metrics and direct/dependency attribution
- source revision, device, metadata, payload, and relationships as stable JSON strings
- `canonical_record_json`, the authoritative complete record object
- specialized presentation fields such as valence/labels, blood-pressure values/component IDs, medication status/dose, or workout identity

Treat `canonical_record_json` as authoritative when a flattened presentation field and the source object need to be reconciled.

The generated field/type inventory is at [`generated/individual/frontmatter-fields.md`](./generated/individual/frontmatter-fields.md).

## Primary-value mapping

| Payload | Entry presentation |
|---|---|
| Quantity | Exact quantity value and unit. |
| Category | Raw category value plus symbolic value when known. |
| Correlation | Specialized mapper where supported, otherwise canonical structured identity. |
| Structured | Domain-specific primary value when known; complete payload remains in canonical JSON. |
| Binary reference | Artifact identifier/reference; bytes remain in the daily archive. |
| Unknown | Preserved canonical object without invented interpretation. |

## State of Mind

State of Mind entries preserve:

- source UUID and exact start/end;
- source kind (Daily Mood or Momentary Emotion);
- valence and human-readable feeling;
- labels and associations;
- optional classification;
- provenance, metadata, and canonical JSON.

Selecting `average_valence` for individual tracking emits each source member used by that view. It does not invent a daily-average event.

Complete example: [`generated/individual/state-of-mind.md`](./generated/individual/state-of-mind.md).

## Blood pressure

One canonical blood-pressure note represents an actual HealthKit correlation. It links the real systolic and diastolic component UUIDs and values. Health.md does not group nearby independent samples into a guessed session and does not substitute the daily average while an archive is present.

Complete example: [`generated/individual/blood-pressure.md`](./generated/individual/blood-pressure.md).

## Medication dose

A canonical medication entry can expose:

- source event UUID;
- medication concept/external identity;
- display name;
- log status and display status;
- actual and scheduled dates;
- actual and scheduled quantity/unit;
- schedule type;
- metadata and canonical payload.

Inventory capture failure does not delete a successfully captured dose event.

Complete example: [`generated/individual/medication-dose.md`](./generated/individual/medication-dose.md).

## Workouts

Workout notes combine canonical source identity with UUID-matched readable presentation. Depending on available data they include:

- activity type/sport and raw HealthKit activity value;
- exact start/end and duration;
- indoor/outdoor state;
- distance, pace/speed, calories, heart rate, cadence, power, and elevation;
- lap/split tables;
- heart-rate zones;
- route and sample counts;
- metadata;
- canonical record fields and JSON.

Presentation enrichment is used only after matching the same source UUID. It cannot replace canonical identity.

Complete example: [`generated/individual/workout.md`](./generated/individual/workout.md).

## Compatibility aggregate entries

When source capture was explicitly not requested or is legacy-unavailable, some metrics can produce an entry with:

```yaml
entry_kind: daily_aggregate
aggregation: daily_latest
```

This is a compatibility projection, not an original Apple Health event. Consumers must keep that distinction.

Complete example: [`generated/individual/legacy-daily-aggregate.md`](./generated/individual/legacy-daily-aggregate.md).

## Parser guidance

1. Use `original_uuid + metric` as canonical entry identity.
2. Prefer `canonical_record_json` for exact source parsing.
3. Preserve unknown additional frontmatter fields.
4. Treat `entry_kind: daily_aggregate` as a projection.
5. Do not infer missing notes from daily summary values.
6. Check the parent daily record's capture status and manifest before asserting entry completeness.
