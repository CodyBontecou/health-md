# Health.md direct protocol contracts

These specifications define the authenticated direct-device protocols used by the portable `healthmd` CLI.

| Contract | Mobile source | Desktop peer | Specification | Canonical vectors |
|---|---|---|---|---|
| Application v1 | iPhone / Swift | Rust CLI | [`v1/protocol.md`](v1/protocol.md) | [`v1/fixtures/swift-reference.json`](v1/fixtures/swift-reference.json) |
| Application v2 | Android / Kotlin | Rust CLI | [`v2/protocol.md`](v2/protocol.md) | [`v2/fixtures/interop.json`](v2/fixtures/interop.json) |

V2 extends the application layer for Android while deliberately reusing the deployed transport framing and binary transfer frame. It does not replace iPhone application v1. Peers negotiate the highest compatible application version and Android fails closed rather than downgrading to v1.

## Implementations

- Swift v1: [`apps/apple/Packages/HealthMdConnectivity/Sources/HealthMdConnectionCore`](../../../apps/apple/Packages/HealthMdConnectivity/Sources/HealthMdConnectionCore)
- Rust v1/v2: [`apps/cli/crates/healthmd-protocol`](../../../apps/cli/crates/healthmd-protocol)
- Kotlin v2: [`apps/android/direct-protocol`](../../../apps/android/direct-protocol)

The [contract manifest](../manifest.json) records exact authorities, consumers, provenance, fixture hashes, and required Cargo mirrors.

## Compatibility changes

Treat changes to cryptographic transcripts, canonical JSON, associated-value layout, envelope discriminators, date/UUID encoding, packet framing, binary frames, and fingerprint inputs as versioned protocol changes unless compatibility is proven across every deployed peer. Additive fields still require decoder analysis because security-critical payloads reject unknown members.

Before editing a specification or vector:

1. classify the change as documentation-only, compatible, capability-gated, or a new negotiated version;
2. update every producer and consumer together;
3. update canonical vectors from their named producer, then update any declared packaging mirrors;
4. run `python3 packages/contracts/validate.py`, Rust vector tests, Kotlin interoperability tests, and Swift connectivity tests;
5. complete physical-device QA for transport or lifecycle changes.
