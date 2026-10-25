# Packaged synthetic producer fixtures

These JSON files are byte-identical copies of reviewed producer fixtures, bundled so published CLI crate tests do not depend on the surrounding monorepo:

- `apple-api-export-v2-provider-sidecar.json`: `apps/apple/docs/reference/generated/automation/api-export-v2-provider-sidecar.json`
- `android-raw-v1-minimal-snapshot.json`: `apps/android/app/src/test/resources/raw-export/v1/minimal-snapshot.json`

`packaged_cross_platform_fixtures_match_reviewed_producer_bytes` checks parity when run in the repository. The packaged-crate smoke checks archive inclusion and runs the same ingest/query tests against the bundled bytes. Do not edit these mirrors independently of their reviewed producer sources.

Refreshing a packaged mirror does not change the producer schema, protocol, registry authority, or production behavior. Preserve historical examples when the current producer profile advances.

`apple-api-export-v2-provider-sidecar-v8.json` preserves the earlier Apple daily-v8 example from commit `ad0e73fac`, while the unversioned mirror follows the current producer (daily v10). Both pass the same lossless provider-sidecar ingestion test; the historical fixture is not regenerated from current writers.
