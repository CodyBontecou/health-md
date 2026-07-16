# Connected Mac–iPhone protocol

Health.md uses a versioned connected-app protocol to request iPhone HealthKit work and deliver files or strict raw results to Mac. This protocol is independent of the public daily file schema.

```text
Mac CLI
  → localhost control API
Mac app
  → iPhone export request
Open connected iPhone
  → HealthKit capture and export preparation
  → bounded transfer offer/chunks/completion
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
- strict raw streaming;
- accepted canonical archive versions;
- accepted raw-result versions;
- request/settings fields supported by each peer.

A lossless file job is rejected when the peer cannot preserve the requested current archive. Strict raw never silently downgrades to the legacy internal `raw_data` path.

Summary-only and explicitly non-granular file jobs can use older negotiated paths when they do not claim a lossless archive.

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

File mode produces a `MacExportJob` containing the captured daily data and exact settings snapshot needed for Mac-side path planning/export. Strict raw produces a canonical raw-result envelope containing public daily JSON.

The iPhone output subfolder from the captured settings is applied beneath the Mac-selected root. A missing field from an older peer uses the documented Mac-local compatibility fallback.

### 4. Bounded transfer

Current lossless jobs and strict raw results use an offer/chunk/complete protocol with:

- a transfer identifier and payload kind/version;
- declared total byte count;
- SHA-256 digest;
- fixed ordered chunk indexes/count;
- per-message validation and acknowledgements;
- duplicate chunk acknowledgement without duplicate application;
- disk spooling/reassembly on the receiver;
- final digest validation before decoding/application;
- explicit rejection reasons.

Limits:

| Limit | Value |
|---|---:|
| Maximum data bytes per chunk | 512 KiB |
| Maximum chunk count | 8,192 |
| Maximum declared transfer | 2 GiB |

Transport framing adds overhead beyond chunk data. These bounds prevent unbounded messages but do not eliminate memory pressure during HealthKit capture or final serialization.

Generated message examples:

- [`generated/automation/transfer-offer.json`](./generated/automation/transfer-offer.json)
- [`generated/automation/transfer-chunk.json`](./generated/automation/transfer-chunk.json)
- [`generated/automation/transfer-acknowledgement.json`](./generated/automation/transfer-acknowledgement.json)
- [`generated/automation/transfer-complete.json`](./generated/automation/transfer-complete.json)
- [`generated/automation/transfer-rejection.json`](./generated/automation/transfer-rejection.json)

### 5. Mac application

For file mode, Mac:

1. validates the job and requested schema/archive capabilities;
2. resolves the selected root and captured iPhone subfolder;
3. writes selected daily/roll-up/entry/dictionary/sidecar files with shared exporters;
4. records safe progress and history;
5. returns per-file/date results.

For strict raw, Mac validates the envelope and returns it through the local control response without writing files.

Generated examples:

- [`generated/automation/mac-export-job.json`](./generated/automation/mac-export-job.json)
- [`generated/automation/mac-export-result-success.json`](./generated/automation/mac-export-result-success.json)
- [`generated/automation/mac-export-result-partial.json`](./generated/automation/mac-export-result-partial.json)

## Cancellation and timeout

- Client disconnect or timeout cancels the coordinator request when possible.
- User cancellation propagates through request state.
- Late results for no-longer-active jobs are ignored.
- Transfer/session cleanup removes spool files without changing an already accepted result.
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
- Request smaller ranges for routes, ECGs, documents, or attachments.
- Treat a successful transport as separate from complete HealthKit capture; inspect the daily manifest.
- Treat a valid checksum as transport integrity, not proof of semantic completeness.
