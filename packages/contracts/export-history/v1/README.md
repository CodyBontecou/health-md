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

Connected corpus adoption must similarly use its existing version-pinned session request fingerprint and frozen manifest/settings/date authority. Local artifact adoption must define and test its exact operation request canonicalization before emitting this contract. The observation model alone does not establish a binding: an unbound file, unknown transport, or receiver without matching request authority must be presented as unverified. No producer may advertise support until that transport's binding, persistence and output qualification are implemented.

## Synthetic conformance fixture

`synthetic-observation.json` is generated by `ExportHistoryObservationTests` with `HEALTHMD_UPDATE_EXPORT_HISTORY_FIXTURE=1`. Its Rust crate-local mirror is byte-identical and allows packaged tests to run independently. Swift tests enforce both canonical bytes and the mirror; Rust tests consume the Swift bytes. This fixture proves grammar compatibility only. Placeholder request hashes and synthetic boundaries are not authenticated capture evidence or physical permission acceptance.

## Direct optional transport fields

The optional hello field `exportHistoryObservationVersions` lists independently supported observation versions. Missing/null/empty has no support. A producer may attach `DirectExportAccepted.historyObservation` only after both endpoints select version 1. The accepted observation is persisted verbatim with the existing journal before capture; its request binding is the existing session fingerprint's `sha256` member (the fingerprint version remains separately pinned by the session/protocol authority). No request, packet, frame, pairing transcript, or raw-day manifest bytes change. Historical fixture objects with absent fields must remain byte-identical.

Receivers require an authoritative non-nil `resolvedCanonicalSelection` whenever an observation is present, and validate operation, fingerprint, peer pair, calendar, resolved metrics and original requested range before capture/transfer admission. They must not infer a metric scope from legacy defaults or skip comparison when it is missing. Legacy jobs without observations remain compatible. They reject a changed/removed observation on resume. A new client resuming an older job leaves it unassessed; a producer must never backfill evidence onto existing captured bytes. Resuming an observed job requires a peer that supports that observation version; lack of support pauses/rejects that resume rather than stripping the observation. Unknown versions are rejected rather than interpreted as v1. `synthetic-direct-job.json` records a Swift-generated request/accepted/session/capability vector with its deployed unchanged request fingerprint. Live advertisement remains disabled until producer, output and physical qualification are complete.

## Raw and extraction output attachment

A receiver with a validated observed job emits the unchanged observation as optional
`history_observation` on the outer raw response, beside `raw_result`. It never inserts this
field or an admission-only canonical selection into the frozen strict raw-result body.
Canonical extraction embeds the same observation in `receipt.history_observation`; JSONL
keeps it in the companion receipt, rather than inventing a health-data row. Absent evidence
omits these fields and remains unverified. These attachments do not alter capture status,
daily documents, the raw-result schema version, or the extraction protocol version.

Portable raw finalization pins the canonical observation digest alongside the saved artifact
hash in private job metadata. Offline artifact, extraction, and JSONL recovery require the
same immutable job request and pinned observation. An internally valid replacement journal
cannot relabel already finalized bytes. Legacy records omit the pin and remain unobserved.
The MCP raw receipt preserves validated backend observations, while the generic presenter
makes no independent endorsement and discloses admission-time scope and permission-change
limitations. Android raw metadata does not acquire an Apple observation.
