# Export schema contract

Health.md exports are intended to be durable files that people can keep in Obsidian, scripts, spreadsheets, and archives for years. Every exported format identifies the schema it uses:

- Markdown / Obsidian Bases frontmatter:
  ```yaml
  schema: healthmd.health_data
  schema_version: 2
  ```
- JSON:
  ```json
  {
    "schema": "healthmd.health_data",
    "schema_version": 2,
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
  2026-06-14,Metadata,schema_version,2,,
  2026-06-14,Metadata,unit_system,metric,,
  ```

## Version 2 live schema

`schema_version: 2` is the current Health.md export schema. It includes stable canonical units, self-describing metadata, the data dictionary, roll-up rules, and richer medication inventory and dose-event details.

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

## API Endpoint envelope

API Endpoint export POSTs a wrapper envelope with `schema: healthmd.api_export` and `schema_version: 1`. The `records` array inside that envelope contains ordinary daily JSON records using `schema: healthmd.health_data` and the current `HealthMdExportSchema.version`.

Connected-app provider sidecars and the API envelope v2 fields are deferred behind `ConnectedAppsFeature.isEnabled == false`. When that feature is intentionally revived, adding `external_records` changes the API envelope contract only; it does not change daily Markdown, Bases, JSON, CSV, or data dictionary output, so it does not require a daily export schema bump.

## Schema version policy

`HealthMdExportSchema.version` is the production export schema integer. Schema version `2` is the current public contract for versioned exports. Schema version `1` remains preserved by its fixture for compatibility checks and historical reference.

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
HealthMdTests/Fixtures/Export/export_schema_signature_v2.json
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
