# Health.md contracts

This package contains language-neutral specifications, interoperability vectors, and a machine-readable inventory for public contracts shared across Health.md products. It does not replace Swift, Kotlin, Rust, or JavaScript build systems.

## Contents

| Path | Purpose |
|---|---|
| [`manifest.json`](manifest.json) | Contract versions, ownership, consumers, fixture provenance, and integrity hashes |
| [`validate.py`](validate.py) | Standard-library validation for the inventory, fixture hashes, mirrors, and wire-vector invariants |
| [`direct-protocol`](direct-protocol) | Normative direct-device protocol specifications and canonical interoperability vectors |

Run the package checks from the repository root:

```bash
python3 packages/contracts/validate.py
# or
make test-contracts
```

## Ownership states

The manifest distinguishes three states:

- `canonical`: the language-neutral specification or fixture lives here and is the shared source of truth.
- `inventory_only`: the contract remains owned by a component and is recorded here to make versions and consumers visible.
- `deferred`: the producer/consumer boundary is known, but extraction has not been approved yet.

The current Apple daily export contract is version 7. Android's compatibility exporter remains version 4. They are deliberately separate inventory entries: moving them into one package without reconciling their semantics would hide real version and unit differences. This extraction does **not** change `healthmd.health_data`, any exporter, metric mapping, unit, frontmatter key, CSV row, or schema version.

## Fixture policy

Canonical fixtures contain synthetic protocol values only; never add health records, user identifiers, credentials, tokens, or production payloads. A fixture change must include:

1. producer evidence from the implementation named in its provenance;
2. matching consumer tests in every affected language;
3. protocol-version analysis for wire, crypto, canonical JSON, enum, timestamp, UUID, or frame changes;
4. an intentional manifest hash update after reviewing the byte diff.

Do not regenerate a fixture merely to make a failing consumer pass.

The independently published Rust crate keeps fixture mirrors inside its Cargo package so release archives remain self-contained. `validate.py` requires those mirrors to be byte-identical to the canonical assets. Android's in-repository Gradle module consumes the canonical v2 fixture directly.
