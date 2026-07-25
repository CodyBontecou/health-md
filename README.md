# Health.md

Health.md is a local-first health data platform. This repository is the canonical source for the Apple apps, Android app, standalone CLI, and website.

## Repository layout

| Path | Product | Toolchain |
| --- | --- | --- |
| [`apps/apple`](apps/apple) | iOS, iPadOS, macOS, watchOS, and widgets | Xcode / Swift |
| [`apps/android`](apps/android) | Android app and direct protocol client | Gradle / Kotlin |
| [`apps/cli`](apps/cli) | Portable `healthmd` CLI | Cargo / Rust |
| [`apps/website`](apps/website) | Product website and documentation | Node.js / Astro |
| [`packages/contracts`](packages/contracts) | Cross-platform schemas and compatibility fixtures | Language-neutral |

The [Health.md Obsidian plugin](https://github.com/CodyBontecou/health-md-visualizations) remains in its own repository and is treated as an external integration.

## Development

Each product keeps its native build system and lockfiles. The root `Makefile` provides convenience commands without replacing component tooling.

```bash
make test-apple
make test-android
make test-cli
make test-website
```

See each component's README and `AGENTS.md` for platform-specific setup and release instructions.

## Public contracts

Health.md exports and the direct-device protocol are long-lived compatibility contracts used across Apple, Android, the CLI, website documentation, and external integrations. Contract changes must update fixtures and run every affected consumer's compatibility tests.

See [`apps/apple/docs/features/export-schema.md`](apps/apple/docs/features/export-schema.md) for the current export contract. Shared, language-neutral contract assets will move into [`packages/contracts`](packages/contracts) in a separate migration phase.

## License

Licensing is documented in [`LICENSES.md`](LICENSES.md). Apple, Android, and CLI source are AGPL-3.0-only. The website's licensing scope must be explicitly decided as part of its import.
