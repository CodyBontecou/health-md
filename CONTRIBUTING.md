# Contributing to Health.md

## Choose a component

Work within the smallest affected component:

- `apps/apple` — Swift/Xcode apps and Apple-side services
- `apps/android` — Kotlin/Gradle app
- `apps/cli` — Rust CLI workspace
- `apps/website` — website and documentation
- `packages/contracts` — shared public schemas and interoperability fixtures
- `packages/healthmd-core-rust` — shared Rust core, UniFFI tooling, and direct protocol

Read the repository-root and nearest component `AGENTS.md` files before making changes.

## Commands

Use native component tooling or the repository-root convenience targets:

```bash
make test-contracts
make test-core
make core-bindings
make check-core-bindings
make test-apple
make test-android
make test-cli
make test-website
```

Keep dependency updates and lockfile changes scoped to the component that needs them. In particular, `apps/cli/Cargo.lock` and `packages/healthmd-core-rust/Cargo.lock` are independently owned and must not be regenerated as a pair merely because the CLI consumes a path dependency from the core workspace.

## Public contracts

Exporter shapes and direct-device protocols have multiple producers and consumers. Start with the [`packages/contracts` manifest](packages/contracts/manifest.json), identify affected Apple, Android, CLI, website, and external Obsidian-plugin behavior, update versioned fixtures intentionally, and run all affected compatibility tests. Never refresh a schema fingerprint or interoperability vector merely to silence CI.

## Pull requests

- Keep structural migration, product behavior, and contract extraction in separate changes.
- Include the component name in the title when practical.
- Document tests run and any physical-device or deployment checks not run.
- Do not commit credentials, signing files, health data, local agent state, or generated build output.
