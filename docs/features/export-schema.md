# Export schema contract

Health.md exports are intended to be durable files that people can keep in Obsidian, scripts, spreadsheets, and archives for years. Every exported format identifies the schema it uses:

- Markdown / Obsidian Bases frontmatter:
  ```yaml
  schema: healthmd.health_data
  schema_version: 4
  time_context:
    calendar_timezone: America/Los_Angeles
    timestamp_timezone: UTC
  ```
- JSON:
  ```json
  {
    "schema": "healthmd.health_data",
    "schema_version": 4,
    "time_context": {
      "calendar_timezone": "America/Los_Angeles",
      "timestamp_timezone": "UTC"
    },
    "unit_system": "metric",
    "units": {
      "active_calories": "kcal"
    }
  }
  ```
- CSV metadata rows:
  ```csv
  Date,Category,Metric,Value,Unit,Timestamp
  2026-06-14,Metadata,schema,healthmd.health_data,,
  2026-06-14,Metadata,schema_version,4,,
  2026-06-14,Metadata,unit_system,metric,,
  2026-06-14,Metadata,time_context.calendar_timezone,America/Los_Angeles,,
  2026-06-14,Metadata,time_context.timestamp_timezone,UTC,,
  ```

## Version 4 live schema

`schema_version: 4` is the current Health.md export schema. It includes stable canonical units, self-describing metadata, the data dictionary, roll-up rules, richer medication inventory and dose-event details, explicit timezone context, and lossless HealthKit workout activity identity.

### Timestamp and calendar timezone contract

Every daily record captures its calendar timezone when HealthKit data is fetched. That context survives iPhone-to-Mac transfer and delayed serialization:

- `time_context.calendar_timezone` is an IANA timezone identifier used for the top-level `date`, daily boundaries, and human-readable clock fields such as `bedtime`, `wakeTime`, and workout display times.
- `time_context.timestamp_timezone` is always `UTC`.
- Complete machine-readable timestamps such as `bedtimeISO`, `startDate`, `endDate`, and granular heart, vitals, or workout sample timestamps use RFC 3339 / ISO 8601 UTC values ending in `Z`.
- HealthKit metadata such as `HKTimeZone` describes an individual source sample. It is preserved unchanged and may differ from the daily record's calendar timezone, particularly during travel.
- Records created before schema v3 did not capture this context. When one is decoded, Health.md captures the current device timezone once as a compatibility fallback and includes it in subsequent exports.

For example, `2026-07-10T07:21:29Z` and a bedtime of `00:21` are the same instant when `calendar_timezone` is `America/Los_Angeles` during daylight saving time. Consumers should compare and sort complete UTC timestamps, then convert them into `calendar_timezone` for display.

Structured export data uses stable canonical units regardless of the user's Metric/Imperial display preference.

- Markdown / Obsidian Bases frontmatter values are canonical and the frontmatter `units:` map names their units.
- JSON values and `units` are canonical. `unit_system` describes the stored data and is therefore `metric`. JSON distance objects keep raw meter values and may also emit explicit derived variants such as `distanceKm` and `distanceMi` together.
- CSV values use canonical units in the `Unit` column and `unit_system` is `metric`; activity and workout distances are stored as meters unless the row name/unit explicitly says otherwise.
- Human-readable Markdown prose may still render values in the user's selected display units, such as pounds, miles, feet, and Fahrenheit.
- Distance frontmatter keys with explicit unit suffixes, such as `walking_running_km` and `walking_running_mi`, are emitted together when enabled so key presence does not depend on display preference.

A frontmatter key's unit suffix is authoritative. For example, `weight_kg` is always kilograms, `height_m` is always meters, `water_l` is always liters, and temperature fields are always Celsius unless a future key explicitly names another unit.

The generated data dictionary also documents per-key daily and period roll-up semantics for every exported frontmatter key. See [Data dictionary and roll-up rules](./data-dictionary.md) for the full user-facing guide. Each `_healthmd_data_dictionary.json` entry includes:

- `dailyAggregation` / `aggregation` — how the daily value is produced for that exact key, e.g. `sum`, `average`, `minimum`, `maximum`, `latest`, `duration_sum`, `count`, `list`, or `category_latest`.
- `healthKitAggregation` — the broader source metric aggregation declared by Health.md's HealthKit metric definition.
- `rollup.primary` — the headline operation weekly/monthly/yearly summaries should use.
- `rollup.statistics` — additional statistics summaries should emit or preserve, such as `days_counted`, `daily_average`, `latest`, or `value_counts`.
- `rollup.periods` — the summary periods the rule applies to; currently `weekly`, `monthly`, and `yearly`.
- `rollup.preferredSource`, `rollup.weightedBy`, and `rollup.notes` — provenance and caveats for richer summaries, especially workout metrics that should be duration-weighted when workout details are available.

### Workout activity identity contract

Workout exports keep separate human, canonical, and HealthKit source identities:

- `type` in JSON and `activity_type` in frontmatter are stable English display names, such as `Rolling`.
- `sport` is Health.md's machine-friendly slug, such as `rolling`.
- `healthKitActivityType` in JSON and `healthkit_activity_type` in frontmatter contain the HealthKit Swift case name known to the app's SDK. Apple Watch's Rolling activity is `preparationAndRecovery`.
- `healthKitActivityTypeRawValue` in JSON and `healthkit_activity_type_raw_value` in frontmatter preserve the original numeric `HKWorkoutActivityType` value. Rolling has raw value `33`.
- CSV emits `Workout Activity Type`, `Workout Sport`, `HealthKit Activity Type`, and `HealthKit Activity Type Raw Value` rows. Their `Timestamp` column contains the workout's UTC start timestamp so rows from multiple workouts can be associated reliably.

Health.md exports every activity known to its current HealthKit SDK using these fields. If a future HealthKit version supplies an unknown raw value, the display name is `Unknown HealthKit Activity`, the sport slug is `healthkit-<raw-value>`, the symbolic HealthKit case is omitted, and the raw value remains present. This is distinct from Apple's explicit HealthKit `other` activity, whose display name is `Other`, sport is `other`, symbolic case is `other`, and raw value is `3000`.

Records decoded from older Health.md data may omit the HealthKit source fields because those records did not retain the original raw value.

## API Endpoint envelope

API Endpoint export POSTs a wrapper envelope with `schema: healthmd.api_export` and `schema_version: 1`. The `records` array inside that envelope contains ordinary daily JSON records using `schema: healthmd.health_data` and the current `HealthMdExportSchema.version`.

Connected-app provider sidecars and the API envelope v2 fields are deferred behind `ConnectedAppsFeature.isEnabled == false`. When that feature is intentionally revived, adding `external_records` changes the API envelope contract only; it does not change daily Markdown, Bases, JSON, CSV, or data dictionary output, so it does not require a daily export schema bump.

## Schema version policy

`HealthMdExportSchema.version` is the production export schema integer. Schema version `4` is the current public contract for versioned exports. Schema versions `1`, `2`, and `3` remain preserved by their fixtures for compatibility checks and historical reference.

Increment the schema version when the current public contract changes. During pre-production rollout hardening for an unshipped schema, keep the version number fixed only when the release owner explicitly chooses to fold those changes into that same versioned contract.

After a schema version has shipped, bump by one when any of these change:

- an exported key is renamed or removed;
- a value changes meaning, type, aggregation, or unit;
- JSON structure changes, including top-level metadata shape;
- CSV columns, metadata rows, categories, metric labels, or row semantics change;
- Markdown / Obsidian Bases reserved frontmatter keys change;
- the generated data dictionary changes in a way downstream tools must understand.

Do not bump for purely internal refactors that preserve byte-compatible output shape and semantics, or for pre-production edits to a schema version that has not shipped yet.

## Automated guardrail

`HealthMdTests/Export/ExportSchemaSignatureTests.swift` builds a canonical export-schema fingerprint from:

- JSON shape paths for the full-day fixture;
- CSV header and row contracts;
- Markdown and Obsidian Bases top-level frontmatter keys;
- the full metric data dictionary in both metric and imperial unit systems.

The committed fixture lives at the current schema-versioned path, for example:

```text
HealthMdTests/Fixtures/Export/export_schema_signature_v4.json
```

If exporter output changes after a schema version has shipped and `HealthMdExportSchema.version` was not bumped, the test fails. The update path intentionally refuses to overwrite the fixture for the same version with a different fingerprint so accidental drift is visible. For unshipped pre-production schema changes, rerun the update with `ALLOW_UNSHIPPED_SCHEMA_SIGNATURE_REWRITE=1` and review the current version fixture diff.

## Release rollout checklist

Before enabling schema-affecting behavior broadly in a release, run a mixed-export compatibility smoke test:

1. Start from an existing flat Health.md export folder with daily Markdown, Obsidian Bases, JSON, CSV, and `_healthmd_data_dictionary.json` files.
2. Re-export one old date and one new date with the default settings; confirm roll-up summaries and format folders remain off unless explicitly enabled.
3. Enable format folders and roll-up summaries in a copy of the vault; confirm daily records still use `healthmd.health_data`, roll-up files use `healthmd.rollup_summary`, and the data dictionary remains at the shared Health folder root.
4. Open the mixed folder in the current Obsidian plugin before launch, then verify the plugin upgrade path before recommending these opt-ins to existing users.
5. App Store / in-app release notes must mention versioned exports, existing-file compatibility, and updating the Obsidian plugin before enabling roll-ups or format folders.

## Intentional schema change workflow

1. Change the exporters / metric dictionary.
2. Decide whether the current schema version has already shipped to production.
3. If the current schema version is already in production, bump `HealthMdExportSchema.version` in `HealthMd/Shared/Export/HealthMetricsDictionary.swift` before updating fixtures. If it has not shipped yet, either keep the version number unchanged for a deliberate pre-production rewrite or bump it when the release owner wants a new public contract.
4. Run one of:
   ```bash
   make update-export-schema-signature
   # For reviewed pre-production edits to an unshipped schema version only:
   ALLOW_UNSHIPPED_SCHEMA_SIGNATURE_REWRITE=1 make update-export-schema-signature
   ```
5. Review the `export_schema_signature_v<version>.json` fixture diff.
6. Run relevant exporter contract tests.

This makes schema changes explicit for humans, CI, and coding agents.
