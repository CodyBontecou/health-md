# healthmd-core

Deterministic post-capture semantics, rendering and scoped Markdown note merging for Health.md.
This library does not access health APIs, devices, files, credentials or networks. Apple and Android
native adapters and the portable CLI use the same profile-specific rules.

The crate includes its versioned registries and conformance fixtures. Contract fixture copies under
`tests/fixtures/contracts` are generated from canonical `packages/contracts` sources with
`python3 packages/healthmd-core-rust/scripts/update-package-fixtures.py`; `--check` verifies byte identity. Public export profiles retain
independent versions; the crate version does not redefine historical export bytes or meanings.

Licensed under AGPL-3.0-only. Source and component documentation: https://github.com/CodyBontecou/health-md/tree/main/packages/healthmd-core-rust.
