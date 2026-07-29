# Health.md Monorepo Agent Instructions

## Repository structure

- `apps/apple`: iOS, macOS, watchOS, widgets, and Apple-side direct services.
- `apps/android`: Android app and Kotlin direct protocol implementation.
- `apps/cli`: standalone Rust CLI and client crates.
- `apps/website`: website and generated product documentation.
- `packages/contracts`: language-neutral schemas and interoperability fixtures.
- `packages/healthmd-core-rust`: shared Rust core, UniFFI tooling, and direct-protocol crate.

Read the nearest component `AGENTS.md` before changing files in a component. Keep component build commands, lockfiles, and generated artifacts scoped to that component.

## Cross-platform contract changes

Health.md exports and direct-device protocols are public, long-lived contracts. When changing exporter mappings, units, schemas, protocol models, wire formats, fixtures, or consumer compatibility:

1. Read `apps/apple/docs/features/export-schema.md` and the relevant protocol documentation.
2. Identify every affected producer and consumer: shared Rust core, Apple, Android, CLI, website, and the external Obsidian plugin.
3. Decide whether the public export schema, direct protocol version, or only an internal shared-core version changed.
4. For export schema changes, bump `HealthMdExportSchema.version` in `apps/apple/HealthMd/Shared/Export/HealthMetricsDictionary.swift` when required.
5. Run `make -C apps/apple update-export-schema-signature` after an intentional schema version change.
6. Review the versioned fixture under `apps/apple/HealthMdTests/Fixtures/Export/`.
7. Run all affected contract and consumer tests before finishing.

Do not update a schema fixture merely to silence CI. Do not combine contract extraction with repository-structure migrations.

## Releases

Components version and release independently:

- Apple tags: `v<version>`
- CLI tags: `healthmd-cli/v<version>`
- Android tags: `android/v<version>`
- Website: commit-based deployment

The independently locked shared-core workspace is not a fifth product release. When staging CLI crates, publish `healthmd-protocol` from `packages/healthmd-core-rust` and wait for its exact version to propagate before publishing `healthmd-client` and `healthmd-cli` from `apps/cli`.

GitHub has one repository-wide latest release. Preserve it for Apple releases; non-Apple release automation must not rely on `/releases/latest`.

For Apple App Store releases, follow the complete synchronization contract in `apps/apple/AGENTS.md`. Release only committed and pushed source from a clean worktree, and keep Git tags, GitHub Releases, App Store Connect versions/builds, and customer-facing notes synchronized.

## CI and paths

- Keep GitHub Actions workflows in the repository-root `.github/workflows` directory.
- Use explicit component working directories and component-prefixed cache/artifact paths.
- Keep `apps/cli` and `packages/healthmd-core-rust` as independent Cargo workspaces with independent lockfiles and target directories.
- Contract changes must trigger every affected component. Shared-core changes must trigger the core, Apple, Android, CLI, and website consumer gates.
- Avoid introducing a repository-wide build framework unless it provides concrete value across Swift, Kotlin, Rust, and Node.js.

## Git

- Never force-push.
- Preserve imported repository history; do not squash source repositories into a single snapshot.
- Keep source revision and history-rewrite maps under `docs/migration/`.
