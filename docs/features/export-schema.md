# Export schema contract

Health.md exports are intended to be durable files that people can keep in Obsidian, scripts, spreadsheets, and archives for years. Every exported format identifies the schema it uses:

- Markdown / Obsidian Bases frontmatter:
  ```yaml
  schema: healthmd.health_data
  schema_version: 1
  ```
- JSON:
  ```json
  {
    "schema": "healthmd.health_data",
    "schema_version": 1,
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
  2026-06-14,Metadata,schema_version,1,,
  2026-06-14,Metadata,unit_system,metric,,
  ```

## Schema version policy

`HealthMdExportSchema.version` is an integer. Start at `1`; bump by one when the public export contract changes.

Bump the schema version when any of these change:

- an exported key is renamed or removed;
- a value changes meaning, type, aggregation, or unit;
- JSON structure changes, including top-level metadata shape;
- CSV columns, metadata rows, categories, metric labels, or row semantics change;
- Markdown / Obsidian Bases reserved frontmatter keys change;
- the generated data dictionary changes in a way downstream tools must understand.

Do not bump for purely internal refactors that preserve byte-compatible output shape and semantics.

## Automated guardrail

`HealthMdTests/Export/ExportSchemaSignatureTests.swift` builds a canonical export-schema fingerprint from:

- JSON shape paths for the full-day fixture;
- CSV header and row contracts;
- Markdown and Obsidian Bases top-level frontmatter keys;
- the full metric data dictionary in both metric and imperial unit systems.

The committed fixture lives at:

```text
HealthMdTests/Fixtures/Export/export_schema_signature_v1.json
```

If exporter output changes and `HealthMdExportSchema.version` was not bumped, the test fails. The update path intentionally refuses to overwrite the fixture for the same version with a different fingerprint.

## Intentional schema change workflow

1. Change the exporters / metric dictionary.
2. Bump `HealthMdExportSchema.version` in `HealthMd/Shared/Export/HealthMetricsDictionary.swift`.
3. Run:
   ```bash
   make update-export-schema-signature
   ```
4. Review the new `export_schema_signature_v<version>.json` fixture diff.
5. Run relevant exporter contract tests.

This makes schema changes explicit for humans, CI, and coding agents.
