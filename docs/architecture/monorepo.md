# Health.md monorepo architecture

## Status

Implementation began on 2026-07-24. The existing `CodyBontecou/health-md` repository remains canonical. Apple, CLI, Android, and website histories have been imported on `chore/monorepo-foundation`; deployment and old-repository cutover remain pending.

The monorepo contains four independently built and released products:

- Apple apps under `apps/apple`
- Android app under `apps/android`
- Rust CLI under `apps/cli`
- Website under `apps/website`

The Obsidian plugin remains an external repository and integration.

## Principles

1. Preserve source history and release provenance.
2. Keep native build systems and component lockfiles.
3. Version and release products independently.
4. Make CI path-aware without hiding required checks.
5. Separate repository migration from schema/protocol consolidation.
6. Keep public export and direct-protocol compatibility explicit and testable.

## History strategy

The Apple project is moved with `git mv`, preserving the existing canonical history. Other default branches are imported from temporary clones using `git filter-repo --to-subdirectory-filter`. Imported commit hashes change so historical paths live at their final monorepo locations; commit maps are retained under `docs/migration/commit-maps` and original repositories remain available for old permalinks.

Source repositories are not force-pushed or rewritten. After validation and cutover, they can be made read-only with a pointer to this repository.

## Build organization

The root Makefile is a command router, not a replacement build system. Each component owns its dependencies, lockfiles, generated files, and release metadata.

Shared code is not extracted during the import. Language-neutral export schemas, protocol vectors, and compatibility fixtures can move to `packages/contracts` after all original tests pass from their new paths.

## CI

Repository-root workflows detect affected paths and invoke component jobs. A final always-running gate reports the aggregate result. Changes to shared contracts run Apple, Android, CLI, website, and relevant external-integration checks.

Component release workflows use non-overlapping tag patterns:

- Apple: `v*`
- CLI: `healthmd-cli/v*`
- Android: `android/v*`

Website production deploys are commit-based. Non-Apple releases must not become or depend on the repository-wide latest release.

## Migration gates

1. [x] Record clean source revisions and commit maps.
2. [x] Move Apple to `apps/apple` and update repository-root workflow paths.
3. [x] Import CLI history and adapt Cargo/CI release paths.
4. [x] Import Android history and add Gradle CI.
5. [x] Import the website and replace Apple cross-checkouts with local paths.
6. [ ] Review the migration branch in GitHub and update required checks/secrets.
7. [ ] Set Vercel's Root Directory to `apps/website` and verify a production-equivalent preview.
8. [ ] Perform Apple and CLI release dry runs.
9. [ ] Merge the migration and update/archive old development repositories after cutover.
10. [ ] Extract shared contracts in a separate change.

## Local validation

- CLI: formatting, Cargo metadata, cargo-dist plan, and all workspace tests pass.
- Android: Gradle unit and direct-protocol tests pass with the local Android SDK.
- Website: external-plugin asset regeneration is reproducible; tests, reference checks, docs link checks, and the production build pass.
- Apple: Xcode resolves the relocated project and packages; monorepo workflow/preflight test suites pass. A complete macOS suite run was attempted but did not finish within the local timeout while Xcode repeatedly queried a passcode-locked physical device.
