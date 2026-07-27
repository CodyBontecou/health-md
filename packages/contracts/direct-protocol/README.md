# Health.md direct protocol contracts

These specifications define the authenticated direct-device protocols used by the portable `healthmd` CLI.

| Contract | Mobile source | Desktop peer | Specification | Canonical vectors |
|---|---|---|---|---|
| Application v1 | iPhone / Swift | Rust CLI | [`v1/protocol.md`](v1/protocol.md) | [`v1/fixtures/swift-reference.json`](v1/fixtures/swift-reference.json) |
| Application v2 | Android / Kotlin | Rust CLI | [`v2/protocol.md`](v2/protocol.md) | [`v2/fixtures/interop.json`](v2/fixtures/interop.json) |

V2 extends the application layer for Android while deliberately reusing the deployed transport framing and binary transfer frame. It does not replace iPhone application v1. Peers negotiate the highest compatible application version and Android fails closed rather than downgrading to v1.

## Implementations

- Swift v1: [`apps/apple/Packages/HealthMdConnectivity/Sources/HealthMdConnectionCore`](../../../apps/apple/Packages/HealthMdConnectivity/Sources/HealthMdConnectionCore)
- Rust v1/v2: [`packages/healthmd-core-rust/crates/healthmd-protocol`](../../healthmd-core-rust/crates/healthmd-protocol)
- Kotlin v2: [`apps/android/direct-protocol`](../../../apps/android/direct-protocol)

The [contract manifest](../manifest.json) records exact authorities, consumers, provenance, fixture hashes, and required Cargo mirrors.

## Internal shared-core authority API

The pure Rust `healthmd-protocol::foundation` module and thin `healthmd-core-uniffi` bridge expose
protocol API revision 1 to packaged Swift/Kotlin core wrappers. This internal API validates the
existing models and bytes: strict request fingerprints, complete control-message canonicalization,
`HMDDIRCT` frames, transfer negotiation/constants, reviewed new-pairing client proof verification,
and reviewed session-key derivation. It performs no networking, lifecycle, trust-store, socket,
exporter, health-payload parsing, or persistence work.

The protocol API revision is not negotiated on the wire and does not bump either direct contract.
Apple/Android pairing selectors stay at 1/2, Apple application stays at version 1, Android
application stays at version 2, shared secure/binary framing stays at version 1, and both canonical
fixtures and Cargo mirrors remain unchanged. The Apple and Android production adapters provide
operation-wide `legacy`, native-authoritative `shadow`, and no-fallback `rust` selection with durable
protocol pins; release defaults remain legacy. See the
[M7 direct-protocol baseline](../../../docs/architecture/shared-core-m7-protocol-baseline.md).

Stateful secure-channel sequencing/replay enforcement, seal/open and nonce/key lifecycle, trusted
reconnect transcripts, trust rotation, and session persistence are explicitly gated on a separate
security review.

## Compatibility changes

Treat changes to cryptographic transcripts, canonical JSON, associated-value layout, envelope discriminators, date/UUID encoding, packet framing, binary frames, and fingerprint inputs as versioned protocol changes unless compatibility is proven across every deployed peer. Additive fields still require decoder analysis because security-critical payloads reject unknown members.

Before editing a specification or vector:

1. classify the change as documentation-only, compatible, capability-gated, or a new negotiated version;
2. update every producer and consumer together;
3. update canonical vectors from their named producer, then update any declared packaging mirrors;
4. run `python3 packages/contracts/validate.py`, Rust vector tests, Kotlin interoperability tests, and Swift connectivity tests;
5. complete physical-device QA for transport or lifecycle changes.
