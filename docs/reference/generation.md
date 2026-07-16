# Generated documentation workflow

Health.md's complete examples and exhaustive reference tables are generated from production code. They are committed so readers can browse them without Xcode, and checked so they cannot silently drift.

## Why generated artifacts

Hand-written examples tend to become inaccurate when:

- a conditional field is added;
- a unit or aggregation rule changes;
- a specialized record gains a public field;
- an API/control response adds a state;
- filename collision behavior changes;
- CSV escaping or row shape changes.

The generator executes the same serializers used by the app and CLI against deterministic synthetic inputs.

## Source inputs

Generated references draw from:

- `HealthMetrics.all` and `HealthMetricDataDictionary.entries`;
- `HealthMetricExportMapping` and reviewed archive-only metrics;
- actual JSON, CSV, Markdown, and Bases exporters;
- `HealthKitRecordArchiveSerializer`;
- `IndividualEntryExporter`;
- roll-up generators/exporters;
- API Endpoint and strict raw envelope serializers;
- localhost control and connected-sync Codable models;
- HealthMdCLI's actual request building, validation, and exit-code logic;
- fixed synthetic fixtures under `HealthMdTests/Fixtures/Documentation`.

The generator does not scrape real Apple Health data.

## Commands

The repository exposes one aggregate Make target plus focused scripts:

```bash
make generate-export-docs
make check-export-docs
```

Focused scripts support `update` and `check` modes:

```bash
scripts/generated-export-docs.sh update
scripts/generated-export-docs.sh check
scripts/generated-cli-reference-docs.sh update
scripts/generated-cli-reference-docs.sh check
scripts/generated-individual-entry-docs.sh update
scripts/generated-individual-entry-docs.sh check
scripts/generated-rollup-reference-docs.sh update
scripts/generated-rollup-reference-docs.sh check
scripts/generated-automation-reference-docs.sh update
scripts/generated-automation-reference-docs.sh check
```

`update` replaces only the corresponding generated subtree. `check` regenerates into temporary output and byte-compares it with committed artifacts.

## Determinism

Fixtures use:

- fixed UTC timestamps;
- fixed UUIDs and external identities;
- stable synthetic source/device values;
- POSIX locale and UTC process timezone;
- deterministic array/key sorting;
- actual canonical timestamp/CSV escaping logic;
- SHA-256 manifests.

Running update twice without source changes must produce no diff.

## Coverage gates

Generated tests assert coverage beyond snapshot comparison:

- every metric definition appears in the catalog;
- every mapped summary key appears in the data dictionary;
- reviewed archive-only metrics remain explicitly identified;
- all canonical record kinds and payload variants have examples;
- every typed metadata case is exercised;
- every query status and diagnostic family is exercised;
- JSON and CSV canonical UUIDs agree;
- CSV reflects production five/six-field row behavior;
- canonical Individual Entry filenames include metric and lowercase UUID;
- roll-up rule families have examples;
- generated JSON parses and CSV passes an RFC 4180 parser;
- current v6 signature remains unchanged.

## Schema guardrail

Documentation generation must never rewrite a shipped schema signature. If production output intentionally changes, follow the repository's schema workflow first:

1. decide whether the public contract changed;
2. bump the schema version when required;
3. generate a new versioned signature fixture;
4. review the fixture diff;
5. regenerate reference artifacts;
6. update prose and migration guidance.

Do not modify `export_schema_signature_v6.json` merely to make generated docs pass.

## Reviewing generated diffs

A generated diff is a contract-review signal. Check:

- which production symbol changed;
- whether keys/types/units/meaning changed;
- whether the correct schema version is declared;
- whether optionality and compatibility are preserved;
- whether JSON/CSV/Markdown/Bases remain consistent with their documented roles;
- whether API, CLI, and connected envelopes can still be parsed by older consumers.

Generated manifests list artifact hashes and fixture coverage to make large reviews manageable.

## Synthetic data rules

Synthetic values should:

- stay within plausible domain ranges unless testing an explicit edge case;
- use reserved fixture identities rather than random UUIDs;
- never resemble a real person's complete history;
- include punctuation/newlines where escaping is part of the contract;
- cover null, empty, partial, unsupported, cancelled, and failure states;
- remain stable across machines.

## Adding a new export field

1. Add or change the production source definition/serializer.
2. Update the deterministic synthetic corpus so the field is exercised.
3. Run the schema-contract decision process.
4. Run `make generate-export-docs`.
5. Review generated path/type, example, metric, and manifest diffs.
6. Add prose only for semantics not evident from the generated structure.
7. Run `make check-export-docs` and focused/full tests.

## Adding a new metric

A new metric should appear automatically in the generated catalog. The coverage test fails if its summary/archive-only status, dictionary mapping, or catalog coverage is unresolved.

## Generated versus hand-written content

Generated files are complete contract showcases. Hand-written pages explain intent, authority, limitations, privacy, and parser behavior. Do not manually edit files below `docs/reference/generated/`; the next update will replace them.
