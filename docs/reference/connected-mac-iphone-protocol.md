# Connected Mac–iPhone protocol

Health.md uses a versioned connected-app protocol to request iPhone HealthKit work and deliver files or canonical results to Mac. The protocol is transport/lifecycle metadata; `healthmd.health_data` remains the single public health-data schema.

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
- canonical health-data selection and request-scoped context acquisition;
- request/settings fields supported by each peer.

A lossless file job is rejected when the peer cannot preserve the requested current archive. Strict raw never silently downgrades to the legacy internal `raw_data` path.

Summary-only and explicitly non-granular file jobs can use older negotiated paths when they do not claim a lossless archive. Daily Notes Only requires explicit support because an older Mac would otherwise ignore the additive setting and unexpectedly write aggregate files.

Generated capability example: [`generated/automation/peer-capabilities.json`](./generated/automation/peer-capabilities.json).

## Request lifecycle

### 1. Mac request

A request identifies the job, dates, response mode/raw transport profile, and request-scoped settings policy. `health_data_projection` additionally carries the exact metric/source/detail/object/field selection, which is fingerprinted and applied before iPhone HealthKit acquisition. Encrypted-context manifests likewise require the immutable canonical selection and matching source list; recovered jobs without that scope are rejected rather than falling back to saved settings. The same job ID follows every progress/result message.

Generated examples:

- [`generated/automation/iphone-export-request-write-files.json`](./generated/automation/iphone-export-request-write-files.json)
- [`generated/automation/iphone-export-request-strict-raw.json`](./generated/automation/iphone-export-request-strict-raw.json)

### 2. iPhone preparation

The iPhone validates:

- app/HealthKit readiness;
- date range;
- quota;
- requested capabilities and versions;
- saved/request-scoped settings;
- cancellation state.

It reports preparation progress without logging source health values.

Generated example: [`generated/automation/iphone-export-progress.json`](./generated/automation/iphone-export-progress.json).

### 3. Prepared result

Current peers open one stable corpus session for the request. iPhone fetches and encodes one HealthKit day at a time, adds its disk spool to the current partition, and releases the in-memory record. The immutable session manifest captures exact source dates and the settings snapshot needed for Mac-side path planning. Older peers retain the whole-`MacExportJob` fallback.

The iPhone output subfolder from the captured settings is applied beneath the Mac-selected root. A missing field from an older peer uses the documented Mac-local compatibility fallback.

### 4. Partitioned bounded transfer

Current peers negotiate a partition target in the 32–64 MiB range (48 MiB by default). Each partition includes:

- the stable parent session/job identity;
- a zero-based partition index and previous-partition digest;
- exact source-date membership;
- declared byte count and SHA-256 digest;
- independently spooled item segments, allowing one dense day to cross any number of bounded physical partitions without a total item cap;
- 512 KiB ordered transport frames with per-frame acknowledgements;
- negotiated binary frame v1, which carries payload bytes and the SHA-256 digest directly instead of JSON/base64;
- a bounded sliding window of up to four in-flight frames, while acknowledgements still occur only after receiver persistence;
- final digest and application acknowledgement.

A partition ACK is issued only after Mac validates the bytes, applies complete daily items, and atomically replaces its durable session journal. The iPhone persists the exact partition before sending and advances its item offset only after that ACK. If either app dies after the Mac commit but before the iPhone checkpoint, replaying the same index/digest returns `already_committed` without writing files again. If a daily item spans partitions, its original protected item bytes and next offset survive relaunch. A Mac-initiated iPhone journal also retries finalization autonomously when only the final ACK was lost, even if the Mac job is already terminal. The aggregate session uses 64-bit counters and has no 2 GiB protocol ceiling.

Durable protocol v2 sessions bind stable source and destination installation UUIDs into the session. Both peers must advertise durable recovery and protocol v2; a different reinstalled iPhone or Mac cannot inspect, resume, or cancel the stored job. Mixed-version peers negotiate protocol v1 and retain in-process-only retry behavior.

Binary framing is separately capability-negotiated. If either peer omits a shared binary frame version, transfer chunks keep the legacy JSON/base64, one-chunk-at-a-time behavior. Manual IP also retains that fallback. The frame window is the smaller advertised peer bound and is clamped to 1–8; current peers advertise four. The receiver can replay an acknowledgement for any already-persisted frame in the active transfer window, and duplicate completion messages remain pending while application persistence finishes rather than aborting valid work.

| Limit | Current corpus protocol |
|---|---:|
| Maximum data bytes per transport frame | 512 KiB |
| Current binary frame version | 1 |
| Current / maximum negotiated in-flight frames | 4 / 8 |
| Negotiated partition target | 32–64 MiB (48 MiB default) |
| Maximum physical partition | 64 MiB |
| Maximum logical day/item | No product cap; 64-bit length, segmented across bounded partitions |
| Aggregate session size | Not capped by the protocol; bounded by available storage/cancellation |

The legacy single-payload path remains capped at 2 GiB and 8,192 chunks for mixed-version peers. Transport framing adds overhead beyond payload bytes.

Generated message examples:

- [`generated/automation/transfer-offer.json`](./generated/automation/transfer-offer.json)
- [`generated/automation/transfer-chunk.json`](./generated/automation/transfer-chunk.json)
- [`generated/automation/transfer-acknowledgement.json`](./generated/automation/transfer-acknowledgement.json)
- [`generated/automation/transfer-complete.json`](./generated/automation/transfer-complete.json)
- [`generated/automation/transfer-rejection.json`](./generated/automation/transfer-rejection.json)

### 5. Mac application

For file mode, Mac:

1. validates the immutable session, partition chain, dates, counters, checksums, available storage, and a one-use admission for the exact next partition;
2. resolves the selected root and captured iPhone subfolder;
3. writes requested daily files atomically as complete items arrive;
4. records committed partitions and exact completed dates in a protected journal;
5. creates disk-backed aggregate-only roll-up projections from each dense source day, generates one period window at a time, and writes archives through a checkpointed streaming ZIP64 writer;
6. returns per-file/date results.

For strict raw or scoped extraction, Mac validates one daily item at a time, composes the `healthmd.raw_result` transport object on disk, and retains that checksummed control-response spool as a protected seven-day job artifact. `healthmd extract` then copies full nested v7 documents or returns exact pointer projections, while retaining per-day/missing/capture diagnostics in a separate protocol receipt. Loopback downloads do not consume it. The CLI uses a download spool and bounded stdout/file copies instead of `URLSession.data(for:)` or whole-response `JSONSerialization`.

Generated examples:

- [`generated/automation/mac-export-job.json`](./generated/automation/mac-export-job.json)
- [`generated/automation/mac-export-result-success.json`](./generated/automation/mac-export-result-success.json)
- [`generated/automation/mac-export-result-partial.json`](./generated/automation/mac-export-result-partial.json)

## Cancellation and timeout

- A transient peer disconnect or iPhone process termination suspends the job. The Mac retains its committed receiver frontier while iPhone retains only bounded uncommitted item/partition bytes; reconnect/hello resends the exact request and reopens the identical session/fingerprint for the same installation pair.
- A loopback client closure or waiter inactivity timeout only detaches that HTTP waiter. The durable request and resumable journal continue accepting progress and terminal results.
- Only explicit job cancellation propagates through request, transfer, and corpus-session state. If the bound iPhone is absent, the cancelled Mac record remains a tombstone and redelivers cleanup only to that installation on a later hello.
- A failed physical partition is retried with the same transfer ID and descriptor instead of restarting the corpus; at most the current ≤64 MiB partition is retransmitted.
- Cancellation preserves exact durably completed dates and deletes uncommitted item/archive spools.
- Late results after a waiter detaches are persisted and retrievable by job ID.
- Jobs use a fixed `createdAt + 7 days` expiry; expiry may clean resumable journals and terminal spool directories.
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

The generated message inventory lists every currently encoded message and observed field: [`generated/automation/message-fields.md`](./generated/automation/message-fields.md).

## Backward compatibility

Connected protocol compatibility is capability-driven:

- optional additive fields allow older peers to decode supported paths;
- current lossless features require explicit advertised versions;
- missing capability produces a structured rejection/unavailable result;
- strict raw never accepts a legacy shape as equivalent;
- summary-only jobs can remain available when their actual output does not require a canonical archive.

## Security and logging

Nearby sync uses encrypted Multipeer Connectivity. Manual IP/Tailscale uses paired encrypted Network.framework transport. The local control listener accepts only loopback peers.

Logs and progress must remain PHI-safe: job IDs, byte counts, dates/counts, statuses, and safe errors are allowed; source sample values, clinical content, routes, and raw payloads are not. Raw health data crosses the protocol only through an explicit file job, a legacy raw compatibility request without `raw_profile`, or a strict raw request. Strict clients must never accept the legacy shape as equivalent.

## Practical guidance

- Keep both apps current for lossless exports.
- Keep the iPhone app open and the protected HealthKit store available.
- Multi-year and corpus-scale ranges use partitioned transfer; available storage and one-day HealthKit density still matter.
- Treat a successful transport as separate from complete HealthKit capture; inspect the daily manifest.
- Treat a valid checksum as transport integrity, not proof of semantic completeness.
