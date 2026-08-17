# Typed provider sections v1

**Status:** canonical for Apple `healthmd.health_data` v8

**Public profile:** Apple `healthmd.health_data` v8

**Nested provider contract:** `healthmd.provider.whoop_daily` v1

**Unchanged profiles:** Android frozen v4 and Android analytical v5

## Purpose

This contract places typed, provider-namespaced data inside the daily files Health.md exports. It does not silently reinterpret provider values as Apple Health or Health Connect values, and it does not replace the provider-native sidecar/raw-snapshot layer.

The first proposed provider is WHOOP. The container is designed so future providers can add independently versioned sections without sharing WHOOP field names or semantics.

## Non-goals

This contract does not:

- change Android frozen v4 or Android analytical v5;
- merge WHOOP HRV RMSSD into Apple HealthKit HRV SDNN;
- overwrite existing Apple Health summary keys;
- define provider values as authoritative over HealthKit or Health Connect;
- place raw provider response bodies, endpoint URLs, OAuth material, pagination cursors, or HTTP headers in the daily provider section;
- remove `healthmd.external_provider_daily` sidecars or Android provider-native Raw API Snapshots;
- define weekly, monthly, or yearly provider roll-ups yet.

## Daily JSON embedding

An Apple v8 daily document adds an optional `providers` object:

```json
{
  "schema": "healthmd.health_data",
  "schema_version": 8,
  "date": "2026-07-13",
  "providers": {
    "whoop": {
      "schema": "healthmd.provider.whoop_daily",
      "schema_version": 1,
      "capture_status": "complete",
      "fetched_at": "2026-07-13T18:00:00Z",
      "resources": [
        {
          "resource": "recovery",
          "status": "success",
          "record_count": 0
        }
      ],
      "cycles": [],
      "recoveries": [],
      "sleep": [],
      "workouts": [],
      "warnings": []
    }
  }
}
```

Provider keys are stable lowercase provider identifiers. Each provider value carries its own schema and version. Consumers must branch on the daily schema version and then on each nested provider schema/version. Consumers should ignore unknown provider keys they do not understand, but the v1 producer schema permits only the reviewed `whoop` key. A future producer must not emit another provider until its strict typed schema and privacy review are added.

The `providers` key is omitted when the export contains no provider section. Once a provider section is requested for a retained day, a successful empty response is represented by `capture_status: complete`, successful resource rows with `record_count: 0`, and empty typed collections. Missing fields never mean zero.

## Common capture semantics

`capture_status` uses the following values:

| Value | Meaning |
|---|---|
| `complete` | Every resource planned for this provider/day completed successfully. A complete capture may contain zero records. |
| `partial` | At least one planned resource failed, was cancelled, skipped, or was unsupported. Successful sibling resources remain valid. |
| `not_requested` | Provider capture was deliberately not requested for this daily record. No typed provider values may be present. |

Every planned resource has exactly one `resources[]` row. Resource names must be unique, and each `record_count` must equal the number of retained typed records for that resource (or `1`/`0` for the body singleton):

```json
{
  "resource": "recovery",
  "status": "success",
  "record_count": 1
}
```

Resource status is one of `success`, `failure`, `cancelled`, `skipped`, or `unsupported`. A successful empty resource uses `success` and `record_count: 0`. `complete` requires every listed resource to be `success`; `partial` requires at least one non-success resource. Safe errors may include a stable code, bounded user-safe message, HTTP status, retryability, and retry delay. Raw provider error bodies are never retained here. Uniqueness and cross-collection record-count equality are producer invariants that must also be enforced by implementation tests because JSON Schema cannot express every cross-array count relationship.

`fetched_at` is the time Health.md completed the provider fetch. It is not a health measurement timestamp. It is `null` only for `not_requested`.

Warnings are structured and additive. They must use stable codes and safe messages and may identify one resource. A warning does not fabricate a provider measurement.

## WHOOP v1 typed groups

The mapping baseline is WHOOP's current [`/developer/v2` API reference](https://developer.whoop.com/api/), reviewed for this draft on 2026-08-12. WHOOP v1 uses these groups:

| Group | Shape | Identity and meaning |
|---|---|---|
| `cycles` | array | One entry per WHOOP cycle, identified by provider-issued `id`. |
| `recoveries` | array | One entry per recovery, identified by provider-issued `cycle_id`; optional `sleep_id` preserves the relationship. |
| `sleep` | array | One entry per WHOOP sleep or nap, identified by provider-issued `id`; required `cycle_id` preserves its cycle relationship. |
| `workouts` | array | One entry per WHOOP workout, identified by provider-issued `id`; current v2 `sport_name` is required. Deprecated v1 `sport_id` is not part of this contract. |
| `body` | object | Current profile singleton, never represented as a historical measurement. |

All provider IDs are encoded as strings even when the upstream API currently returns a number. This avoids cross-language integer-width and precision differences and does not change provider identity.

### Units and names

Field names carry units or semantics when ambiguity would otherwise be possible:

- WHOOP duration values use exact integer `*_milliseconds`; producers do not round or truncate the provider's millisecond values;
- energy uses `energy_kilojoules`;
- distance and altitude use meters;
- heart rate uses `*_bpm`;
- WHOOP HRV uses `hrv_rmssd_ms` and must never project into Apple `hrv_ms`/SDNN;
- oxygen and WHOOP scores use `*_percent` on a `0...100` scale;
- temperature uses `skin_temperature_celsius`;
- WHOOP strain uses the provider-defined dimensionless `strain_score`;
- height and weight use meters and kilograms;
- `recent_nap_adjustment_milliseconds` preserves WHOOP's signed `need_from_recent_nap_milli` value exactly; it is negative or zero and is not sign-inverted into a positive “credit.”

Unknown or unavailable values are omitted. Explicit zero is retained only when WHOOP returned zero or the documented typed derivation produced zero; producers must not use zero as a missing-value placeholder. `cycles[].end_time: null` is reserved for an in-progress cycle whose provider response explicitly has no end. Physiologically nonzero measurements such as heart rate and SpO₂ must be positive when present.

### Timestamps and ordering

Measurement/event timestamps are RFC 3339 UTC strings ending in `Z`. Producers preserve a provider-reported `timezone_offset` separately when supplied; that field accepts `Z` or a signed `±HH:MM` value. Arrays are sorted deterministically by start time and then provider ID. Recoveries are sorted by their related cycle start when available, then `cycle_id`.

The owning daily record supplies calendar-day ownership. Provider requests use the same captured IANA calendar timezone and half-open `[start, end)` day window used for the export operation. Raw event timestamps are not clipped to day boundaries.

### Derived values

A producer may emit `total_sleep_milliseconds` only from the exact typed WHOOP stage durations retained in the same sleep entry. The reviewed formula is:

```text
total_sleep_milliseconds = light_sleep_milliseconds + slow_wave_sleep_milliseconds + rem_sleep_milliseconds
```

No other provider-specific score or aggregate is inferred when WHOOP does not return it.

### Body singleton

WHOOP body data is a current profile singleton with no measurement timestamp. It uses:

```json
{
  "source_kind": "current_profile_snapshot",
  "observed_at": "2026-07-13T18:00:00Z",
  "height_meters": 1.82,
  "weight_kilograms": 78.4
}
```

`observed_at` is fetch time, not measurement time. The singleton may be included only for the current owner day and must not be repeated across historical or range days.

## Existing summaries and overlap

Apple v8 leaves existing Apple Health summary fields byte-semantically unchanged. Provider values appear only under `providers.whoop` and in equivalent provider-prefixed flat-format projections.

This is intentional because the same WHOOP event may also have been written into HealthKit. The v1 provider section does not claim cross-layer deduplication and does not combine provider and HealthKit sleep stages, calories, heart values, or workouts.

A later source-resolution contract may project reviewed equivalent provider facts into traditional summary keys. That future contract must define per-metric precedence, provenance, missingness, deduplication, and semantic compatibility. It requires its own public schema analysis.

## Other export formats

The provider section is one logical contract rendered for each traditional format.

### Markdown

Markdown adds a provider section after the established health summaries:

```markdown
## WHOOP

- Capture: Complete
- Recovery score: 82%
- HRV (RMSSD): 54.3 ms
- Resting heart rate: 49 bpm
```

Repeated sleep, cycle, and workout records may use compact tables. Markdown must label RMSSD explicitly and must not present provider body fetch time as measurement time.

### Obsidian Bases/frontmatter

Bases/frontmatter exports add stable provider-prefixed scalar keys for values that have an unambiguous daily scalar projection, for example:

```yaml
whoop_capture_status: complete
whoop_recovery_score_percent: 82
whoop_hrv_rmssd_ms: 54.3
whoop_resting_heart_rate_bpm: 49
```

Repeated events are not flattened into lossy indexed keys. They remain available in JSON, Markdown tables, and CSV structured rows. Provider-prefixed keys require data-dictionary entries before implementation.

### CSV

CSV preserves the existing six-column header. Scalar projections use provider categories such as `WHOOP Recovery` and `WHOOP Body`. Repeated structured events use RFC 4180-safe canonical JSON values, following the established raw HealthKit row pattern:

```csv
Date,Category,Metric,Value,Unit,Timestamp
2026-07-13,WHOOP Recovery,Recovery Score,82,percent,
2026-07-13,WHOOP Workout,Workout Record,"{""id"":""workout-synthetic-001""}",json,2026-07-13T15:00:00Z
```

The v1 contract does not add a CSV column. Structured JSON rows retain provider IDs that cannot be represented safely in the existing scalar columns. A recovery scalar has an empty `Timestamp` because WHOOP recovery has no independent measurement timestamp in this typed contract; `fetched_at` must never be substituted. Its structured record retains `cycle_id` and `sleep_id` for joining to timed records.

### API Endpoint

API Endpoint records carry the same v8 daily `providers` section. The existing v2 envelope may continue to carry `external_records` for exact provider-native sidecars; normalized daily provider facts and provider-native payloads are intentionally different layers. Removing or relocating `external_records` would require separate API-envelope version analysis.

### Sidecars and raw snapshots

- Apple `healthmd.external_provider_daily` v1 remains the provider-native fidelity layer.
- Android Raw API Snapshot remains the exact provider-native page layer.
- The typed daily section contains reviewed fields only and never embeds arbitrary provider JSON.
- Consumers must not assume a sidecar exists merely because a typed provider section exists; destination settings may independently control native payload output.

## Capture failures and privacy

A provider failure must not discard a valid Apple Health or Health Connect daily record. Successful typed siblings remain present with `capture_status: partial` and a resource error. Rate limits, revoked access, missing scopes, malformed success responses, and network failures use stable safe codes.

The typed section must redact or omit:

- access and refresh tokens;
- OAuth codes, client secrets, and authorization headers;
- pagination cursors and provider URLs;
- cookies and arbitrary response headers;
- raw provider error bodies;
- account names, email addresses, and profile identifiers not required for record identity.

## Versioning and adoption

Embedding `providers` changed the Apple public daily schema and advanced `HealthMdExportSchema.version` to 8.

The nested WHOOP contract advances independently when WHOOP-specific keys, types, units, meanings, or capture semantics change. Adding another provider does not change the WHOOP schema version, but it still requires daily/profile compatibility analysis because Markdown, Bases, CSV, data dictionary, and downstream parsers may gain new public output.

Android frozen v4 and analytical v5 must not change in place. Android adoption requires a new explicit profile/version or another reviewed additive boundary. The existing Android `WhoopCloudDataProvider` is useful mapping evidence, not authority to relabel frozen output.

Implementation and future changes require coordinated review of:

- Apple local, scheduled, Connected Mac, ZIP, API, and direct/CLI paths;
- Android compatibility and raw-provider paths;
- shared Rust semantic/render input and provider extension retention;
- the website export reference and generated examples;
- the external Obsidian plugin and custom scripts;
- export schema signatures, data dictionary, roll-up rules, and interoperability fixtures.

## Implementation boundary

Native capture normalizes provider API responses once into a typed provider daily model. Exporters and the Rust rendering boundary should consume that typed model rather than parse `ExternalProviderPayload.data` independently.

```text
WHOOP API response
    → native WHOOP v2 normalizer
    → typed healthmd.provider.whoop_daily v1
    → daily provider extension retained through semantic/render input
    → JSON / Markdown / Bases / CSV projections
```

Provider capture and provider rendering remain native-authoritative. The shared Rust core exposes the `apple_health_data_v8` profile for provider-free semantics/rendering; adapters reject provider-bearing records rather than dropping the typed section.

## Fixture

[`fixtures/whoop-complete.providers.json`](fixtures/whoop-complete.providers.json) is synthetic and contains no production health data, credentials, account identity, endpoint URL, or pagination cursor. It represents the exact canonical value of a daily record's `providers` property and is described by [`provider-sections-v1.schema.json`](provider-sections-v1.schema.json).

## Adopted v8 decisions

1. Provider-only days remain supplemental and do not become exportable daily records.
2. Provider-native sidecars remain available from the same fetch; v8 adds no setting and no duplicate provider request.
3. Provider scalars have no weekly, monthly, or yearly roll-ups.
4. Provider records do not participate in Individual Entry Tracking.
5. v8 is Apple-only; Android frozen v4 and Android analytical v5 remain unchanged.
