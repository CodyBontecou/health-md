# Health.md

Health.md is a local-first health data platform. This repository is the canonical source for the Apple apps, Android app, standalone CLI, and website.

## Agent skill

Install the [consumer-facing Health.md CLI skill](https://skills.sh/CodyBontecou/health-md/healthmd-cli) for bounded, privacy-aware CLI and MCP workflows:

```bash
npx skills add CodyBontecou/health-md@healthmd-cli
```

The skill teaches agents to request the smallest user-authorized scope, preserve units and missingness, query typed iPhone data, handle iPhone and Android exports truthfully, and recover durable jobs without exposing raw health records. Installing the skill does not install the `healthmd` binaries or grant access to a phone. Review the [skill source](.agents/skills/healthmd-cli/SKILL.md) and the [CLI preview status](apps/cli/README.md) before use.

## Repository layout

| Path | Product | Toolchain |
| --- | --- | --- |
| [`apps/apple`](apps/apple) | iOS, iPadOS, macOS, watchOS, and widgets | Xcode / Swift |
| [`apps/android`](apps/android) | Android app and direct protocol client | Gradle / Kotlin |
| [`apps/cli`](apps/cli) | Portable `healthmd` CLI | Cargo / Rust |
| [`apps/website`](apps/website) | Product website and documentation | Node.js / Astro |
| [`packages/contracts`](packages/contracts) | Cross-platform schemas and compatibility fixtures | Language-neutral |
| [`packages/healthmd-core-rust`](packages/healthmd-core-rust) | Shared export core, UniFFI binding tooling, and direct protocol | Cargo / Rust |

The [Health.md Obsidian plugin](https://github.com/CodyBontecou/health-md-visualizations) remains in its own repository and is treated as an external integration.

## Development

Each product keeps its native build system and lockfiles. The root `Makefile` provides convenience commands without replacing component tooling.

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

See each component's README and `AGENTS.md` for platform-specific setup and release instructions.

## Cross-platform product policy

Health.md keeps Apple and Android unified whenever their operating systems expose semantically compatible capabilities. Shared features should align user outcomes, terminology, settings semantics, public IDs, units, reducers, missingness, provenance, completeness, and automation behavior. Native UI and implementation may follow platform conventions.

When the operating systems differ, Health.md represents that difference explicitly instead of fabricating parity. Unsupported data is omitted/reported unavailable, temporary gaps are tracked as planned with a target, and related-but-different values—such as HealthKit HRV SDNN and Health Connect/WHOOP RMSSD—keep distinct identities.

The governing workflow and definition of done are in [`docs/architecture/cross-platform-unification-policy.md`](docs/architecture/cross-platform-unification-policy.md).

The product-wide feature baseline lives in [`docs/features/feature-inventory.md`](docs/features/feature-inventory.md): every feature across Apple, Android, CLI, core, contracts, practice, and website surfaces, with source evidence, per-feature documentation status, and the gap list used to manage documentation. Update it when adding a feature. Per-capability Apple↔Android pairings and honest parity classifications live in [`docs/features/feature-parity.md`](docs/features/feature-parity.md).

## Public contracts

Health.md exports and the direct-device protocol are long-lived compatibility contracts used across Apple, Android, the CLI, website documentation, and external integrations. Contract changes must update fixtures and run every affected consumer's compatibility tests.

See [`apps/apple/docs/features/export-schema.md`](apps/apple/docs/features/export-schema.md) for the current Apple export contract and [`apps/android/docs/export-contract/migration-plan.md`](apps/android/docs/export-contract/migration-plan.md) for Android compatibility profiles. Normative direct-protocol specifications, interoperability vectors, and the cross-product contract inventory live in [`packages/contracts`](packages/contracts). Their shared Rust implementation and canonical metric/profile registry live in [`packages/healthmd-core-rust`](packages/healthmd-core-rust); moving deterministic metadata there does not change protocol bytes or public export schemas.

Apple v8, Android frozen v4, and Android analytical v5 remain explicit historical/current profiles. The proposed common successor is [`healthmd.health_data` v9](packages/contracts/proposals/unified-health-data-v9/contract.md); it unifies truthful shared semantics while preserving independently versioned platform sections for OS-specific data.

## License

Licensing is documented in [`LICENSES.md`](LICENSES.md). Apple, Android, CLI, and shared-core Rust source are AGPL-3.0-only; the website is MIT-licensed.
