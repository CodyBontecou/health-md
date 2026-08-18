# Unified cross-platform `healthmd.health_data` v9 proposal

**Status:** proposed; not approved for production writers

**Public schema:** `healthmd.health_data` v9

**Public profile:** `unified-cross-platform-v1`

**Source profiles:** Apple v8, Android frozen v4, Android analytical v5

**Nested platform contracts:** `healthmd.platform.apple_daily` v1 and `healthmd.platform.android_daily` v1

**Typed provider contract:** `healthmd.provider.whoop_daily` v1

## Decision summary

The first unified Apple/Android daily contract must be `healthmd.health_data` **v9**, not a second v8 grammar. Apple v8 already identifies a shipped public grammar. A profile field cannot retroactively disambiguate two documents that share `schema: healthmd.health_data` and `schema_version: 8`, because deployed consumers may dispatch on that pair alone.

This proposal unifies the envelope, owner-day model, typed metric facts, exact numbers, capture completeness, provenance, platform-extension boundary, and typed-provider boundary. It does not claim that HealthKit and Health Connect are semantically identical, and it does not rewrite Apple v8 or Android v4/v5.

The proposal is a contract artifact, not authorization to enable a writer. The default-writer and migration gates in [RFC-0004](../../../../docs/architecture/rfc-0004-unified-health-data-v9.md) remain required.

## Goals

1. Give Apple and Android one unambiguous daily schema and one machine-readable profile.
2. Place only reviewed semantic facts in a shared typed metric collection.
3. Preserve non-equivalent platform data in independently versioned platform sections.
4. Preserve exact numeric representation, source identity, timestamps, missingness, and provenance.
5. Distinguish successful empty capture from unsupported, unauthorized, unavailable, failed, cancelled, and not-requested capture.
6. Reuse independently versioned provider contracts, beginning with WHOOP v1.
7. Permit readers to dual-read historical Apple v5/v6/v7/v8 and Android v4/v5 without changing their bytes.

## Non-goals

This proposal does not:

- rename Apple v8 as a cross-platform format;
- modify any historical fixture or shipped writer in place;
- claim that HealthKit HRV SDNN and Health Connect or WHOOP RMSSD are interchangeable;
- merge typed provider data into primary-platform metrics;
- define cross-source deduplication or provider precedence;
- make provider-only days exportable;
- define provider roll-ups or provider Individual Entry Tracking;
- embed arbitrary platform or provider JSON in shared metrics;
- change API envelope, direct protocol, raw snapshot, HealthKit archive, semantic-input, or render-input versions;
- promise lossless reverse conversion into every historical profile.

## Canonical JSON envelope

Every unified daily document has this identity:

```json
{
  "schema": "healthmd.health_data",
  "schema_version": 9,
  "profile": "unified-cross-platform-v1"
}
```

The complete top-level shape is:

```json
{
  "schema": "healthmd.health_data",
  "schema_version": 9,
  "profile": "unified-cross-platform-v1",
  "owner_date": "2026-07-13",
  "calendar": {
    "identifier": "gregorian",
    "time_zone": "America/New_York",
    "interval_start": "2026-07-13T04:00:00Z",
    "interval_end": "2026-07-14T04:00:00Z",
    "assignment_rule": "record_start_in_half_open_day_interval"
  },
  "source": {
    "platform": "apple",
    "source_profile": "apple_health_data_v8"
  },
  "capture": {
    "status": "complete",
    "resources": [
      {
        "source": "apple_health",
        "resource": "steps",
        "status": "complete",
        "record_count": 1
      }
    ]
  },
  "metrics": [],
  "platform": {
    "apple": {
      "schema": "healthmd.platform.apple_daily",
      "schema_version": 1,
      "source_schema_version": 8
    }
  }
}
```

Unknown top-level keys are rejected. Additive evolution uses a new daily schema version, a newly reviewed nested platform/provider version, or both after compatibility analysis.

## Owner date and calendar

`owner_date` is the civil day assigned by the export operation. `calendar.time_zone` is a frozen IANA timezone. `interval_start` and `interval_end` are exact UTC boundaries for the half-open owner-day interval `[start, end)`. They are not assumed to be 24 hours apart.

Primary-platform capture and every typed provider request must use this same frozen calendar. A record belongs to the day when its source start instant is in the half-open interval unless a separately versioned platform contract defines a reviewed source-specific ownership rule. Raw event timestamps remain exact and are not clipped to owner-day boundaries.

Historical Android noon-to-noon sleep journal ownership is not silently generalized into the daily interval. When analytical conversion retains that distinct journal interpretation, its source facts and rule remain Android platform data; a shared sleep metric may be emitted only under an approved mapping.

## Source and platform invariants

Exactly one primary platform is present.

| `source.platform` | Allowed `source.source_profile` | Required platform key |
|---|---|---|
| `apple` | `apple_health_data_v8` | `platform.apple` |
| `android` | `android_frozen_v4`, `android_analytical_v5` | `platform.android` |

The source profile records the authoritative input projection used to produce v9. It does not make v9 a wrapper around an opaque legacy document.

### Apple platform v1

```json
{
  "schema": "healthmd.platform.apple_daily",
  "schema_version": 1,
  "source_schema_version": 8,
  "healthkit_record_archive": {
    "schema": "healthmd.healthkit_records",
    "schema_version": 1,
    "sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
    "byte_count": 4096
  }
}
```

The optional archive reference, when present, identifies separately bounded canonical `healthmd.healthkit_records` v1 bytes by schema, version, SHA-256, and byte count. The referenced bytes must independently satisfy that contract; v9 does not accept an unbounded opaque object in the daily envelope. Apple-only medications, state of mind, clinical records, source archives, characteristics, attachments, and other non-shared structures stay in this platform/archive layer until a language-neutral mapping is approved.

### Android platform v1

```json
{
  "schema": "healthmd.platform.android_daily",
  "schema_version": 1,
  "source_schema_version": 5,
  "source_profile": "android-analytical-v5",
  "merge_provenance": {
    "schema": "healthmd.android_merge_provenance",
    "schema_version": 1,
    "sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
    "byte_count": 2048
  }
}
```

The optional merge-provenance reference identifies separately bounded, independently versioned analytical audit bytes by schema, version, SHA-256, and byte count. A raw snapshot remains governed by `healthmd.raw_snapshot` v1 and may be referenced by digest; neither payload is copied into shared metric facts. Android-native source records, exact Health Connect timestamps, synthetic-ID markers, workout merge decisions, cadence structures, routes, and medical resources remain platform data when the common fact model cannot retain them without loss.

A v9 reader recognizes the nested platform/provider versions enumerated by the v9 schema. If a future nested version is designed to remain compatible with the same daily v9 envelope, the v9 schema and reader policy must first be revised through explicit compatibility review; otherwise the daily schema advances. A converter that advertises round-trip preservation must retain referenced canonical bytes; otherwise it must fail rather than silently drop them.

## Shared typed metrics

`metrics[]` is a deterministically ordered collection of typed semantic facts. It is not a copy of the current Apple or Android JSON hierarchy.

```json
{
  "semantic_id": "steps",
  "statistic": "sum",
  "value": {
    "value_type": "number",
    "number": {
      "representation": "unsigned_integer",
      "decimal": "1234"
    },
    "unit": "count"
  },
  "provenance": [
    {
      "source": "health_connect",
      "source_semantic_id": "steps",
      "source_record_ids": ["hc-steps-001"],
      "source_statistic": "sum"
    }
  ]
}
```

### Metric identity

- `semantic_id` is the language-neutral meaning, not a platform presentation key.
- `statistic` is required and must match the reviewed reducer: `sum`, `average`, `minimum`, `maximum`, `latest`, `count`, `duration_sum`, `first_time`, or `last_time`.
- A `(semantic_id, statistic)` pair occurs at most once per day.
- Metrics are sorted lexicographically by unified `semantic_id`, then by statistic enum order. The mapping ledger, not either platform's ordinal, controls which source identity maps to each unified ID.
- Missing values are omitted. Missing, unavailable, unauthorized, and failed values are never represented as zero.
- Explicit zero is retained when it is the captured or correctly reduced value.

### Exact values

Numbers use one of:

- `binary64` with exactly 16 lowercase hexadecimal IEEE-754 bits;
- `signed_integer` with a canonical decimal string;
- `unsigned_integer` with a canonical decimal string.

This avoids JSON number coercion and integer-width loss across Swift, Kotlin, Rust, JavaScript, and CLI consumers. Non-finite binary values are forbidden even though JSON Schema cannot inspect their bits; producers and validators must enforce that invariant.

Text, booleans, and text lists are tagged separately. Units use canonical language-neutral IDs such as `count`, `millisecond`, `meter`, `kilogram`, `kilocalorie`, `beat_per_minute`, `breath_per_minute`, `percent_0_100`, `fraction_0_1`, `celsius`, `milligram`, and `microgram`. Display abbreviations are renderer concerns.

### Provenance

Every metric has at least one provenance row. A row identifies:

- the primary source (`apple_health` or `health_connect`);
- the source semantic ID;
- source record IDs when available and safe;
- the source statistic when it differs from or clarifies the common statistic.

Provider sources are intentionally excluded from v1 shared-metric provenance because typed providers do not populate shared metrics. Cross-source deduplication and precedence require a future contract.

## Initial mapping policy

The shared metric registry is mapping evidence, not automatic authority. A metric may enter unified v9 only after its semantic ID, canonical unit, statistic, owner-day behavior, source aggregation, and provenance mapping have been reviewed on both platforms.

The initial candidate set is the intersection of backed Apple and Android metrics. Registry classes mean:

- `platform_exact_or_unavailable`: eligible when both sides are backed and unit/statistic normalization is reviewed;
- `mapped_alias`: eligible only after confirming that the alias preserves meaning, not merely a historical key;
- `platform_distinct`: never enters under a shared identity without a new reviewed semantic ID.

The normative mapping ledger is [`mapping-ledger.md`](mapping-ledger.md). An entry marked `candidate` is not permission for a writer. Only `approved` entries may appear in production v9.

### HRV

There is no generic `hrv` shared metric.

| Source fact | Unified semantic ID | Rule |
|---|---|---|
| HealthKit HRV | `heart_rate_variability_sdnn` | SDNN only; unit `millisecond` |
| Health Connect HRV | `heart_rate_variability_rmssd` | RMSSD only; unit `millisecond` |
| WHOOP recovery HRV | remains `providers.whoop.recoveries[].hrv_rmssd_ms` | no shared projection in v9 v1 |

SDNN and RMSSD must never be relabeled, averaged together, or used as precedence candidates for one another.

### Percentages

Every percentage mapping declares one canonical scale. A `fraction_0_1` fact and `percent_0_100` fact are different unit representations even when convertible. Producers must normalize using the mapping ledger, preserve explicit zero, and never infer a scale from magnitude. This closes the Android v4/v5 SpO2 and body-fat presentation ambiguity.

### Sleep

Sleep stage names do not become equivalent merely because UIs display similar labels. Apple core sleep and Android light sleep require an explicit reviewed mapping. Android's additive overlapping-session journal behavior must be disclosed in provenance/platform data and cannot silently claim principal-session or deduplicated semantics.

## Capture completeness

`capture` describes the primary platform only. Typed providers keep their own nested capture status.

Top-level status is mechanically derived:

- `complete`: every requested primary resource completed, including successful empty resources;
- `partial`: at least one requested resource was unsupported, unauthorized, unavailable, failed, or cancelled;
- `not_requested`: primary capture was deliberately not requested and there are no resource rows.

Every planned resource has one unique `(source, resource)` result:

```json
{
  "source": "apple_health",
  "resource": "steps",
  "status": "complete",
  "record_count": 0
}
```

Resource statuses are:

| Status | Meaning |
|---|---|
| `complete` | Query completed. `record_count: 0` is successful empty capture. |
| `not_requested` | Deliberately not requested. |
| `unsupported` | Runtime/platform cannot provide the resource. |
| `unauthorized` | Required authorization was not granted. |
| `unavailable` | Resource exists conceptually but was unavailable for this capture. |
| `failed` | Attempt failed. A safe error is required. |
| `cancelled` | Attempt was cancelled. A safe error is required. |

Safe errors contain only stable code, bounded user-safe message, and retryability. They never expose URLs, credentials, headers, cursors, account identity, stack traces, raw provider/platform bodies, or arbitrary SDK diagnostics.

Resource uniqueness, top-level derivation, and metric-to-resource consistency are implementation invariants that JSON Schema cannot fully express and validators must enforce.

## Typed providers

The optional `providers` object reuses independently versioned provider contracts. v9 v1 permits:

```json
{
  "providers": {
    "whoop": {
      "schema": "healthmd.provider.whoop_daily",
      "schema_version": 1
    }
  }
}
```

The complete WHOOP value must satisfy the canonical provider-sections v1 schema. The provider schema remains independently versioned and retains exact string IDs, millisecond values, signed nap adjustment, `sport_name`, relationships, missingness, resource bounds, safe failures, and deterministic ordering.

Provider rules remain:

1. Provider data supplements a retained primary-platform day; provider-only days do not create v9 documents.
2. Typed data coexists with Apple provider-native sidecars or Android raw snapshots.
3. The same fetch should supply typed and native fidelity layers; no duplicate request is implied.
4. Provider values do not populate shared metrics or platform compatibility summaries.
5. Provider records have no v1 weekly/monthly/yearly roll-ups or Individual Entry Tracking.
6. Provider and primary capture use the same frozen owner-day calendar and request interval. Provider record inclusion follows its independently versioned provider contract and may retain relationship context whose start precedes the interval (for example, a WHOOP cycle or sleep crossing local midnight); raw event timestamps are not clipped or reassigned.

## Determinism and boundedness

Canonical JSON uses UTF-8, no BOM, sorted object keys, canonical exact-number strings, and deterministic array order. Producer documentation must state whether a terminal newline is present. Hashing and fixtures use the exact bytes, not reparsed semantic equivalence.

Bounds in the structural schema are security boundaries, not batch recommendations. Native archives/raw snapshots keep their own independent limits. Producers must bound response bytes before parsing and must never retain unbounded arbitrary extension objects.

## Other formats

JSON is the normative v9 grammar. Markdown, CSV, and Obsidian Bases are deterministic projections, not separate semantic authorities.

- **Markdown:** labels semantic IDs/statistics and exposes source platform/profile. It must name HRV statistic and percentage scale.
- **CSV:** keeps a stable versioned v9 row contract; structured/platform/provider values use canonical JSON cells rather than lossy indexed flattening.
- **Bases/frontmatter:** emits only unambiguous scalar projections. Repeated facts remain structured.
- **Roll-ups:** consume only approved shared metrics whose mapping ledger defines a roll-up. Platform/provider sections do not acquire roll-up semantics by implication.

Exact format schemas and golden fixtures are required before any production writer is enabled.

## API, direct protocol, CLI, and raw boundaries

A daily schema bump does not implicitly bump transport contracts:

- API envelopes must advertise `daily_record_schema_version: 9` when carrying v9 records; an envelope version changes only if its own grammar changes.
- Direct protocols may carry generated v9 files after explicit capability negotiation without changing cryptographic/wire versions solely for the file schema.
- Strict canonical Apple `--raw` remains an Apple Health source operation unless separately expanded; it is not automatically a unified/provider export.
- Android `healthmd.raw_snapshot` v1 and Apple `healthmd.healthkit_records` v1 remain separate source-fidelity contracts.
- Internal `healthmd.semantic_input` and `healthmd.render_input` versions do not equal the public daily version.

## Migration and adoption

1. Preserve Apple v5/v6/v7/v8 and Android frozen v4/analytical v5 fixtures byte-for-byte.
2. Implement v9 readers in Apple, Android, CLI, website tooling, and the pinned Obsidian consumer before enabling any v9 writer.
3. Keep existing profile writers as defaults for at least the reviewed compatibility window.
4. Introduce v9 as an explicit opt-in. Default-writer rollout requires RFC approval and release evidence.
5. Persist the selected public profile in scheduled, retry, recovery, API, Connected Mac, SAF, and direct-file jobs.
6. Dual-write only to separate destinations or deterministic filenames; never overwrite a historical-profile document with v9.
7. Publish field-by-field source mappings, rejected mappings, unit conversions, ownership differences, and omission behavior.
8. Test real pinned CLI and Obsidian/visualization consumers against canonical Apple and Android v9 fixtures.
9. Provide migration guidance for Dataview, Bases, scripts, dashboards, API receivers, and archives.
10. Remove a historical writer/reader only in a later explicit compatibility decision.

## Producers and consumers

### Producers

- Apple iOS local, API, scheduled, Connected Mac, direct generated-file, streaming, and recovery exports.
- Apple macOS received/continued exports and roll-ups.
- Android local SAF, API, scheduled, automation, history retry, and direct generated-file exports.
- Shared Rust semantic/render core after a dedicated `unified_health_data_v9` profile is approved.
- CLI conversion commands that explicitly produce v9.

### Consumers

- Apple and Android historical readers and persisted jobs.
- Health.md CLI/MCP on macOS, Linux, and Windows.
- Contract validators, fixtures, package mirrors, and generated bindings.
- Website reference pages, samples, localized docs, and public agent assets.
- The pinned external Obsidian visualization plugin.
- User-authored Bases, Dataview queries, scripts, dashboards, API receivers, and archival tools.
- Direct peers carrying generated files.

## Validation requirements before writer approval

- JSON Schema validation for at least one Apple and one Android canonical fixture.
- Semantic invariant validation beyond JSON Schema: source/platform agreement, interval/owner-date agreement, unique metric keys, unique resources, capture derivation, finite binary64 values, canonical ordering, unit/statistic allowlists, and provider schema validation.
- Byte-level historical fixture checks.
- Swift, Kotlin, Rust, CLI, website, and pinned external-consumer tests.
- Privacy/security review of platform archives, provenance, safe errors, and source IDs.
- Documented RFC-0002 release/rollback evidence and owner approval.

## Versioning

Changes to a public key, requiredness, JSON type, unit, semantic meaning, reducer, omission rule, ordering rule, or capture state require `healthmd.health_data` v10 unless the change is isolated inside an independently versioned nested platform/provider contract and old readers can safely ignore it.

Adding a provider requires a reviewed typed provider schema and daily/profile compatibility analysis. Adding an approved metric mapping changes the profile revision/inventory and may require a schema bump if deployed readers treat the metric set as closed.

## Canonical artifacts

- Structural schema: [`unified-health-data-v9.schema.json`](unified-health-data-v9.schema.json)
- Mapping ledger: [`mapping-ledger.md`](mapping-ledger.md)
- Synthetic fixtures:
  - [`fixtures/apple-minimal.json`](fixtures/apple-minimal.json)
  - [`fixtures/android-minimal.json`](fixtures/android-minimal.json)
  - [`fixtures/apple-partial.json`](fixtures/apple-partial.json)
  - [`fixtures/android-not-requested.json`](fixtures/android-not-requested.json)
  - [`fixtures/apple-whoop.json`](fixtures/apple-whoop.json)

The additional fixtures cover a 25-hour DST owner day, partial and successful-empty resources, deliberate not-requested capture, and nested WHOOP schema reuse. These fixtures contain no production health data, user identity, credentials, provider URLs, cursors, or raw error bodies.
