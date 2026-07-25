# Health.md monorepo architecture

## Status

Implementation began on 2026-07-24. The existing `CodyBontecou/health-md` repository remains canonical.

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

1. Record clean source revisions and create backups.
2. Move and validate Apple from `apps/apple`.
3. Import and validate CLI history.
4. Import and validate Android history.
5. Import the website, replace Apple cross-checkouts with local paths, and cut over Vercel's root directory.
6. Verify CI and perform release dry runs.
7. Archive old development repositories only after successful cutover.
8. Extract shared contracts in a separate change.
