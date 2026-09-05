# Health.md contracts

This package contains language-neutral specifications, interoperability vectors, and a machine-readable inventory for public contracts shared across Health.md products. It does not replace Swift, Kotlin, Rust, or JavaScript build systems.

The package is licensed under the [GNU Affero General Public License v3.0 only](LICENSE) (`AGPL-3.0-only`). Synthetic fixtures and schemas in this directory are distributed under the same terms unless a file carries a more specific notice.

## Contents

| Path | Purpose |
|---|---|
| [`manifest.json`](manifest.json) | Contract versions, ownership, consumers, fixture provenance, and integrity hashes |
| [`product-capabilities.json`](product-capabilities.json) | Machine-readable Apple/Android capability and output-profile inventory |
| [`../healthmd-core-rust/crates/healthmd-core/registry/metric-registry-v1.json`](../healthmd-core-rust/crates/healthmd-core/registry/metric-registry-v1.json) | Rust-owned ordered metric/profile inventory pinned by `manifest.json` |
| [`validate.py`](validate.py) | Standard-library validation for inventories, hashes, mirrors, metric/profile cross-links, and wire-vector invariants |
| [`direct-protocol`](direct-protocol) | Normative direct-device protocol specifications and canonical interoperability vectors |
| [`semantic-input/v1`](semantic-input/v1/contract.md) | Internal post-capture semantic envelope, strict schemas, and synthetic cross-language differential corpus |
| [`render-input/v1`](render-input/v1/contract.md) | Internal profile rendering, artifact-plan, path, merge, API batching, and bounded lossless-stream contract |
| [`shared-setup/v1`](shared-setup/v1/contract.md) | Public bounded Apple/Android portable setup profile, registry-backed metric alias ledger, and non-operative schedule/API destination intent |
| [`agent-data/v1`](agent-data/v1/contract.md) | Public read-only grant, query, and response contracts shared by local and future hosted agent data stores |

## Typed provider contracts

| Path | Purpose |
|---|---|
| [`proposals/provider-sections-v1`](proposals/provider-sections-v1/contract.md) | Canonical typed, namespaced WHOOP provider section for Apple `healthmd.health_data` v8; the historical proposal path is retained for stable links |
| [`proposals/unified-health-data-v9`](proposals/unified-health-data-v9/contract.md) | Proposed unified Apple/Android daily contract with exact typed metrics, provenance, capture completeness, platform sections, mapping ledger, schema, and synthetic fixtures; no production writer is approved yet |

Run the package checks from the repository root:

```bash
python3 packages/contracts/validate.py
# or
make test-contracts

# Product capability/profile parity only
make test-product-parity
```

## Ownership states

The manifest distinguishes three states:

- `canonical`: the language-neutral specification or fixture lives here and is the shared source of truth.
- `inventory_only`: the contract remains owned by a component and is recorded here to make versions and consumers visible.
- `deferred`: the producer/consumer boundary is known, but extraction has not been approved yet.

`healthmd.semantic_input` v1 is an internal canonical contract, not a public health export schema. It keeps exact numeric/timestamp fidelity and platform-extension retention between native capture and deterministic Rust reduction. Its version and canonical-result model version are independent from every public export and direct protocol version.

`healthmd.render_input` v1 is a separate internal boundary from one completed semantic result to exact profile artifacts. Its fixtures include reviewed Rust plans plus independently frozen bytes from the pre-cutover Swift and Kotlin renderers. It does not grant Rust access to destinations, HTTP, HealthKit, Health Connect, ZIP containers, or credentials.

The current Apple daily export contract is version 8. Android's compatibility exporter remains frozen at version 4, while Android's additive local analytical profile is version 5. They are deliberately separate shipped inventory entries: moving them into one package without reconciling their semantics would hide real version and unit differences. Apple v8 adds the reviewed `providers.whoop` section and provider-prefixed Markdown, Bases/frontmatter, CSV, and data-dictionary projections. Android v4/v5 contracts remain unchanged.

`healthmd.shared_setup` v1 is a separate pre-canonical public configuration contract candidate, deferred pending physical-device interoperability and accessibility QA. It carries only explicitly allowlisted portable preferences, exact registry semantic metric IDs, typed native extensions, and disabled schedule/API intent. It never carries health data, credentials, folder grants, purchases, or runtime state and does not bump any health export schema or direct protocol.

A unified cross-platform successor is now specified as a **deferred `healthmd.health_data` v9 proposal**. It cannot use v8 because Apple v8 already identifies a different shipped grammar. The proposal does not enable writers or alter current output profiles; acceptance remains gated by RFC-0004, mapping review, dual-read consumers, privacy/security review, and release evidence.

## Cross-platform unification policy

[`docs/architecture/cross-platform-unification-policy.md`](../../docs/architecture/cross-platform-unification-policy.md) makes parity the default and divergence an evidence-backed exception. New mobile capabilities should start with a platform-neutral outcome and both-platform API review. Equivalent semantics use common IDs/contracts; OS-specific or non-equivalent data uses explicit capability states, distinct semantic IDs, or independently versioned platform sections. Similar labels and matching field counts are never sufficient evidence.

## Product capability inventory

`product-capabilities.json` records output profiles and product-level capabilities. Each capability is classified as `shared`, `apple_only`, `android_only`, `unavailable`, or `planned`. Platform entries use `available`, `unavailable`, or `planned`; every unavailable entry must carry a non-empty reason, and every planned entry must name its target. Platform-only data remains a supported product capability rather than a parity defect.

The contract manifest pins both inventories by SHA-256. Update a hash only after reviewing its semantic diff and evidence. `make test-product-parity` checks capability classifications, profile/contract references, registry identity/order/availability/output invariants, evidence paths, canonical bytes, and pinned hashes.

## Fixture policy

Canonical fixtures contain synthetic protocol values only; never add health records, user identifiers, credentials, tokens, or production payloads. A fixture change must include:

1. producer evidence from the implementation named in its provenance;
2. matching consumer tests in every affected language;
3. protocol-version analysis for wire, crypto, canonical JSON, enum, timestamp, UUID, or frame changes;
4. an intentional manifest hash update after reviewing the byte diff.

Do not regenerate a fixture merely to make a failing consumer pass.

The independently published Rust crates keep protocol, semantic, and render differential fixture mirrors inside their Cargo packages so release archives remain self-contained. `validate.py` requires those mirrors to be byte-identical to the canonical assets. Android's in-repository Gradle module consumes the canonical v2 fixture directly.
