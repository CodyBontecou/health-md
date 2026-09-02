# Direct application protocol v2

This document specifies the Android-capable Health.md direct application protocol. The CLI is the TCP listener and the foreground Android app connects outbound to it. The CLI is not embedded in the APK.

Protocol v2 is an application-layer extension. It deliberately reuses these deployed v1 transport properties from [the v1 contract](../v1/protocol.md):

- TCP port `17647` and `u64be(length) || JSON` outer packets;
- the deployed protocol-v1 packet framing and X25519/reconnect-secret handshake, with legacy Android pairing selector 2 or current shared selector 3 using a short-lived 20-digit high-entropy code and independently domain-separated authentication proofs;
- encrypted `HMDSC001` sequenced channel;
- `HMDDIRCT` binary transfer frame version 1;
- 2 MiB packet and 512 KiB chunk limits;
- seven-day durable job lifetime.

Keeping one audited transport avoids embedding Rust/JNI in Android and avoids a second cryptographic protocol. `v1` iOS application messages and durable jobs remain unchanged.

## Negotiation

Immediately after authentication, peers exchange the existing Swift-compatible `hello` message. A v2-capable CLI advertises application versions `[1,2]`. Existing iOS advertises `[1]`; Android MUST advertise `[2]`, platform `android`, an empty `supportedRawProfiles` list, durable jobs, and transfer protocol version 1.

The selected application version is the highest common version. The CLI requires:

| Source platform | Required application version |
|---|---:|
| `ios` | 1 |
| `android` | 2 |

Android MUST fail closed rather than downgrade to application v1. Once version 2 is selected, every non-binary control payload uses the envelope below. Android `PairingRequest.protocolVersion` 3 selects the current [shared pairing profile](../pairing-v3/protocol.md); selector 2 remains compatible with older clients and CLIs. The reused secure-channel and binary framing remain version 1, and application version 2 is negotiated independently.

## Encoding

A v2 control message is canonical UTF-8 JSON:

```json
{
  "protocol_version": 2,
  "type": "export_request",
  "payload": {}
}
```

Rules:

- names and enum values are `snake_case`;
- UUIDs are lowercase, hyphenated strings;
- timestamps are RFC 3339 UTC with whole-second precision and a `Z` suffix;
- absent optional members are omitted, never `null`;
- fingerprinted objects use recursively key-sorted compact JSON;
- floats and non-finite values are forbidden in protocol metadata;
- security-critical payloads reject unknown members;
- byte counts and offsets are non-negative integers.

The Rust models are implemented in [`packages/healthmd-core-rust/crates/healthmd-protocol/src/v2.rs`](../../../healthmd-core-rust/crates/healthmd-protocol/src/v2.rs). The shared [Rust/Kotlin interoperability fixture](fixtures/interop.json) pins cryptographic values, canonical request bytes and fingerprints, and envelope bytes. Both implementations test the deployed binary-frame layout separately.

## Source capabilities

After negotiation Android sends `source_hello`. It identifies the app installation and advertises only products the installed app and connected providers can currently produce.

Initial products are:

| Product ID | Artifact schema | Initial support |
|---|---|---|
| `android_provider_native_snapshot_v1` | `healthmd.raw-snapshot`, major 1 | Required |
| `generated_files_v1` | `healthmd.generated-files`, major 1 | Required |
| `android_daily_records_v1` | `healthmd.health_data`, major 4 | Later extraction phase |

A provider-native request MUST name one provider. `all_connected` is not a provider and is rejected until a multi-artifact bundle contract exists. A provider without a native raw adapter MUST return `unsupported_provider`; it MUST NOT silently fall back to Health Connect.

## Requests

An immutable `export_request` contains:

- job, creation, expiry, and selected source installation IDs;
- exact or all-available date selection;
- one explicitly tagged product request;
- an optional opaque destination binding for generated files.

The Android app never receives an absolute desktop destination path. The CLI stores the path and filesystem identity in its local durable job and sends only a SHA-256 binding plus privacy-safe basename. The binding is part of the request fingerprint.

`export_accepted` pins the peer binding, product, source calendar timezone/range, provider when applicable, settings snapshot hash when applicable, and request fingerprint before health bytes are produced.

### Generated-files settings policies

`generated_files_v1` carries a `settings_policy` naming where the request's output settings come from, advertised per capability in `source_hello.products[].settings_policies`:

- `requested_scope` — request-scoped selections (reserved; not currently advertised for this product).
- `saved_device_settings` — the device's saved export settings.
- `profile` — an export profile on the device, referenced by the sibling `profile_reference` object (`profile_id` authoritative; optional `name` is display/resolution convenience). The profile's frozen snapshot — including its frozen engine authority — becomes the run's settings basis. Unknown references are rejected with `invalid_request` (`profile_not_found`); they never fall back to saved settings.

The `profile` policy and `profile_reference` field are additive relative to older v2 peers, and v2 payloads use `deny_unknown_fields`: an older peer fails closed with a typed decode error rather than misinterpreting the request (the same fail-closed doctrine as the iOS v1 `settingsPolicy: "profile"` addition; see `fixtures/profile-policy-reference.json`).

## Artifacts

Every artifact has an immutable `artifact_manifest` containing its ID, kind, schema, media type, byte count, exact-byte SHA-256, and product-specific metadata.

### Android raw snapshot

The Android [`raw-snapshot-v1` contract](../../../../apps/android/docs/export-contract/raw-snapshot-v1.md) remains authoritative. The artifact is JSON or NDJSON with schema `healthmd.raw-snapshot`, major 1. The manifest also carries provider ID, logical checksum, and snapshot status.

The CLI MUST use a dedicated streaming Android snapshot validator. It MUST NOT pass this artifact through the iOS `RawReceiver` or relabel it as an iOS canonical result.

Raw snapshots are non-transactional. A resumed job reuses the exact preserved artifact. If it is missing, Android returns `spool_missing_restart_required`; it MUST NOT regenerate under the same job ID.

### Generated files

Each file is a separate artifact with a safe POSIX relative path and one write policy:

- `overwrite`
- `append`
- `merge_markdown`
- `merge_markdown_preserving_preamble`

Android generates new content without reading the desktop destination. The CLI applies write/merge behavior through its capability-based destination commit engine. Absolute paths, `..`, empty components, NUL, unsafe separators, destination collisions, and changed destination identity are rejected.

## Transfer

The transfer sequence is:

```text
Android -> export_accepted, progress*, transfer_session, artifact_manifest*
for each globally contiguous zero-based partition:
  Android -> transfer_open
  CLI     -> transfer_disposition(needed | already_committed | rejected)
  if needed:
    Android -> encrypted HMDDIRCT binary chunks
    CLI     -> transfer_chunk_acknowledgement
    Android -> transfer_partition_complete
    CLI     -> transfer_partition_acknowledgement
Android -> transfer_finalize
CLI     -> validate, assemble, and durably commit
CLI     -> transfer_final_acknowledgement
Android -> completion_confirmed
```

A partition binds job/session/request fingerprint, artifact ID, artifact offset, partition index, exact byte count/SHA-256, and previous partition SHA-256. Partitions are globally contiguous. Chunks begin at sequence 1 for each partition and use the deployed binary frame format.

A CLI job is complete only after `completion_confirmed`. Pending partition bytes may be discarded after disconnect; acknowledged CLI partitions survive until confirmation. Android retains the exact source artifact through the seven-day job expiry even after sending confirmation, so an ambiguous/lost final delivery can replay without rereading a non-transactional provider. Cancellation or forgetting trust purges it sooner.

## Runtime constraints

The Android connection is user-started from the foreground Direct CLI screen:

- the CLI listener must already be running;
- the app may scan the universal in-app QR or accept the same host, port, and 20-digit code manually; camera permission and hardware remain optional;
- Android uses a short-lived foreground `dataSync` service;
- one direct export may run at a time;
- no boot reconnect, WorkManager destination, schedule target, automation target, or mDNS discovery;
- source permissions are checked before request acceptance;
- provider-native snapshots are bound to the immutable range/scope/route policy and validated for record/provider hashes, counts/reports, status, logical/manifest checksums, and exact bytes;
- NDJSON validation streams with bounded lines; JSON validation is capped at 64 MiB and larger raw jobs must use NDJSON;
- trust credentials are encrypted with Android Keystore and stored under no-backup app storage;
- health values, tokens, paths, and exception strings never appear in logs, notifications, or wire errors.

## Errors

`export_rejected` carries a stable code, phase, retryability, fixed public message, optional job ID, and bounded string-list details. Supported codes are defined by `v2::ErrorCode` and include incompatible protocol, unsupported product/schema/provider, permission required, device locked, busy, quota exhausted, validation/transfer/destination failure, cancellation, and expiry.

A service cannot launch permission UI. `permission_required` identifies missing permissions; the visible Android UI routes the user to the existing permission flow.

## Compatibility

| Combination | Result |
|---|---|
| New CLI + existing iOS | Negotiates application v1; existing behavior |
| New CLI + Android | Negotiates application v2 |
| Old CLI + Android | Fails application negotiation before health reads |
| Android + v1-only peer | Fails closed; no downgrade |

The CLI must be released before Android direct export is enabled in production.

## Internal authority API (non-wire)

The transport-independent Rust authority in `healthmd-protocol::foundation`, exposed through the
thin shared-core UniFFI package at protocol API revision 1, can validate/fingerprint the exact v2
request model, canonicalize complete `Envelope` JSON, process opaque deployed `HMDDIRCT` frames,
reuse transfer negotiation, verify the reviewed selector-2 and selector-3 new-pairing client transcripts, and derive
the reused reviewed session key. This internal revision is not negotiated and does not alter
application version 2, legacy Android pairing selector 2, shared secure/binary framing version 1, any
envelope discriminator, timestamp/UUID rule, hash, limit, or fixture in this specification.

Stateful `HMDSC001` sequence/replay enforcement, seal/open and AEAD nonce/key lifecycle, trusted
reconnect/server transcripts, trust rotation, sockets, transport lifecycle, and persistence remain
outside UniFFI and gated on a separate security review.
