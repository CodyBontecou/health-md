# Health.md Raw Snapshot v1 Contract

Status: v1 normative contract. The JSON Schema is structural; the requirements in this document are the semantic conformance profile.

The key words **MUST**, **MUST NOT**, **SHOULD**, and **MAY** are normative. A producer MUST NOT claim API-complete v1 conformance when an item marked “required for API-complete v1” in the implementation-status section is absent.

## 1. Purpose and fidelity boundary

A raw snapshot is a deterministic export of provider-native records. It does not convert records to Health.md daily metrics. “Raw” means every field exposed by the pinned provider SDK has an explicit mapper, native identifiers and metadata are retained, source strings that are promised exact remain exact, and any unavoidable loss is declared in `capabilities` or an issue. It does not mean a byte-for-byte copy of a provider database.

A snapshot is **non_transactional**. Reads of different types and pages do not share a provider transaction or common revision. Records can be inserted, changed, or deleted while the export runs. `createdAt` is export creation time, not a consistency watermark. A consumer MUST NOT infer a point-in-time database image.

Health Connect remains the API-complete v1 provider at `androidx.health.connect:connect-client:1.2.0-alpha02`; its closed 54-entry inventory is [health-connect-raw-record-ledger.md](health-connect-raw-record-ledger.md). Cloud snapshots use the additive `provider_payload` record and a dynamic endpoint inventory documented in [cloud-raw-provider-ledger.md](cloud-raw-provider-ledger.md). They never serialize Health.md's normalized `HealthData` as raw.

## 2. Request and half-open range

`request.startTime` is **startInclusive** and `request.endTime` is **endExclusive**. The interval is written `[startInclusive,endExclusive)` and MUST be non-empty.

Each instant is `{ "epochSecond": integer, "nano": 0..999999999, "epochSecondExact": string }` on the UTC Java/Unix timeline. `epochSecondExact` is the exact base-10 representation of `epochSecond` for clients whose number type cannot safely hold Int64. Comparisons use `(epochSecond,nano)` without truncation. Leap seconds follow `java.time.Instant`; no local-time parsing is involved.

For the intended API-complete profile:

* an instant record is in range iff `startInclusive <= time < endExclusive`;
* an interval record is in range iff it overlaps the request: `record.startTime < endExclusive && record.endTime > startInclusive`;
* an interval ending exactly at `startInclusive`, or starting exactly at `endExclusive`, is excluded;
* Health Connect queries MAY return a broader boundary set, but the exporter MUST post-filter records to these rules;
* cloud adapters form native provider range parameters from the captured calendar zone and these `[start,end)` day boundaries; the exact server response is preserved and MUST NOT be rewritten to post-filter embedded records. Any provider boundary/summary behavior is disclosed per endpoint;
* nested samples, stages, segments, laps, deltas, and route locations belong to an included parent and MUST NOT be independently clipped;
* Personal Health Record (PHR/FHIR) medical resources have no provider temporal field and MUST NOT receive a fabricated time. They are exported without range filtering and their per-type report MUST say `rangeBehavior: unbounded_non_temporal` when that additive report field becomes available.

`pageSize` is an execution hint from 1 through 5000 and MUST NOT change logical contents. `includeExerciseRoutes=false` intentionally removes the entire `fields.route` member; it does not emit `route:null`.

### 2.1 Scope

`SELECTED_RECORD_TYPES` resolves each `selectedMetricIds` value through the catalog ledger. The union of matching native descriptors is read once. One metric can select several descriptors and one descriptor can serve several metrics. Unknown metric IDs produce an issue and make the snapshot `PARTIAL`.

`ALL_AUTHORIZED_SUPPORTED_DATA` means every catalog descriptor supported by the pinned provider plus every PHR category, constrained by permissions and feature availability. `selectedMetricIds` is ignored for selection in this scope. “All” never means data inaccessible to the app, unsupported SDK fields, another app’s private database, or normalized cloud metrics.

A Health Connect API-complete manifest MUST report all 54 ledger `typeKey` values, including types that yielded zero records. A cloud manifest MUST report every implemented endpoint capability plus explicit unsupported categories from that adapter's dynamic inventory. Selected metrics expand to whole native endpoints. Unknown/uncovered selections produce structured issues/reports rather than silence. Under selected scope, unselected entries use `not_selected`; under all-authorized scope every implemented endpoint is requested and missing permission is not silently treated as unselected.

## 3. Header

A JSON header has:

| Member | Requirement |
|---|---|
| `schema` | Exact string `healthmd.raw-snapshot`. |
| `version` | Integer `1`. |
| `snapshotId` | Stable identifier for this run; Health Connect's compatibility algorithm is the first 32 lowercase hex characters of SHA-256 over `v1\n`, `createdAt` as `epochSecond:nano`, `\n`, and canonical request JSON with `format=JSON`. Cloud sources insert `provider:<providerId>\n` after `v1\n` so independent provider artifacts cannot share an ID. |
| `createdAt` | Full-resolution export creation instant. |
| `request` | The effective request, including format, scope, half-open instant range, lexically sorted selected IDs, bounded page size, route choice, and additive IANA `calendarZoneId` captured when calendar days were converted to instants. |
| `capabilities` | Provider observations made for this export. |

`capabilities.providerId` and `capabilities.fidelityLevel` identify the actual source. Only Fitbit, Oura, WHOOP, and Withings native adapters declare `native_api_payload`; Polar and direct Samsung/Huawei/Garmin are `unsupported`. A normalized-only provider MUST NOT claim native fidelity. `capabilities.nonTransactional` MUST be `true`. For Health Connect, `preservesSourceUnits=false` means quantities were converted to documented canonical units. `preservesUnknownSdkFields=false` means the pinned explicit mapper does not preserve fields unknown to it. Neither flag permits dropping known pinned-SDK fields. Permission strings and feature names are diagnostic facts, not authorization grants to the consumer.

## 4. JSON and NDJSON artifacts

### 4.1 JSON form

Media type: `application/vnd.healthmd.raw-snapshot+json`.

The root object is emitted in logical order:

```json
{
  "header": { "schema": "healthmd.raw-snapshot", "version": 1 },
  "records": [],
  "issues": [],
  "manifest": { "schema": "healthmd.raw-snapshot.manifest", "version": 1 }
}
```

The full structural contract is [schemas/healthmd.raw_snapshot.v1.schema.json](schemas/healthmd.raw_snapshot.v1.schema.json), and each record follows [schemas/healthmd.raw_record.v1.schema.json](schemas/healthmd.raw_record.v1.schema.json). A missing or truncated `manifest` makes the JSON artifact incomplete even if it can be repaired into syntactically valid JSON.

### 4.2 NDJSON form

Media type: `application/x-ndjson`; UTF-8; one canonical JSON object plus LF per line. Envelopes are:

```json
{"header":{...},"kind":"header"}
{"kind":"record","record":{...}}
{"issue":{...},"kind":"issue"}
{"kind":"manifest","manifest":{...}}
```

There MUST be exactly one header line first, zero or more record lines, zero or more issue lines, and exactly one manifest line last. Blank lines and content after the manifest are invalid. No final NDJSON manifest means incomplete. Consumers MUST NOT accept the preceding valid lines as a completed snapshot.

JSON and NDJSON for the same logical request and creation instant MUST contain equivalent header, ordered records, ordered issues, manifest counts, and logical checksum. `request.format`, artifact bytes, artifact checksum, and final location may differ.

## 5. Deterministic canonicalization and ordering

All artifact JSON is UTF-8 without a BOM. Canonical JSON recursively sorts object keys by Unicode code-point order, emits no insignificant whitespace, and preserves array order. Strings use JSON escaping. Producers MUST reject non-finite numbers. Decimal rendering MUST be locale-independent and round-trippable.

Before hashing or output, records are sorted by:

1. `wireType` ascending;
2. nullable `startTime` (`null` first), epoch second then nano;
3. nullable `endTime` (`null` first), epoch second then nano;
4. `nativeIdentity` ascending;
5. `hash` ascending.

Nested sample-like arrays are ordered by their native instant; sleep stages, segments, and laps by start time; medical categories by numeric provider type. Planned blocks/steps/performance targets retain provider order because it is semantically meaningful. `typeCounts` and `typeReports` are ordered by key. Set-valued header fields (`selectedMetricIds`, permissions, features), dynamic inventories, maps, and report lists MUST be lexically sorted before encoding. Issues MUST retain deterministic provider traversal order: catalog order, then medical type order, and occurrence order within a type.

## 6. Duplicate rules

Deduplication is global by non-empty `nativeIdentity`. For N records with the same identity, exactly one survives and `duplicateCount` increases by N−1. The winner is, in order:

1. greatest `metadata.clientRecordVersion` (`null` metadata ranks lowest);
2. latest `metadata.lastModifiedTime`;
3. lexicographically smallest lowercase record `hash`.

`recordCount` and `typeCounts` count survivors. Duplicate elimination is not evidence that the provider returned identical payloads. A native identity group whose canonical hashes differ produces one `identity_collision` issue, increments `identityCollisionCount`, and uses the same winner rule. An identity group whose hashes are identical is deduplicated without that issue. A cross-type identity collision follows the same global rule.

## 7. Per-type status reports

API-complete Health Connect v1 requires `manifest.typeReports`, one row for every one of its 54 ledger `typeKey` values. Cloud snapshots instead require one row per declared endpoint and unsupported category in that provider's dynamic inventory. The schema requires the member. Each row contains `typeKey`, `wireType`, `status`, `recordCount`, `issueCount`, `permission`, `feature`, `rangeBehavior`, and `message`; the permission, feature, and message values may be null. `rangeBehavior` is `instant`, `overlap`, or `unbounded_non_temporal`. Exactly these status values are allowed:

| Status | Meaning |
|---|---|
| `exported` | The type was selected, readable, fully paged, and mapped. Zero records is valid. |
| `not_selected` | The type was outside `SELECTED_RECORD_TYPES`; never used merely because authorization is absent. |
| `permission_not_granted` | Its required read permission was not granted at read time. |
| `feature_unavailable` | A required SDK/provider feature was unavailable. |
| `history_permission_missing` | Requested history predates the ordinary provider window and full history access was absent. No claim of a complete range is allowed. |
| `read_error` | A permission revocation, paging failure, mapper failure, or other read error prevented a complete type read. |
| `unsupported_by_provider` | The provider implementation cannot supply this catalog type despite the cross-provider API surface. |

Precedence from highest to lowest when several conditions apply is `not_selected`, `unsupported_by_provider`, `feature_unavailable`, `permission_not_granted`, `read_error`, `history_permission_missing`, then `exported`. Thus a paging error supersedes history incompleteness and an earlier successful page. Every non-`exported` status except `not_selected` MUST have at least one matching issue. PHR reports use category keys such as `medical_resource/allergies_intolerances`, not one ambiguous aggregate row.

## 8. Issues and snapshot status

An issue contains stable machine `code`, human `message`, `severity` (`INFO`, `WARNING`, or `ERROR`), nullable `recordType`, and `retryable`. Messages are diagnostic and MUST NOT contain access tokens, authorization headers, cookies, full FHIR bodies, route coordinates, or other unnecessary health data. Unknown issue codes MUST be tolerated.

`manifest.completedAt` is the full-resolution instant when provider processing and artifact accounting finished, immediately before final manifest emission. It is not a provider consistency watermark and does not change the snapshot's `non_transactional` source semantics. Manifest status means:

* `COMPLETE`: every type the scope made readable was fully paged, no required history is known missing, and no unknown selection was requested. In `ALL_AUTHORIZED_SUPPORTED_DATA`, truthful `permission_not_granted`, `feature_unavailable`, and `unsupported_by_provider` rows do not alone make the authorized subset partial; in selected scope those statuses do;
* `PARTIAL`: a final, parseable artifact exists but one or more explicitly selected types/ranges are incomplete, an attempted readable type failed, required history may be missing, or an unknown selection was requested;
* `FAILED`: a final diagnostic artifact may exist, but it MUST NOT be treated as a data-complete export;
* `PENDING` and `RUNNING`: transient only and MUST NOT appear in a promoted final artifact;
* `CANCELLED`: reserved for external run state. Cancellation MUST abort/delete partial output and MUST NOT promote a final artifact.

A crash, cancellation, I/O failure, or missing final manifest is **incomplete**, not `PARTIAL`. `PARTIAL` is a deliberate completed artifact with a final manifest and actionable issues. `.partial` files are never consumer artifacts. Storage promotion happens only after bytes are closed; SAF copy/delete is best effort and is not a cross-provider atomic rename.

## 9. Checksums

All SHA-256 values are 64 lowercase hexadecimal characters over UTF-8 bytes unless stated otherwise.

* Health Connect `record.hash`: SHA-256 of canonical record JSON with the `hash` member omitted, after `nativeIdentity` is finalized.
* Cloud `provider_payload` `record.hash` and `providerPayload.responseSha256`: SHA-256 of exact bytes decoded from authoritative `responseBytesBase64`; fetch time and outer canonical JSON do not change this native checksum.
* `logicalChecksumSha256`: an incremental digest over header, surviving records, and issues, excluding the manifest. For each value append ASCII kind (`header`, `record`, or `issue`), one NUL byte, canonical JSON bytes, and LF. In the logical header only, normalize `request.format` to `JSON`, making JSON and NDJSON logically equivalent.
* `manifestChecksumSha256`: SHA-256 of canonical manifest JSON with both `manifestChecksumSha256` and `artifactChecksumSha256` omitted.
* embedded `artifactChecksumSha256`: currently `null`, because artifact bytes cannot include their own completed digest without recursion. The returned `RawExportResult.artifactChecksumSha256` is SHA-256 of the exact closed artifact bytes and the returned manifest copy carries it. Consumers of a file alone MUST NOT invent or trust an out-of-band artifact checksum without a trusted sidecar/API response.
* `fields.fhirResource.checksumSha256`: SHA-256 of the exact UTF-8 bytes of `fhirResourceJson`.

For a folder export, Health.md writes the immutable snapshot under `<configured-subfolder>/raw/` with range, schema version, and snapshot ID in the filename. Only after final promotion it writes `<artifact-name>.sha256` containing the lowercase artifact checksum, two ASCII spaces, the artifact filename, and LF. A missing sidecar does not invalidate the embedded logical or manifest checksum, but consumers MUST NOT claim exact artifact-byte verification without it.

For an API export, Health.md requires HTTPS and streams the completed no-backup artifact without materializing it as a string. Requests include `X-HealthMD-Schema`, `X-HealthMD-Export-ID`, `X-HealthMD-Checksum-SHA256` (the logical checksum), `X-HealthMD-Artifact-Checksum-SHA256`, `X-HealthMD-Calendar-Zone`, and `X-HealthMD-Provider`. The private temporary artifact is deleted after success or failure; a retry is a new non-transactional snapshot.

## 10. Privacy and provider/cloud fidelity

Raw snapshots contain sensitive health data, stable source IDs, package names, free-text notes, device details, FHIR resources, and optionally precise exercise routes. They MUST stay in app-private no-backup storage until an explicit user export, use least-privilege permissions, avoid logs/analytics/crash payloads, and be deleted according to user-visible retention policy. `includeExerciseRoutes` defaults true for fidelity but UI consent SHOULD call out location sensitivity.

A cloud adapter MUST distinguish exact source payload from parsed projections. It MUST preserve each exact successful page as authoritative base64 plus exact decoded text, content metadata, fetch instant, ordinal, and native checksum when claiming exact fidelity. Parsing is allowed only to discover pagination/fan-out values. It MUST declare pagination and server-side aggregation per endpoint; `serverAggregation=true` never claims record-level data. OAuth tokens, refresh tokens, request headers, cookies, and provider secrets MUST never enter records or issues. An adapter with only normalized metrics uses `unsupported_by_provider` for native types it cannot faithfully supply; it MUST NOT synthesize provider-native metadata.

## 11. Implementation status and known limitations

The contract records required behavior independently of the exporter; fidelity promises are not weakened to match an implementation limitation.

| Area | Current code | API-complete v1 requirement |
|---|---|---|
| JSON/NDJSON, canonical record sort, dedupe, hashes | Implemented. | Keep byte/logical rules stable. |
| Non-transactional and fidelity capability flags | Implemented and explicit. | Keep truthful for every provider. |
| Per-type `typeReports` | Implemented for all 42 Health Connect descriptors + 12 PHR categories, and dynamic cloud endpoint inventories. | Keep Health Connect's closed ledger and each cloud adapter's endpoint/unsupported inventory synchronized. |
| Native cloud payloads | Exact Fitbit, Oura, WHOOP, and Withings pages are streamed through the OAuth client's capture boundary. | Never replace them with normalized `HealthData`; retain capped/cycle-detected paging and WHOOP cycle-to-recovery provenance. |
| All connected | One immutable artifact per connected provider in one action; no `HealthDataMerger`, fallback, dedupe, or overlap removal. | Preserve provider-specific counts/provenance and explicit unsupported artifacts/errors. |
| Permission/feature omission under all-authorized scope | Implemented with structured reports and matching issues. | Keep truthful authorized-subset omissions from making a snapshot partial by themselves. |
| History access | Implemented per affected readable temporal type. | Keep `history_permission_missing` from claiming full-range completeness. |
| Half-open range | Explicit page-level post-filter is implemented. | Preserve exact `[startInclusive,endExclusive)` point/overlap semantics without clipping children. |
| Deterministic sets/issues | Header sets, reports, records, and issues are deterministically resolved. | Preserve lexical set/report ordering and provider traversal issue order. |
| Known SDK-field completeness | Explicit pinned mapper exists for catalog entries. | Audit every pinned SDK upgrade; unknown fields remain an explicit limitation, never reflection/`toString`. |
| PHR/FHIR | Exact FHIR JSON/checksum, nullable missing source mapping, per-category reports, and `unbounded_non_temporal` are implemented. | Preserve exact provider strings and category isolation. |
| getChanges | Snapshots remain full-read only. The independently versioned `healthmd.raw-changes` v1 backend implements token-before-snapshot bootstrap, upsertions, deletion tombstones, crash replay, and rebase handling for eligible Health Connect record types. | Keep snapshots and incremental chains separate; PHR and cloud changes/deletions remain unsupported by Health Connect `getChanges`. |
| Cancellation | Partial sink is aborted and no artifact promoted. | Preserve; a final `CANCELLED` artifact is forbidden. |
| Embedded artifact checksum | Null in file; exact digest is returned out of band, published as the folder `.sha256` sidecar after promotion, or sent in the API artifact-checksum header. | Preserve the documented sidecar/header protocol. |
| Streaming validation/import boundary | `RawSnapshotValidator` validates JSON/NDJSON one record at a time; `RawRecordDecoder` has an exhaustive wire-type switch and typed nested variants. | Keep validation independent from export and reject structural/unit/hash regressions. |
| Restore boundary | Decoded client record ID/version, recording method, device, times, offsets, fields, samples, and nested order are retained in typed DTOs. Server ID, data origin, and last-modified time are separate provenance. | Never describe server-owned provenance as restorable metadata. |
| Process restart | Restart-only, from-scratch policy; no Health Connect page token or destination credential is checkpointed. New runs remove abandoned private spools and destination `.partial` documents while registry-protecting live concurrent runs. | Never promote crash debris or place credentials/health data in WorkManager `Data`. |

Schema validation alone does not prove ordering, checksums, range behavior, field completeness, privacy, or API-complete status reporting.

## 12. Validation and typed import boundary

`RawSnapshotValidator` is the production consumer boundary. It accepts an `InputStream` and an explicit physical format, reads JSON arrays or NDJSON lines incrementally, and retains only accounting state plus the current item. It identifies the header schema and major version before record callbacks. A newer major version is rejected read-only; no repair, migration, truncation, rename, or source write is attempted. A missing header/manifest, blank NDJSON line, trailing line, or content after the NDJSON manifest is incomplete and invalid.

Validation covers canonical record order and unique identities; record/type/issue counts; type-report order and Health Connect's closed inventory; raw/manifest/logical checksums; optional exact artifact and sidecar checksums; full-resolution exact integer strings; finite decimal round trips; nullable offset shape; raw+label enums; canonical quantity families and units; nested ordering; provider base64, byte checksum, strict charset/text agreement; and exact UTF-8 FHIR string checksums. Validation failures contain stable codes and structural locations only. They MUST NOT interpolate record values, provider text, FHIR, route coordinates, credentials, or source issue messages.

`RawRecordDecoder` returns independent typed DTOs for all 42 ordinary wire types, every planned-goal/target and route variant, PHR/FHIR payloads, and cloud provider pages. Additive unknown v1 members are retained by JSON pointer in `additiveUnknownFields`; missing/wrong known members and wrong canonical units are rejected. This is not a generic `JsonObject` restore path. Executable coverage and SDK fixture limitations are listed in [raw-import-test-matrix.md](raw-import-test-matrix.md).

The decoder deliberately does not expose a blanket `toInsertableRecord()`. Constructor and feature availability differs across Health Connect installations, and server-assigned `Metadata.id`, `dataOrigin`, and `lastModifiedTime` cannot be supplied to an insert. `RestorableClientMetadata` contains only client record ID/version, recording method, and device. `NonRestorableMetadata` keeps the original server ID, origin package, and last-modified instant as provenance. A later insertion adapter MAY construct an SDK record from the typed DTO and restorable metadata after runtime feature checks; it MUST NOT claim that server provenance was restored. PHR records decode to exact FHIR DTOs and cloud pages to exact provider payload DTOs, never to Health Connect `Record` values.

## 13. Deliberate restart-only resilience policy

Manual raw export remains an explicitly user-scoped ViewModel coroutine. Scheduled raw export already runs inside `ExportWorker`. A second disconnected foreground worker was not added because securely reproducing a manual action would require durable request/destination state and could mislead users into believing a non-transactional provider snapshot resumes at a consistency point. In particular, destination authorization, custom headers, OAuth material, FHIR, provider bytes, and Health Connect page tokens MUST NOT be placed in WorkManager `Data`.

After process death, the next explicit or scheduled run starts the complete non-transactional snapshot again with a new creation instant. The in-process registry protects live concurrent spool/partial paths. Because that registry is empty in a new process, run startup deletes abandoned installation-private `spool-*` directories and stale destination `.partial` documents before opening the new partial. Final names are created/promoted only after the new manifest is closed. No old partial is promoted, and no page token is resumed. This restart-only behavior is safer and more truthful than token checkpointing across provider mutation.
