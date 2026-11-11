# History observation for export jobs, version 1

`healthmd.export_history_observation/1` records selected-type access evidence at job admission. It is independently versioned from daily exports, typed-query history metadata, raw/file envelopes and encrypted-context storage. It certifies neither full history nor current permission, and does not change capture completion or query predicates. Samples keep their original dates, including starts preceding a sample-end boundary.

A producer freezes this observation before capture and persists it with the original job. Resume returns the same observation; it never substitutes a new assessment for already captured bytes. Permission may change after observation, including during a resumed capture. Consumers must disclose that limitation. Absent observations, unsupported versions and legacy jobs remain unverified; query success and empty results cannot upgrade them.

## Version 1 grammar

The object has `schema: "healthmd.export_history_observation"`, integer `schema_version: 1`, `observation_id` and `operation_id` UUIDs, `observed_at` (canonical RFC3339 UTC instant with exactly nine fractional digits), `request_binding_sha256` (lowercase the existing immutable operation request fingerprint, as defined below), `source_id: "apple.healthkit"`, `time_zone_identifier`, sorted unique `metric_ids`, original `requested_start` and `requested_end` canonical nine-fractional-digit RFC3339 UTC instants, Boolean `all_available`, `range_semantics` (`owner_dates` or `exact_interval`), `evidence_method`, and `types` sorted by unique `type_id`. Optional `source_installation_id` and `destination_installation_id` occur together for an authenticated remote job; local files omit both.

Each type contains `type_id`, sorted unique `direct_metric_ids`, `dependency_metric_ids`, `dependency_reasons`, and `outcome`: `limited`, `unknown`, `api_unavailable`, `assessment_failed`, or `unassessed`. Only `limited` has `sample_end_boundary` (canonical nine-fractional-digit RFC3339 UTC instant). Only `unassessed` has `unassessed_reason`. Omitted HealthKit boundaries are `unknown`, never full. This grammar has no full-access outcome. Unassessed selection and dependencies remain explicit. Direct metric attribution must cover the selected metrics; every attributed metric belongs to the frozen selection. Each row attributes at least one direct or dependency metric. Dependency reasons are forbidden without dependency metrics; unresolved dependency descriptors may omit reasons while retaining an explicit unassessed reason.

Limits: canonical encoded observation at most 256 KiB; at most 512 metrics/types/identifiers per row; identifier at most 128 ASCII bytes (letters, digits, `.`, `_`, `:`, `-`); unique sorted identifiers; finite ordered dates; valid IANA timezone (or UTC/GMT). Unknown object keys are rejected in version 1. Invalid recognized observations fail closed at acquisition/ingress. Raw input must also obey the owning transport packet/sidecar byte bound before JSON decoding; re-encoding is not an input-allocation limit. Unsupported versions are not interpreted as version 1.

## Adoption and compatibility

This document defines the observation object only. A transport must explicitly negotiate version 1 and bind the observation to the authenticated operation/peer and immutable receiver checkpoint. It must not modify existing request fingerprints, cryptographic transcripts, enum discriminators, packet formats or historical fixture bytes. Generated files use a separate operation-scoped sidecar; daily documents retain their existing schema. An encrypted Mac context must persist observation provenance alongside the specific imported generation and expose only matching provenance to queries. Raw/extract presenters expose it outside the frozen raw-result body.

Apple's HealthKit evidence and Android Health Connect history permissions are distinct. Android does not produce this Apple observation. Its adapter remains planned under the existing platform staging record; absence on Android is unverified, not an inferred Apple boundary.

Implementation and physical qualification are required before advertising production support. A synthetic grammar fixture alone establishes neither native API behavior nor end-to-end acceptance.

## Request binding authority

For direct jobs, `request_binding_sha256` is exactly the existing version-pinned `DirectTransferSession.requestFingerprint` / Rust `TransferSession.request_fingerprint`, computed from the original `DirectExportRequest` by the negotiated direct protocol authority. Do not recompute it using the typed-query canonicalizer or change its bytes. The authenticated receiver must compare the observation operation UUID, request fingerprint, installation pair, timezone, and metric/range scope to its accepted immutable job. Resolved settings and resolved owner dates remain frozen by that job's existing accepted/session/journal authority; this digest does not independently certify them.

Observed encrypted-context corpus jobs use the two-stage binding described below, with the existing version-pinned fingerprint algorithm and frozen manifest/settings/date authority. Local artifact adoption must define and test its exact operation request canonicalization before emitting this contract. The observation model alone does not establish a binding: an unbound file, unknown transport, or receiver without matching request authority must be presented as unverified. No producer may advertise support until that transport's binding, persistence and output qualification are implemented.

## Synthetic conformance fixture

`synthetic-observation.json` is generated by `ExportHistoryObservationTests` with `HEALTHMD_UPDATE_EXPORT_HISTORY_FIXTURE=1`. Its Rust crate-local mirror is byte-identical and allows packaged tests to run independently. Swift tests enforce both canonical bytes and the mirror; Rust tests consume the Swift bytes. This fixture proves grammar compatibility only. Placeholder request hashes and synthetic boundaries are not authenticated capture evidence or physical permission acceptance.

## Direct optional transport fields

The optional hello field `exportHistoryObservationVersions` lists independently supported observation versions. Missing/null/empty has no support. A producer may attach `DirectExportAccepted.historyObservation` only after both endpoints select version 1. The accepted observation is persisted verbatim with the existing journal before capture; its request binding is the existing session fingerprint's `sha256` member (the fingerprint version remains separately pinned by the session/protocol authority). No request, packet, frame, pairing transcript, or raw-day manifest bytes change. Historical fixture objects with absent fields must remain byte-identical.

Receivers require an authoritative non-nil `resolvedCanonicalSelection` whenever an observation is present, and validate operation, fingerprint, peer pair, calendar, resolved metrics and original requested range before capture/transfer admission. They must not infer a metric scope from legacy defaults or skip comparison when it is missing. Legacy jobs without observations remain compatible. They reject a changed/removed observation on resume. A new client resuming an older job leaves it unassessed; a producer must never backfill evidence onto existing captured bytes. Resuming an observed job requires a peer that supports that observation version; lack of support pauses/rejects that resume rather than stripping the observation. Unknown versions are rejected rather than interpreted as v1. `synthetic-direct-job.json` records a Swift-generated request/accepted/session/capability vector with its deployed unchanged request fingerprint. The draft candidate advertises version 1 for end-to-end qualification. Production merge/release remains gated on complete producer/output/native/physical acceptance.

## Connected encrypted-context binding

`ConnectedCorpusTransferCapabilities.contextHistoryObservationVersion: 1` is
independent of corpus item/partition protocol versions. Both endpoints must select
1 and durable installation binding before a new encrypted-context job attaches
`ConnectedCorpusExportManifest.historyObservation`. Missing or unknown versions
have no support. Draft candidates advertise version 1 for qualification; production merge/release requires complete native/physical acceptance. The Rust CLI keeps its source-neutral hello unchanged for new/unknown and Android peers; it advertises Apple observations only for an established iOS source. A connection uses the version selected from its actual sent and received hellos, never a platform learned afterward.
Legacy manifests omit the field and retain their existing encoded bytes.

The observation's `request_binding_sha256` is the existing v1 corpus fingerprint
of the immutable manifest **with `historyObservation` absent**. The session's
request fingerprint is then computed by the unchanged v1 algorithm over the
**complete observed manifest**. This avoids a circular digest and binds the exact
observation, job and authenticated installation pair without changing the
fingerprint algorithm, partition envelope, daily documents or older fixtures.
The source and receiver compare selected metrics, logical All Time, original
owner dates and source/frozen-settings calendar against the operation authority.
Observed context jobs have an exact requested/original/transfer date plan; no
rollup expansion or injected extra capture day is permitted. Captured settings
come from the frozen manifest, and resumed observations are never reassessed.

Private source checkpoints use observed journal version 3 versus legacy 2;
private Mac receiver checkpoints use observed version 6 versus legacy 5.
Version/presence mismatches fail without converting observed work into a legacy
job. Older unobserved journal migrations remain unobserved. The Mac request
record pins the first accepted corpus session and fingerprint. Resuming observed
source work requires bilateral version 1 and the same installation pair.

Encrypted context keeps observation associations with selected metric scopes
inside the exact immutable authenticated day generation: observed day blobs use
version 2, legacy blobs remain version 1, and the encrypted manifest stays version
1. Scoped refreshes trim replaced associations; legacy replacements clear rather
than backfill evidence. Retained associations must still match their metric rows
and referenced evidence after the actual merge, including off-scope legacy row
replacements. Data and provenance load atomically from the same generation.

Mac queries expose fixed, bounded `history_*` limitations for matching
request/grant-selected Apple scopes. They distinguish limited, unknown,
API-unavailable, failed and unassessed acquisition evidence, without exposing
original observation objects or unrelated metrics. Provider-only queries do not
acquire Apple limitations. These limitations describe historical acquisition,
not current permission or full-history certification; capture completion retains
its existing meaning. Exact type/boundary objects remain in the authenticated
private acquisition evidence rather than being relabelled as a new query capture.

## Raw and extraction output attachment

A receiver with a validated observed job emits the unchanged observation as optional
`history_observation` on the outer raw response, beside `raw_result`. It never inserts this
field or an admission-only canonical selection into the frozen strict raw-result body.
Canonical extraction embeds the same observation in `receipt.history_observation`; JSONL
keeps it in the companion receipt, rather than inventing a health-data row. Absent evidence
omits these fields and remains unverified. These attachments do not alter capture status,
daily documents, the raw-result schema version, or the extraction protocol version.

Rust and Swift raw/file finalization pin the observation digest alongside the saved artifact
hash in private job metadata. Offline artifact, extraction, JSONL and generated-file receipt recovery require the
same immutable job request and pinned observation. An internally valid replacement journal
cannot relabel already finalized bytes. Legacy records omit the pin and remain unobserved.
The MCP raw receipt preserves validated backend observations, while the generic presenter
makes no independent endorsement and discloses admission-time scope and permission-change
limitations. Android raw metadata does not acquire an Apple observation.

## Generated-file receipt attachment

An observed direct generated-file job includes the same optional `history_observation`
in its operation receipt, outside daily documents. Fresh, resumed and offline receipt
paths preserve that frozen object; capture status and generated-file bytes retain their
existing meanings. Legacy receipts omit the field. Rust and Swift receivers require
receipt evidence to equal the validated journal and finalized private artifact pin, and
require the journal request/job to match the immutable job record. Replacing an internally
valid observation or rebinding a different request cannot relabel finalized files.

The portable MCP file receipt forwards this object and uses the same conservative
admission-time disclosure as raw exports. A generic presenter does not independently
endorse supplied evidence. The direct-receiver sidecar contract below binds this evidence to committed file
hashes. Native and physical qualification of these portable and Mac-context paths remain
required before production advertisement.

## Artifact sidecar grammar and direct receiver placement

`healthmd.export_history_file_receipt/1` is a separate operation-scoped object:
`schema`, integer `schema_version: 1`, `history_observation` (the exact v1 admission
observation), and `artifacts`. Each artifact has `relative_path`, `write_mode`
(`overwrite`, `append`, `merge_markdown`, or `merge_markdown_preserving_preamble`),
nonnegative signed-64-bit `generated_byte_count`, lowercase `generated_sha256`, and
lowercase `committed_sha256`. Both hashes are SHA-256; overwrite requires them to be equal. The generated hash describes
only this operation's contribution; the committed hash describes the complete file
after its write/append/merge. The admission observation never certifies the history
of preexisting content in a merged file.

Artifact paths are informational relative paths, not filesystem authority. Reject
empty/absolute paths, backslashes, colons, empty/dot/parent segments, C0/C1 control
characters, and paths exceeding 4,096 UTF-8 bytes. Writers must additionally use the
owning destination's complete safe-path and collision policy before any filesystem
operation. Artifacts are unique and sorted by UTF-8 path bytes, at most 100,000;
encoded metadata (compact JSON with unescaped slashes and UTF-8 text) is bounded to 64 MiB. Readers must enforce the input byte bound
before JSON decoding. Unknown keys/versions, malformed observations, invalid
hashes/modes/counts, duplicate or unsorted paths are rejected.

`synthetic-file-receipt.json` is generated by the Swift contract test and mirrored
into the packaged Rust protocol fixture. It proves grammar/hash-role compatibility,
not actual artifact contents, source authorization, or a trusted binding. Observed direct file receivers write `.healthmd/history-observations/<job_uuid>.json`
inside the explicit destination after all generated files commit. Their durable
JSON receipt carries `history_sidecar` with `relative_path`, `byte_count` and
`sha256`; the descriptor and private copy are validated on offline recovery.
Skipped existing-only notes from the independently negotiated
[scoped-note extension](../../direct-protocol/scoped-notes-v1/contract.md) have no committed artifact
and are omitted from this list; an empty artifact list is valid. Their outer file receipt records
skip paths separately and never assigns them a fabricated committed hash.
Metadata is excluded from health-file counts and transfer bytes. Observed source
manifests cannot collide with the reserved directory or its parents. A matching
sidecar is idempotent; a conflicting file or symlink fails without overwriting it.
The durable receipt describes the historical commit, even if the owner later
edits destination files. Native and physical qualification of these implemented
portable/Mac-context paths remain required before production merge/release.
Local filesystem/API-envelope adoption is a separate feature; absent metadata stays unverified.
