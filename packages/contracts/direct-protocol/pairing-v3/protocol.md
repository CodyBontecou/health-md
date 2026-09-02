# Shared Direct CLI pairing profile v3

This document specifies pairing selector `3`, the shared iOS/Android 20-digit onboarding profile, and its universal QR handoff. It is normative together with [`fixtures/shared-pairing-v3.json`](fixtures/shared-pairing-v3.json).

This is a pairing-profile addition, not a wire-framing or application-protocol revision. The deployed outer packet schema, secure channel, transfer framing, iOS application v1, and Android application v2 remain unchanged.

## Compatibility

Pairing selectors are preserved as independent compatibility profiles:

| Selector | Code | Client/profile | Status |
|---:|---:|---|---|
| `1` | 6 ASCII digits | legacy Apple | unchanged |
| `2` | 20 ASCII digits | legacy Android | unchanged |
| `3` | 20 ASCII digits | shared iOS/Android | current onboarding |

A current CLI listener accepts all three selectors. It generates one shared 20-digit secret for selectors `2` and `3` and a separate six-digit secret for selector `1`. Existing selectors and their transcript bytes MUST NOT change.

Current iOS and Android clients use selector `3` for new code/QR pairing. Trusted reconnect continues to use each platform's deployed selector (`1` on iOS and `2` on Android), because reconnect authentication is based on the stored 32-byte secret and the unchanged trusted-client/server domains. Android MAY retry selector `2` after a selector-3 connection fails in order to pair with an older CLI; this does not reduce code entropy.

After pairing, normal hello negotiation determines the source platform and application protocol. Selector `3` does not imply iOS or Android.

## Code and cryptographic transcripts

The pairing code is exactly 20 ASCII decimal digits. A generator MUST obtain every code from a cryptographically secure random source without modulo bias. The code carries approximately 66.4 bits of entropy and is never sent on the wire.

Define `F(value) = u64be(byte_count) || value` and `L(uuid)` as lowercase ASCII UUID text.

```text
code_key = SHA256("HealthMd.DirectCLI.Code.v3." || twenty_ascii_digits)

pairing_client_proof = HMAC-SHA256(
  code_key,
  "HealthMd.DirectCLI.PairingVerifier.v3"
  || F(L(client_id)) || F(client_public_key) || F(client_nonce)
)
```

For a new pairing, the server proof is:

```text
HMAC-SHA256(
  code_key,
  "HealthMd.DirectCLI.PairingServer.v3"
  || F(L(client_id)) || F(client_public_key) || F(client_nonce)
  || F(L(server_id)) || F(server_public_key) || F(server_nonce)
  || 0x01 || F(sealed.nonce) || F(sealed.ciphertext) || F(sealed.tag)
)
```

X25519, session-key derivation, reconnect-secret sealing, trusted reconnect proofs, packet limits, and secure-channel sequencing are exactly those in [direct protocol v1](../v1/protocol.md).

The selector-3 domains are intentionally distinct from selectors `1` and `2`. Implementations MUST NOT select a transcript only from code length: the explicit `PairingRequest.protocolVersion` selects the cryptographic profile.

## Universal QR handoff

The CLI renders this canonical payload, substituting the selected address, listener port, and shared code:

```text
healthmd://direct-cli/pair?host=192.168.1.42&port=17647&code=12345678901234567890
```

The QR is an in-app handoff, not an externally authorized deep link. Mobile apps MUST NOT register a browsable `healthmd://direct-cli` intent/URL handler. Scanning the QR inside the foreground Direct CLI screen is explicit pairing consent and may start pairing immediately.

A scanner parser MUST fail closed unless all of these hold:

- the payload is at most 512 ASCII bytes and contains no whitespace, control characters, percent encoding, fragment, or credentials;
- scheme, authority, and path are exactly `healthmd`, `direct-cli`, and `/pair`;
- the query contains exactly one each of `host`, `port`, and `code`, with no duplicate or unknown fields;
- `host` is canonical dotted-decimal IPv4 in RFC 1918 space (`10/8`, `172.16/12`, `192.168/16`) or Tailscale CGNAT space (`100.64/10`), with no leading-zero octets;
- `port` is decimal in `1...65535`;
- `code` is exactly 20 ASCII digits.

Manual host, port, and code entry remains available when camera hardware or permission is unavailable. A scanned host is only a connection destination; successful transcript authentication remains mandatory.

## Fixture obligations

The canonical fixture pins:

- selector and pairing code;
- client/server UUIDs, public keys, nonces, and the derived code key;
- the separated reconnect-secret frame;
- selector-3 client and server HMAC values;
- one canonical QR payload.

Rust, Swift, and Kotlin tests MUST consume or byte-match this fixture. Changes to any fixture value require an explicit new pairing profile rather than silently changing selector `3`.
