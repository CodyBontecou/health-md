# Documentation map

This page locates canonical documentation and source owners. It is not a second database of implemented features, metric counts, release state, or per-page readiness. Follow the relevant source and guide instead of maintaining another copy here.

## Authority

- **Implemented behavior:** owning code, automated tests, schemas, and configuration. Documentation explains workflows and constraints; a prose assertion alone does not prove availability or successful QA.
- **Requirements and intent:** [cross-platform policy](../architecture/cross-platform-unification-policy.md), accepted decisions under [architecture](../architecture/), and versioned public contracts. A disagreement with code requires investigation; cleanup must not silently discard a requirement.
- **Capability classifications:** [`product-capabilities.json`](../../packages/contracts/product-capabilities.json). [Feature parity](feature-parity.md) retains cross-platform rationale and source pairings, not a competing classification ledger.
- **Metric identities and semantics:** the [shared metric registry](../../packages/healthmd-core-rust/crates/healthmd-core/registry/metric-registry-v1.json), with explicit platform distinctions. Similar names do not establish equivalence.
- **Public contracts and fixtures:** the [contract registry](../../packages/contracts/manifest.json) and [contracts README](../../packages/contracts/README.md). Historical profiles and interoperability fixtures remain versioned compatibility evidence.

## Find the maintained document

| Audience or task | Canonical location |
|---|---|
| Customers using Health.md | [Website guide sources and translations](../../apps/website/docs-src/src/content/docs/) |
| Apple workflows and implementation caveats | [Apple documentation index](../../apps/apple/docs/index.md) and [workflow guides](../../apps/apple/docs/features/index.md) |
| Apple field/format reference and generated examples | [Export reference](../../apps/apple/docs/reference/index.md) and [generation workflow](../../apps/apple/docs/reference/generation.md) |
| Apple test development and quality gates | [Testing index](../../apps/apple/docs/testing/README.md) |
| Android workflows and native caveats | [Android workflow guides](../../apps/android/docs/features/index.md) |
| Android compatibility/raw contracts | [Export-contract sources](../../apps/android/docs/export-contract/) |
| Standalone CLI/MCP users and maintainers | [CLI README](../../apps/cli/README.md) and [CLI architecture](../../apps/cli/docs/architecture.md) |
| Shared deterministic semantics and direct protocols | [Shared core README](../../packages/healthmd-core-rust/README.md) and [contract registry](../../packages/contracts/README.md) |
| Practice synthetic runtime and clinical approval boundaries | [Practice README](../../apps/practice/README.md) and [product requirements](../product/practice/README.md) |
| Notification-only Direct CLI wake service | [Wake README](../../apps/wake/README.md) and [worker specification](../architecture/rfc-0005-worker-spec.md) |
| Contributor/consumer agent skills and publication | [Agent skill ownership and installation](../agents/skills.md) |
| Releases and CI | Component `AGENTS.md` files and [workflow index](../../.github/workflows/README.md) |
| Import provenance and source-history maps | [Migration records](../migration/) |

## Maintenance

Update this map when a canonical owner or documentation location changes, not for every implementation change. Update the relevant existing guide when its user workflow changes; create a new guide only for a distinct audience or task that lacks adequate coverage.

Keep task state and temporary session planning in the tracker or ignored agent state. Per-guide editorial readiness belongs with the guide or its publishing workflow, not in another product-wide status table. Video planning is optional commissioned work, not a requirement for every feature.

Generated references and immutable publication snapshots are maintained through their owning generators and drift checks. The repository's [documentation maintenance policy](../../AGENTS.md#documentation-maintenance) governs audits, consolidation, and removal.
