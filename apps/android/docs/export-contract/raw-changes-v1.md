# Health.md Raw Changes v1 Contract

Status: v1 normative contract. This contract is independently versioned and is **not** `healthmd.raw-snapshot`, a compatibility export, or a date-range export.

## 1. Identity and scope

The schema identifier is exactly `healthmd.raw-changes`; `version` is `1`. The provider is Android Health Connect through `androidx.health.connect:connect-client:1.2.0-alpha02` `getChangesToken` and `getChanges`.

A scope is the exact, lexically sorted set of Health Connect `Record` type keys plus an exact, lexically sorted set of `DataOrigin.packageName` filters. Its `scopeHash` is lowercase SHA-256 of UTF-8 `healthmd.raw-changes.scope.v1\n` followed by canonical scope JSON. Durable state is keyed only by that canonical hash and stores the canonical JSON to detect a hypothetical hash/scope mismatch. Empty origin filters mean all origins readable by the app; they do not mean cloud providers.

All 42 ordinary entries in `HealthConnectRecordCatalog` are changes-eligible when their documented Health Connect feature is available. If a selected gated type is unavailable before token creation, the action returns `UnavailableScope` with sorted type and feature names; it creates no archive and claims no coverage. PHR/FHIR `MedicalResource` and Health.md cloud-provider payloads are `unsupported_changes_api`; they are not passed to `ChangesTokenRequest`. This archive never claims PHR/cloud deletion coverage. A `provider_payload` RawRecord or cloud tombstone is invalid in raw-changes v1; cloud snapshots must be recaptured as immutable full-page artifacts.

## 2. Header and chain

The header contains:

* `schema`, `version`, stable `archiveId`, `chainId`, and monotonically increasing `sequence` (first catch-up is 1);
* nullable `previousArchiveLogicalHash` (null only at sequence 1);
* `scopeHash`, exact selected `recordTypeKeys`, and exact `dataOriginPackageNames`;
* captured provider, pinned SDK, sorted provider capabilities, and full-resolution `createdAt`;
* `tokenSemantics`: generation time, whether generation occurred before the base snapshot, 30-day SDK validity, `opaqueTokenExported=false`, and `advancesOnlyAfterDurability=true`;
* `consistency=non_transactional_at_least_once`.

The opaque changes token, its plaintext, reversible encoding, digest, prefix, suffix, length, and provider error echo MUST NOT occur in an archive, sidecar, log, exception message, analytics, crash payload, settings JSON, or backup.

## 3. Events and identity index

An upsertion event embeds exactly the v1 `RawRecord` produced by `RawHealthConnectMapper`; no second mapper, reflection, or `toString` representation is permitted. Snapshot and changes representations for the same native record are byte-equivalent canonical `RawRecord` values.

A deletion has the provider's exact `nativeRecordId`, nullable `wireType`, nullable `typeKey`, nullable `dataOriginPackageName`, nullable `lastKnownRecordHash`, full-resolution `observedAt`, and `eventHash`. Type/origin/hash come only from the installation-local committed identity index or an earlier upsertion in the same run. If no entry exists they MUST be null and `unknownDeletionCount` increases; a producer MUST NOT guess.

Every event has an observed provider ordinal starting at 1. Events are emitted in ascending ordinal, preserving page then response-list order. `eventHash` is an idempotency SHA-256: it hashes canonical event JSON without `eventHash` or archive-local `ordinal`, and deletion hashes also omit archive-local `observedAt`. Repeated events are legal; consumers deduplicate by event hash according to their retention needs. A replay may produce another archive containing the same logical event. This is at-least-once delivery, not exactly-once delivery.

The identity index maps `(scopeHash,nativeRecordId)` to type key, wire type, origin, and last known RawRecord hash. It is disk indexed and queried per event; the exporter MUST NOT load the complete index into memory. Base indexing and archive mutations are staged. They become visible in one SQLite transaction only after base/archive durability and token advancement prerequisites are satisfied.

## 4. Artifact, ordering, reports, and final manifest

The v1 artifact is canonical UTF-8 JSON:

```json
{"header":{},"events":[],"issues":[],"manifest":{}}
```

Object keys use the same canonical JSON rules as raw snapshot v1. Header is first, events are ascending `ordinal`, issues retain deterministic occurrence order, and the manifest is last. Missing/truncated/followed-by-content manifest means incomplete. Only `COMPLETE` is a promoted v1 status. Cancellation, crash, provider failure, or storage failure removes/unpublishes a partial; it is not `PARTIAL`.

`typeCounts` is sorted by wire type. `typeReports` is sorted by type key and covers all 42 ordinary catalog descriptors plus all 12 PHR categories. Ordinary statuses are `exported`, `not_selected`, `permission_not_granted`, or `feature_unavailable`; PHR is `unsupported_changes_api`. The manifest separately names `cloud_providers` and `personal_health_record` in sorted `unsupportedCategories`. Counts include upsertions, known deletions, unknown deletions, pages, issues, and totals. Unknown tombstones appear under `unknown_deletion`, never under a guessed native type.

The provider is non-transactional: pages do not constitute a provider transaction, and records can change while pages are drained. A page can repeat after process death. Consumers MUST tolerate duplicate upsertions/deletions and MUST NOT infer an exactly-once or point-in-time view.

## 5. Checksums

All hashes are 64 lowercase hexadecimal SHA-256 values.

* `RawRecord.hash` is unchanged from raw-record v1.
* `eventHash` is canonical event JSON without that member.
* `logicalChecksumSha256` incrementally digests header/events/issues, excluding manifest. For each append ASCII kind (`header`, `event`, `issue`), NUL, canonical JSON bytes, and LF.
* `manifestChecksumSha256` hashes canonical manifest JSON with `manifestChecksumSha256` and `artifactChecksumSha256` omitted.
* Embedded `artifactChecksumSha256` is null to avoid recursion. The backend result contains SHA-256 of exact closed bytes.
* After promotion, `<archive>.sha256` contains `<artifact hash>  <archive filename>\n`. Token state cannot advance before this sidecar is durable for the built-in destination.

## 6. Commit, failure, crash, and rebase

Processing is page-bounded and externally spooled. The producer MUST fetch every page, close/sync the event spool, write a final manifest, close/sync artifact bytes, promote the artifact, durably publish the sidecar, and only then atomically apply identity mutations plus encrypted chain/token state. `nextChangesToken` remains memory-only until that final transaction. The prior token and identity index remain unchanged on any failure before it.

Checkpoints live under `noBackupFilesDir/raw-changes/checkpoints`. Preparation/promotion is identified by archive ID and exact artifact checksum. A promoted archive is never rebuilt with different bytes. If promotion happened but chain commit did not, restart verifies/finishes its sidecar, marks that artifact orphaned from chain state, discards staged identities, and rereads the prior token into a new archive. This deliberately allows duplicate events rather than misses. A crash before preparation likewise discards the staged run and rereads the prior token.

If `changesTokenExpired` is true (including the SDK's API-34 invalid-token mapping), the result is `rebase_required`. No archive is promoted, no new token is silently requested, and existing chain/index state is unchanged. Rebase uses the full bootstrap sequence below and creates a new chain.

## 7. Safe bootstrap

The strict coordinator enforces:

1. Canonicalize scope and call `getChangesToken`.
2. Durably checkpoint that encrypted token.
3. Enter the caller's base-snapshot callback. The callback writes a complete `healthmd.raw-snapshot` with final manifest/promotion/sidecar and stages every emitted `RawRecord` in the supplied disk index.
4. Reject a callback receipt not marked durable.
5. Drain `getChanges` from the token captured in step 1, staging upsertions/deletions and writing sequence-1 catch-up archive.
6. In one state transaction, clear every identity from the scope's prior chain, apply the base/catch-up mutation journal, and make the new token, chain ID, sequence, and logical hash visible only after both artifacts are durable.

The initial token is generated before the base snapshot. A change concurrent with the full snapshot is therefore either present in the base, catch-up, or both. Duplicates are allowed and misses are not. The current date-range UI cannot explain bootstrap/rebase and does not expose this backend. `ExportMode` remains unchanged; raw snapshot remains the default raw product.

## 8. Private state and backup

The state database, WAL, pending run indexes, token ciphertext, spools, and private archives are rooted under `noBackupFilesDir/raw-changes`. Token ciphertext is AES-GCM with a randomized nonce and an installation-bound AndroidKeyStore key. No shared preference, ordinary database directory, settings store, or backup-transfer domain contains this material. Uninstall/key loss makes ciphertext intentionally unrecoverable and requires bootstrap.
