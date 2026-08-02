# healthmd-protocol

Wire models, canonical encoding, cryptography, request fingerprints, and bounded transfer frames for
the Health.md direct mobile-source protocols.

This crate is an interoperability component of the standalone
[Health.md CLI](https://github.com/CodyBontecou/health-md/tree/main/apps/cli). It does not read HealthKit, perform
networking, or log health data. Application protocol v1 mirrors the deployed Swift implementation;
application protocol v2 supports Android with shared Rust/Kotlin interoperability fixtures; query
protocol v3 mirrors the Swift iPhone capability used by the portable MCP server.

## Transport-independent foundation

`foundation` is the pure internal authority used by the shared UniFFI package. Protocol API revision
1 exposes deployed v1/v2 transport constants, strict canonical request fingerprints, complete
Apple-v1/v3 `DirectMessage` and Android-v2 `Envelope` canonicalization, `HMDDIRCT` transfer-frame
encoding/decoding, and the existing transfer-capability negotiation. Inputs are bounded before
model decoding, unknown fields and noncanonical fingerprint bytes fail closed, chunk bodies remain
opaque, and every failure maps to a fixed health-free code/message at the native wrapper.

The optional crypto surface is deliberately narrow and JSON-free: it verifies reviewed new-pairing
client transcripts and derives the reviewed v1 session key from fixed 32-byte inputs. Selected
Rust-owned vectors use `zeroize`; generated UniFFI transport buffers are outside that guarantee,
and callers own and must wipe returned key bytes. This remains a conformance API rather than
production key custody until secret-FFI review. It does not own trust, pairing lifecycle,
credentials, random key generation, or persistence.

Protocol API revision 1 is an internal API revision, not a wire version. The supported pairing
selectors remain Apple 1 and Android 2, Apple exports remain 1, Android application remains 2,
Apple query capability uses 3, and shared secure/binary framing remains 1. The canonical contract fixtures and crate mirrors are
byte-identical and unchanged.

## Security-review gate

Stateful `HMDSC001` channel authority is not exported through UniFFI. Sequence allocation and
replay/out-of-order rejection, AEAD nonce/key lifecycle, seal/open, reconnect-secret and trusted
transcripts, trust rotation, transport binding, and session persistence remain native/CLI authority
until a dedicated cross-language security and zeroization review approves migration.

Licensed AGPL-3.0-only.
