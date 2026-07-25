# Direct protocol specification

This directory is the language-neutral interoperability contract between Health.md mobile sources
and the portable CLI.

[Version 1](v1.md) documents the deployed Swift/iOS application protocol exactly. [Version 2](v2.md)
is the platform-neutral Android application protocol. It reuses the audited v1 pairing, encrypted
transport, and binary frame while replacing application messages with explicit tagged envelopes.
A client must not advertise a version until the normative fixtures for that version pass in every
participating language.

Normative areas:

1. TCP packet length framing and allocation limits.
2. Pairing-code and trusted-reconnect handshakes.
3. Curve25519/HMAC transcript field encoding and session-key derivation.
4. ChaCha20-Poly1305 frame representation and monotonic secure-envelope sequencing.
5. Direct command and response JSON envelopes.
6. Immutable request fingerprint canonicalization.
7. Partition negotiation, frame hashes, digest chains, checkpoints, and acknowledgements.
8. Terminal completion confirmation and durable cancellation.

Health data values must never appear in protocol diagnostics or test fixtures.
