# Health.md Agent Instructions

## Export schema contract

Health.md export files are a public, long-lived contract for Obsidian, JSON, CSV, and downstream automation.

When editing any exporter, metric mapping, unit mapping, data dictionary, frontmatter key, CSV row/header, or JSON shape:

1. Read `docs/features/export-schema.md`.
2. Decide whether the public export schema changed.
3. If it changed, bump `HealthMdExportSchema.version` in `HealthMd/Shared/Export/HealthMetricsDictionary.swift`.
4. Run `make update-export-schema-signature` to create/update the versioned fixture.
5. Review the fixture diff under `HealthMdTests/Fixtures/Export/export_schema_signature_v<version>.json`.
6. Run exporter contract tests before finishing.

Do **not** update the schema signature fixture just to silence CI. The test intentionally refuses to overwrite a changed fingerprint for the same `schema_version`; bump the schema version for intentional schema changes.
