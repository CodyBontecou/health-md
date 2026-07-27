# Health.md contracts

This package contains language-neutral specifications, interoperability vectors, and a machine-readable inventory for public contracts shared across Health.md products. It does not replace Swift, Kotlin, Rust, or JavaScript build systems.

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

The current Apple daily export contract is version 7. Android's compatibility exporter remains frozen at version 4, while Android's additive local analytical profile is version 5. They are deliberately separate inventory entries: moving them into one package without reconciling their semantics would hide real version and unit differences. This extraction does **not** change `healthmd.health_data`, any exporter, metric mapping, unit, frontmatter key, CSV row, or schema version.

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
