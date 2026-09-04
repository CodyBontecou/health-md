# Health.md Monorepo Agent Instructions

## Repository structure

- `apps/apple`: iOS, macOS, watchOS, widgets, and Apple-side direct services.
- `apps/android`: Android app and Kotlin direct protocol implementation.
- `apps/cli`: standalone Rust CLI and client crates.
- `apps/practice`: separately governed clinician portal and future clinical service boundary.
- `apps/wake`: notification-only Direct CLI wake Worker and isolated D1 service; never a health-data path.
- `apps/website`: website and generated product documentation.
- `packages/contracts`: language-neutral schemas and interoperability fixtures.
- `packages/healthmd-core-rust`: shared Rust core, UniFFI tooling, and direct-protocol crate.

Read the nearest component `AGENTS.md` before changing files in a component. Keep component build commands, lockfiles, and generated artifacts scoped to that component.

## Cross-platform product and contract policy

Apple and Android should remain unified whenever their operating systems expose semantically compatible capabilities. Read `docs/architecture/cross-platform-unification-policy.md` before changing a mobile feature, metric, setting, export, API behavior, automation surface, or public terminology.

Default rules:

- Define the platform-neutral user/consumer outcome before native implementation details.
- Inspect both Apple and Android APIs and update both implementations when semantics permit.
- Use shared semantic IDs, canonical units, reducers, capture states, and fixtures only for proven equivalence.
- Record unavoidable OS/API differences explicitly in `packages/contracts/product-capabilities.json`, the metric registry, or an independently versioned platform section.
- Never fabricate parity: unsupported data is omitted/reported unavailable, and related-but-different statistics keep distinct identities.
- A one-platform implementation of an otherwise shared capability must mark the other platform `planned` with a concrete target or document why it is unavailable.

Health.md exports and direct-device protocols are public, long-lived contracts. When changing exporter mappings, units, schemas, protocol models, wire formats, fixtures, or consumer compatibility:

1. Read `docs/architecture/cross-platform-unification-policy.md`, `apps/apple/docs/features/export-schema.md`, and the relevant Android/protocol documentation.
2. Identify every affected producer and consumer: shared Rust core, Apple, Android, CLI, website, and the external Obsidian plugin.
3. Use exact machine-readable classifications with evidence: capabilities use `shared`, `apple_only`, `android_only`, `unavailable`, or `planned`; registry mappings use `platform_exact_or_unavailable`, `mapped_alias`, or `platform_distinct`. A mapping-ledger review state such as `alias-review` does not replace the registry classification.
4. Decide whether the common public export schema, a platform extension/profile, direct protocol version, or only an internal shared-core version changed.
5. For Apple export schema changes, bump `HealthMdExportSchema.version` in `apps/apple/HealthMd/Shared/Export/HealthMetricsDictionary.swift` when required.
6. Run `make -C apps/apple update-export-schema-signature` after an intentional Apple schema version change.
7. Review every affected versioned fixture, including Apple, Android, shared-contract, and external-consumer fixtures.
8. Run all affected Apple, Android, contract, core, CLI, website, API/automation, and external-consumer tests before finishing.

Do not update a schema fixture merely to silence CI. Do not combine contract extraction with repository-structure migrations.

## Releases

Components version and release independently:

- Apple tags: `v<version>`
- CLI tags: `healthmd-cli/v<version>`
- Android tags: `android/v<version>`
- Website: commit-based deployment

The independently locked shared-core workspace is not a fifth product release. When staging CLI crates, publish `healthmd-protocol` from `packages/healthmd-core-rust`, then `healthmd-operations`, `healthmd-client`, `healthmd-mcp`, and `healthmd-cli` from `apps/cli`, waiting for each exact version to propagate before publishing a dependent crate.

GitHub has one repository-wide latest release. Preserve it for Apple releases; non-Apple release automation must not rely on `/releases/latest`.

For Apple App Store releases, follow the complete synchronization contract in `apps/apple/AGENTS.md`. Release only committed and pushed source from a clean worktree, and keep Git tags, GitHub Releases, App Store Connect versions/builds, and customer-facing notes synchronized.

## CI and paths

- Keep GitHub Actions workflows in the repository-root `.github/workflows` directory.
- Use explicit component working directories and component-prefixed cache/artifact paths.
- Keep `apps/cli` and `packages/healthmd-core-rust` as independent Cargo workspaces with independent lockfiles and target directories.
- Keep `apps/practice` isolated from the static website and existing non-PHI Workers; its lockfile, build, tests, deployment configuration, and clinical data boundary remain component-scoped.
- Keep `apps/wake` notification-only, with its own lockfile, D1 migrations, secrets, CI, and deployment configuration; no health payload or request contents may enter the Worker.
- Contract changes must trigger every affected component. Shared-core changes must trigger the core, Apple, Android, CLI, and website consumer gates.
- Avoid introducing a repository-wide build framework unless it provides concrete value across Swift, Kotlin, Rust, and Node.js.

## Git

- Never force-push.
- Preserve imported repository history; do not squash source repositories into a single snapshot.
- Keep source revision and history-rewrite maps under `docs/migration/`.
