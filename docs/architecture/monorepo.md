# Health.md monorepo architecture

## Status

Implementation began on 2026-07-24. The existing `CodyBontecou/health-md` repository remains canonical. Apple, CLI, Android, and website histories have been imported on `chore/monorepo-foundation`; deployment and old-repository cutover remain pending.

The monorepo contains four independently built and released products:

- Apple apps under `apps/apple`
- Android app under `apps/android`
- Rust CLI under `apps/cli`
- Website under `apps/website`

Shared implementation and contracts are separate from those product workspaces:

- Rust export core, UniFFI tooling, and the direct-protocol crate under `packages/healthmd-core-rust`
- language-neutral specifications and compatibility fixtures under `packages/contracts`

The Obsidian plugin remains an external repository and integration.

## Principles

1. Preserve source history and release provenance.
2. Keep native build systems and component lockfiles.
3. Version and release products independently.
4. Make CI path-aware without hiding required checks.
5. Separate repository migration from schema/protocol consolidation.
6. Keep public export and direct-protocol compatibility explicit and testable.
7. Keep Apple and Android product capabilities and public semantics unified whenever OS APIs permit; document unavoidable divergence rather than fabricating parity.

The governing cross-platform workflow is [Apple and Android unification policy](cross-platform-unification-policy.md). It requires a platform-neutral outcome, both-platform API analysis, a capability/mapping classification, common contracts for proven equivalence, and explicit platform sections or unavailable/planned states for OS limitations.

## History strategy

The Apple project is moved with `git mv`, preserving the existing canonical history. Other default branches are imported from temporary clones using `git filter-repo --to-subdirectory-filter`. Imported commit hashes change so historical paths live at their final monorepo locations; commit maps are retained under `docs/migration/commit-maps` and original repositories remain available for old permalinks.

Source repositories are not force-pushed or rewritten. After validation and cutover, they can be made read-only with a pointer to this repository.

## Build organization

The root Makefile is a command router, not a replacement build system. Each component owns its dependencies, lockfiles, generated files, and release metadata.

`apps/cli` and `packages/healthmd-core-rust` are independent Cargo workspaces. Each keeps its own `Cargo.lock` and `target` directory; aggregate commands invoke them separately rather than creating a repository-wide Cargo workspace. The CLI consumes the shared `healthmd-protocol` crate by path during development and by exact crates.io version when packaged.

The separately reviewed contracts workstream centralizes language-neutral direct-protocol specifications and interoperability vectors under `packages/contracts`. Milestone 1 moves the existing Rust protocol implementation into the shared-core workspace and establishes the Rust/UniFFI build boundary without changing protocol bytes or public export schemas. The canonical metric registry now keeps profiles explicit, and the internal semantic-input v1 layer moves bounded post-capture filtering/reduction into Rust without changing native SDK access or public rendering. See [ADR-0001](adr-0001-shared-rust-uniffi-core.md), the [M4 semantic baseline](shared-core-m4-semantic-baseline.md), the [M5 rendering baseline](shared-core-m5-rendering-baseline.md), the [M6 rollout baseline](shared-core-m6-rollout-baseline.md), the [M6 rollout/rollback runbook](shared-core-m6-rollout-runbook.md), the [M7 direct-protocol baseline](shared-core-m7-protocol-baseline.md), the [historical unified-v8 deferral](rfc-0002-unified-health-data-v8.md), the [unified-v9 proposal](rfc-0004-unified-health-data-v9.md), and the [cross-platform unification policy](cross-platform-unification-policy.md).

## CI

Repository-root workflows detect affected paths and invoke component jobs. A final always-running gate reports the aggregate result. Changes to shared contracts run Apple, Android, CLI, website, and relevant external-integration checks. Changes under `packages/healthmd-core-rust` run the core gate and every Apple, Android, CLI, and website consumer gate.

The shared-core workspace is not a fifth product release. `healthmd-protocol` is staged from that workspace before the exact-version CLI crates during the protected CLI crates.io workflow.

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

- Shared Rust core: formatting, MSRV, tests, clippy, contract vectors, and host binding-generation checks pass in its independently locked workspace.
- CLI: formatting, Cargo metadata, cargo-dist plan, and all CLI-workspace tests pass against the shared protocol path dependency.
- Android: Gradle unit and direct-protocol tests pass with the local Android SDK.
- Website: external-plugin asset regeneration is reproducible; tests, reference checks, docs link checks, and the production build pass.
- Apple: Xcode resolves the relocated project and packages; monorepo workflow/preflight test suites pass. A complete macOS suite run was attempted but did not finish within the local timeout while Xcode repeatedly queried a passcode-locked physical device.
