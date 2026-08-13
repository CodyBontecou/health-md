---
title: "Connected Mac–iPhone protocol"
description: "Health.md uses a versioned connected-app protocol to request iPhone HealthKit work and deliver files or canonical results through the Mac app. The protocol is…"
editUrl: false
---

Health.md uses a versioned connected-app protocol to request iPhone HealthKit work and deliver files or canonical results through the Mac app. The protocol is transport/lifecycle metadata; `healthmd.health_data` remains the single public health-data schema.

This page describes the default `mac-app` backend. The explicit [direct iPhone CLI backend](/docs/cli-direct/) reuses shared pairing/framing foundations and the same public exporters/schema, but has a separate trust domain, `DirectMessage` envelope, protected iPhone spool, CLI receiver journal, and explicit Manual IP/Nearby selection. The two backends never silently fall back to one another.

```text
Mac CLI
  → localhost control API
Mac app
  → iPhone export request
Open connected iPhone
  → HealthKit capture and export preparation
  → stable corpus session / bounded checksum partitions / completion
Mac app
  → acknowledgement, file writes or strict result
  → final local control response
```

HealthKit reads always occur on iPhone. Mac owns its selected destination and file writes.

## Capability negotiation

Peers advertise capabilities before a current request is accepted. Negotiated features include:

- iPhone-export request support;
- current file-job versions;
- size-bounded connected transfers;
- partitioned corpus sessions and negotiated 32–64 MiB targets;
- binary connected-transfer frame versions and bounded in-flight windows;
- strict raw streaming and spooled control responses;
- accepted canonical archive versions;
- accepted raw-result versions;
- Daily Notes Only support;
- explicit data-dictionary suppression while preserving aggregate files;
- authoritative generated-file accounting, including exact category breakdowns and an explicit lower-bound state after interrupted writes;
- canonical health-data selection and request-scoped context acquisition;
- request/settings fields supported by each peer.

A lossless file job is rejected when the peer cannot preserve the requested current archive. Strict raw never silently downgrades to the legacy internal `raw_data` path.

Summary-only and explicitly non-granular file jobs can use older negotiated paths when they do not claim a lossless archive. Daily Notes Only requires explicit support because an older Mac would otherwise ignore the additive setting and unexpectedly write aggregate files. Data-dictionary suppression likewise requires explicit destination support because an older Mac would otherwise recreate the JSON sidecar.

Generated capability example: [`generated/automation/peer-capabilities.json`](/docs/reference/generated/automation/peer-capabilities.json).

## Request lifecycle

### 1. Mac request

A request identifies the job, dates, response mode/raw transport profile, and request-scoped settings policy. `health_data_projection` additionally carries the exact metric/source/detail/object/field selection, which is fingerprinted and applied before iPhone HealthKit acquisition. Encrypted-context manifests likewise require the immutable canonical selection and matching source list; recovered jobs without that scope are rejected rather than falling back to saved settings. The same job ID follows every progress/result message.

Generated examples:

- [`generated/automation/iphone-export-request-write-files.json`](/docs/reference/generated/automation/iphone-export-request-write-files.json)
- [`generated/automation/iphone-export-request-strict-raw.json`](/docs/reference/generated/automation/iphone-export-request-strict-raw.json)

### 2. iPhone preparation

The iPhone validates:

- app/HealthKit readiness;
- date range;
- quota;
- requested capabilities and versions;
- saved/request-scoped settings;
- cancellation state.

It reports preparation progress without logging source health values.

Generated example: [`generated/automation/iphone-export-progress.json`](/docs/reference/generated/automation/iphone-export-progress.json).

### 3. Prepared result

Current peers open one stable corpus session for the request. iPhone fetches and encodes one HealthKit day at a time, adds its disk spool to the current partition, and releases the in-memory record. The immutable session manifest captures exact source dates and the settings snapshot needed for Mac-side path planning. Older peers retain the whole-`MacExportJob` fallback.

The iPhone output subfolder from the captured settings is applied beneath the Mac-selected root. A missing field from an older peer uses the documented Mac-local compatibility fallback.

### 4. Partitioned bounded transfer

Current peers negotiate a partition target in the 32–64 MiB range (48 MiB by default). Each partition includes:

- the stable parent session/job identity;
- a zero-based partition index and previous-partition digest;
- exact source-date membership;
- declared byte count and SHA-256 digest;
- independently spooled item segments, allowing one dense day to cross any number of bounded physical partitions without a total item cap; senders flush after 32 pending small items even below the negotiated byte target so durable journals and recovery batches remain responsive;
- 512 KiB ordered transport frames with per-frame acknowledgements;
- negotiated binary frame v1, which carries payload bytes and the SHA-256 digest directly instead of JSON/base64;
- a bounded sliding window of up to four in-flight frames, while acknowledgements still occur only after receiver persistence;
- final digest and application acknowledgement.

A partition ACK is issued only after Mac validates the bytes, applies complete daily items, synchronizes the protected source file and every affected item/record/raw directory entry, binds each completed file (or partial prefix) to its exact byte count and SHA-256, and atomically replaces its durable session journal. The journal also binds the app-private session directory's device/inode; current reads, writes, partition application, finalization setup, and recursive cleanup reopen that identity instead of following a substituted session path. Source spool creation, inspection, move, and removal use descriptor-relative no-follow traversal and reject linked files or substituted item/record/raw directories. A strict-raw spool left by an interrupted partition checkpoint is adopted only when its protected bytes are exact. The iPhone persists the exact partition before sending and advances its item offset only after that ACK. If either app dies after the Mac commit but before the iPhone checkpoint, replaying the same index/digest returns `already_committed` without writing files again. If a daily item spans partitions, its original protected item bytes, prefix digest, and next offset survive relaunch. A Mac-initiated iPhone journal also retries finalization autonomously when only the final ACK was lost, even if the Mac job is already terminal. The aggregate session uses 64-bit counters and has no 2 GiB protocol ceiling.

Durable protocol v2 sessions bind stable source and destination installation UUIDs into the session. Both peers must advertise durable recovery and protocol v2; a different reinstalled iPhone or Mac cannot inspect, resume, or cancel the stored job. Protocol v3 keeps the same partition bytes and additionally attests that the Mac can defer compatible pinned roll-up jobs and commit one received range plan at finalization. Before the first destination mutation, the Mac now writes the exact selected artifact bytes and, when enabled, data-dictionary bytes to a protected, no-backup finalization spool and atomically journals their digests, selected-root binding, immutable engine pin/plan identity, and ordered acknowledgement frontier.

Protocol v4 keeps the same bounded partition framing and public export contracts, but replaces the private per-day application-item JSON wrapper with deterministic `HMDCITEM` v1 typed tokens. Object keys remain sorted and v1-v3 application-item bytes remain byte-for-byte unchanged. For strict raw, iPhone writes the canonical daily JSON document once to a protected spool and copies those UTF-8 bytes directly into the token stream; Mac selectively decodes the small metadata while extracting the canonical document to a checksummed protected sidecar. Neither peer creates a second whole-item `Data`/JSON object during encode, receive, restart, or finalization. New/older peers negotiate the newest shared revision, with v1-v3 retaining their original application encoding and behavior.

### `HMDCITEM` v1 byte format

The private application item is deterministic and self-delimiting:

- header: eight ASCII bytes `HMDCITEM`, unsigned big-endian format version `1` (`u16`), item kind (`1` = `mac_health_day`, `2` = `strict_raw_day`), then one zero reserved byte;
- every node: one tag byte followed by an unsigned big-endian payload length (`u64`) and exactly that many payload bytes;
- tags: `1` object, `2` array, `3` null, `4` Boolean, `5` signed integer, `6` unsigned integer, `7` double, `8` UTF-8 string, `9` raw data, and `10` date;
- object payload: entry count (`u32`), then entries sorted by UTF-8 key bytes. Each entry is key length (`u32`), key bytes, child-node length (`u64`), and the exact child node;
- array payload: element count (`u64`), followed by child-node length (`u64`) and exact child node for each element;
- Boolean payload is one byte. Integer payloads are eight-byte big-endian bit patterns. Double payloads are IEEE-754 binary64. Date payloads are a finite binary64 count of seconds since Apple's 2001-01-01 reference date. Strings are canonical UTF-8 and data is unmodified bytes.

Decoders reject trailing bytes, unknown tags/kinds, nonzero reserved bytes, duplicate or unsorted object keys, invalid UTF-8/numbers, nesting over 128 levels, objects over 16,384 keys, keys over 4,096 bytes, and array counts impossible for the declared payload. Large data tokens are mapped from the validated item file instead of copied into an item-sized allocation; required native strings are UTF-8-validated and assembled in bounded chunks without a second payload-sized `Data`. Immutable fixtures in `ConnectedCorpusPartitionFileTests` pin the compatibility bytes:

| Application item fixture | Bytes | SHA-256 |
|---|---:|---|
| v1-v3 sorted-JSON strict missing day | 334 | `6bc3bec26eca6e246d93539ad6235a884926a7124ca1c2517055ffa44f39a80f` |
| v4 `mac_health_day` empty result | 150 | `03c954a05d5b0f9eee8bb2f6a785f111969e2958fd52d12e414da2cc278f8a99` |
| v4 `strict_raw_day` missing day | 721 | `fd4be6ebd2204e5efdcaa8d9c1e4e811e9958d831376c2588a4919f550422559` |

Binary framing is separately capability-negotiated. If either peer omits a shared binary frame version, transfer chunks keep the legacy JSON/base64, one-chunk-at-a-time behavior. Manual IP also retains that fallback. The frame window is the smaller advertised peer bound and is clamped to 1–8; current peers advertise four. The receiver can replay an acknowledgement for any already-persisted frame in the active transfer window, and duplicate completion messages remain pending while application persistence finishes rather than aborting valid work.

| Limit | Current corpus protocol |
|---|---:|
| Current corpus protocol version | 4 |
| Current application-item encoding | `HMDCITEM` token stream v1 |
| Maximum data bytes per transport frame | 512 KiB |
| Current binary frame version | 1 |
| Current / maximum negotiated in-flight frames | 4 / 8 |
| Negotiated partition target | 32–64 MiB (48 MiB default) |
| Preferred small-item flush | 32 pending items |
| Maximum physical partition | 64 MiB |
| Maximum logical day/item | No transport cap; 64-bit length, segmented across bounded partitions |
| Aggregate session size | Not capped by the protocol; bounded by available storage/cancellation |
| Admitted shared-core range owner dates | 400 |
| Shared-core semantic records / canonical record bytes | 100,000 / 64 KiB each / 32 MiB total |
| Shared-core semantic batch | 4,096 records / 1 MiB |

The legacy single-payload path remains capped at 2 GiB and 8,192 chunks for mixed-version peers. Transport framing adds overhead beyond payload bytes.

Generated message examples:

- [`generated/automation/transfer-offer.json`](/docs/reference/generated/automation/transfer-offer.json)
- [`generated/automation/transfer-chunk.json`](/docs/reference/generated/automation/transfer-chunk.json)
- [`generated/automation/transfer-acknowledgement.json`](/docs/reference/generated/automation/transfer-acknowledgement.json)
- [`generated/automation/transfer-complete.json`](/docs/reference/generated/automation/transfer-complete.json)
- [`generated/automation/transfer-rejection.json`](/docs/reference/generated/automation/transfer-rejection.json)

### 5. Mac application

For file mode, Mac:

1. validates the immutable session, partition chain, dates, counters, checksums, available storage, and a one-use admission for the exact next partition;
2. resolves the selected root and captured iPhone subfolder;
3. writes ordinary requested daily files atomically as complete items arrive and records committed partitions/exact completed dates before ACK;
4. for a compatible protocol-v3 received range, rejects more than 400 semantic owner dates, descriptor-validates every acknowledged source spool, incrementally enforces the 100,000-record, 64 KiB-record, 32 MiB-record-total, 4,096-record-batch, and 1 MiB-batch contracts, materializes one selected plan, protects every exact UTF-8 byte sequence with `0600` permissions, and persists the whole-plan digest before opening the destination commit frontier. Transport wrappers retain their existing segmented 64-bit protocol shape and are not mistaken for canonical semantic record bytes;
5. binds the selected root by canonical real path plus filesystem device/inode, then commits the optional dictionary and explicitly classified daily/roll-up artifacts in authoritative order through descriptor-relative `O_NOFOLLOW` traversal and same-directory atomic replacement. The final replacement uses the verified parent's canonical descriptor path with `RENAME_NOFOLLOW_ANY`, so a rename after the final precommit check cannot redirect the source temporary file; it reopens and compares the live root/parent namespace around replacement, and every exact file and containing directory chain is synchronized before its one-file journal checkpoint advances. An exact unacknowledged file is reinspected inside the non-cancellable commit transaction, read back again before its frontier checkpoint, and adopted only after that durability check, while an acknowledged missing/changed file, corrupt, symlinked, or hard-linked spool, unsafe/colliding path, same-path root replacement, concurrent namespace rebinding, or changed selected root fails closed;
6. creates disk-backed aggregate-only roll-up projections for legacy/archive work, generates one period window at a time, and writes archives through a checkpointed streaming ZIP64 writer;
7. reports generated-file categories separately from data-day completion and API payload records. `isTotalFilesWrittenAuthoritative: true` means the total is exact; `false` means it is only the confirmed lower bound. Missing authority metadata is never interpreted as exact. Ordinary partial per-date results retain exact completed dates, while `hadTerminalRangeFailure` identifies failures whose range-level derived output cannot be assigned to one day;
8. persists the terminal result and final acknowledgement before deleting payload/finalization spools, so a newly launched Mac can replay the same acknowledgement without rendering or rewriting. A failed terminal journal replacement restores the pre-terminal in-memory state and remains resumable rather than exposing completion. Strict-raw completion additionally streams an exact protected terminal-result copy, binds its byte count/hash and response metadata in the journal, and retains that copy through the fixed session recovery window. Process restart or a lost final acknowledgement therefore replays bytes so a missing, replaced, or corrupt control-response spool can be revalidated or repaired before another acknowledgement. The separate control-response store synchronizes exact spool bytes and its terminal record; its fixed expiry extends to the later connected-corpus session recovery deadline. Transient installation failures receive no final protocol acknowledgement and remain retryable.

For strict raw or scoped extraction, Mac validates one daily item at a time, composes the `healthmd.raw_result` transport object on disk, and retains that checksummed control-response spool as a protected seven-day job artifact. `healthmd extract` then copies full nested v8 documents or returns exact pointer projections, while retaining per-day/missing/capture diagnostics in a separate protocol receipt. Loopback downloads do not consume it. The CLI uses a download spool and bounded stdout/file copies instead of `URLSession.data(for:)` or whole-response `JSONSerialization`.

Generated examples:

- [`generated/automation/mac-export-job.json`](/docs/reference/generated/automation/mac-export-job.json)
- [`generated/automation/mac-export-result-success.json`](/docs/reference/generated/automation/mac-export-result-success.json)
- [`generated/automation/mac-export-result-partial.json`](/docs/reference/generated/automation/mac-export-result-partial.json)

## Cancellation and timeout

- A transient peer disconnect or iPhone process termination suspends the job. The Mac retains its committed receiver frontier while iPhone retains only bounded uncommitted item/partition bytes; reconnect/hello resends the exact request and reopens the identical session/fingerprint for the same installation pair.
- A loopback client closure or waiter inactivity timeout only detaches that HTTP waiter. The durable request and resumable journal continue accepting progress and terminal results.
- Only explicit job cancellation propagates through request, transfer, and corpus-session state. If the bound iPhone is absent, the cancelled Mac record remains a tombstone and redelivers cleanup only to that installation on a later hello.
- A failed physical partition is retried with the same transfer ID and descriptor instead of restarting the corpus; at most the current ≤64 MiB partition is retransmitted.
- Cancellation preserves exact durably completed dates and deletes uncommitted item/archive/finalization spools only after the cancelled state is durably recorded. A cancellation request that arrives inside one exact destination write/readback/frontier-checkpoint transaction is not acknowledged until the caller retries at the next artifact boundary.
- Late results after a waiter detaches are persisted and retrievable by job ID.
- Jobs use a fixed `createdAt + 7 days` expiry; only positively validated expired sessions are automatically removed. Corrupt durable state is retained to fail closed instead of making the same session look new.
- Cancellation is represented explicitly and must not be relabeled as successful empty capture.

## Transfer rejection

The receiver rejects malformed transfers for conditions such as:

- unsupported payload kind/version;
- declared size or chunk count above limits;
- inconsistent chunk indexes/counts;
- bytes beyond the declared size;
- duplicate chunks with mismatched content;
- final size/digest mismatch;
- decode failure;
- wrong job/transfer identity;
- application failure.

The generated message inventory lists every currently encoded message and observed field: [`generated/automation/message-fields.md`](/docs/reference/generated/automation/message-fields/).

## Backward compatibility

Connected protocol compatibility is capability-driven:

- optional additive fields allow older peers to decode supported paths;
- current lossless features require explicit advertised versions;
- missing capability produces a structured rejection/unavailable result;
- peers that do not advertise authoritative Mac-export file-accounting semantics do not start new Connected Mac jobs; this prevents an older consumer from presenting a lower bound as exact;
- a legacy result already in flight decodes missing authority metadata as a lower bound, never as an exact total;
- strict raw never accepts a legacy shape as equivalent;
- summary-only jobs can remain available when their actual output does not require a canonical archive.

## Security and logging

Mac-app nearby sync uses encrypted Multipeer Connectivity. Mac-app Manual IP/Tailscale uses its paired encrypted Network.framework transport. The local control listener accepts only loopback peers.

Direct CLI trust is separate from Mac-app sync trust. It uses an opt-in iPhone service that requires the foreground for pairing and new commands; an already-connected export may request finite iOS background execution time, with expiration producing a durable pause. Sessions use mutual authenticated Curve25519-derived keys, installation binding, and ChaCha20-Poly1305 for every direct application message/frame. Direct Nearby requires Multipeer encryption and retains that application layer. Direct Manual IP defaults to port `17647`; transport selection is explicit.

Logs and progress must remain PHI-safe: job IDs, byte counts, dates/counts, statuses, and safe errors are allowed; source sample values, clinical content, routes, and raw payloads are not. Raw health data crosses the protocol only through an explicit file job, a legacy raw compatibility request without `raw_profile`, or a strict raw request. Strict clients must never accept the legacy shape as equivalent.

## Practical guidance

- Keep both apps current for lossless exports.
- Keep the iPhone app open to pair or begin work and keep the protected HealthKit store available. An active direct export can survive brief backgrounding but may still pause when iOS expires its background time.
- Multi-year and corpus-scale ranges use partitioned transfer; available storage and one-day HealthKit density still matter.
- Treat a successful transport as separate from complete HealthKit capture; inspect the daily manifest.
- Treat a valid checksum as transport integrity, not proof of semantic completeness.
