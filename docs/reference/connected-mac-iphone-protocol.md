# Connected Mac–iPhone protocol

Health.md uses a versioned connected-app protocol to request iPhone HealthKit work and deliver files or strict raw results to Mac. This protocol is independent of the public daily file schema.

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
- strict raw streaming and spooled control responses;
- accepted canonical archive versions;
- accepted raw-result versions;
- Daily Notes Only support;
- request/settings fields supported by each peer.

A lossless file job is rejected when the peer cannot preserve the requested current archive. Strict raw never silently downgrades to the legacy internal `raw_data` path.

Summary-only and explicitly non-granular file jobs can use older negotiated paths when they do not claim a lossless archive. Daily Notes Only requires explicit support because an older Mac would otherwise ignore the additive setting and unexpectedly write aggregate files.

Generated capability example: [`generated/automation/peer-capabilities.json`](./generated/automation/peer-capabilities.json).

## Request lifecycle

### 1. Mac request

A request identifies the job, dates, response mode/profile, and request-scoped settings policy. The same job ID follows every progress/result message.

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
- independently spooled item segments, allowing one dense day to cross partitions while enforcing a 64 MiB per-item decode bound;
- 512 KiB ordered transport frames with per-frame acknowledgements;
- final digest and application acknowledgement.

A partition ACK is issued only after Mac validates the bytes, applies complete daily items, and atomically replaces its durable session journal. Replaying the same index and digest returns the recorded commit without writing files again; changing a committed digest is rejected. The aggregate session uses 64-bit counters and has no 2 GiB protocol ceiling.

| Limit | Current corpus protocol |
|---|---:|
| Maximum data bytes per transport frame | 512 KiB |
| Negotiated partition target | 32–64 MiB (48 MiB default) |
| Maximum physical partition | 64 MiB |
| Maximum independently decoded day/item | 64 MiB |
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
5. generates roll-ups one period window at a time and writes archives through a checkpointed streaming ZIP64 writer;
6. returns per-file/date results.

For strict raw, Mac validates one daily item at a time, composes the public `healthmd.raw_result` object on disk, and retains that checksummed control-response spool as a protected seven-day job artifact. Loopback downloads do not consume it. The CLI uses a download spool and bounded stdout/file copies instead of `URLSession.data(for:)` or whole-response `JSONSerialization`.

Generated examples:

- [`generated/automation/mac-export-job.json`](./generated/automation/mac-export-job.json)
- [`generated/automation/mac-export-result-success.json`](./generated/automation/mac-export-result-success.json)
- [`generated/automation/mac-export-result-partial.json`](./generated/automation/mac-export-result-partial.json)

## Cancellation and timeout

- A transient peer disconnect suspends the open journal and marks the durable Mac job paused; reconnect/hello may resend the exact stored request and reopen the identical session/fingerprint.
- A loopback client closure or waiter inactivity timeout only detaches that HTTP waiter. The durable request and resumable journal continue accepting progress and terminal results.
- Only explicit job cancellation propagates through request, transfer, and corpus-session state.
- A failed physical partition is retried with the same transfer ID and descriptor instead of restarting the corpus.
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
