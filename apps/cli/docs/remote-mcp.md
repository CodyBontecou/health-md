# Remote MCP architecture

## Status and scope

Health.md has one vendor-neutral MCP application with two deployment modes:

| Mode | Transport | Data source | Intended use |
|---|---|---|---|
| Local | newline-delimited JSON-RPC over stdio | a paired foreground iPhone over the encrypted direct protocol | Codex, Claude Desktop/Code, IDEs, and custom local MCP hosts |
| Hosted | MCP Streamable HTTP at `/mcp` | an encrypted, user-partitioned synchronized query corpus | any OAuth-capable MCP client, including web and mobile clients |

ChatGPT, Claude, Codex, and other clients are distribution targets, not architectural dependencies.
Vendor-specific manifests and review material belong under `distribution/<vendor>/`; they must not
change tool semantics, authorization, storage, or transport-independent results.

The hosted service is a resource server, not an OAuth authorization server and not a raw HealthKit
archive. It serves bounded factual query results. Pairing, diagnostics for local trust, absolute-path
exports, and durable local export jobs remain local-only.

## Components and boundaries

```text
MCP client
  -> MCP Streamable HTTP + OAuth access token
  -> healthmd-mcp transport and session policy
  -> shared healthmd-operations registry and HealthOperations service
  -> HostedDataBackend
  -> tenant/user-partitioned encrypted compact-day store

Health.md iPhone app
  -> explicit Health.md account authorization and category consent
  -> outbound HTTPS synchronization
  -> validated healthmd.query_context_day/1 records
  -> encrypted compact-day store
```

`healthmd-operations` owns the client-neutral backend interface, fixed definitions, normalization,
receipts, validation, and traversal limits. `healthmd-mcp` owns capability negotiation, MCP Apps,
JSON-RPC, Streamable HTTP, OAuth resource-server validation, and transport envelopes. Operation code
does not know whether a request arrived through CLI, stdio, or HTTP.

The local CLI adapter owns direct iPhone credentials, LAN/Tailscale listeners, and local export
paths. Hosted code cannot open those credentials or paths. `HostedDataBackend` resolves the
verified OAuth caller to exactly one corpus and rejects all local export operations.

The iPhone remains authoritative for HealthKit access and projection. It uploads the derived compact
query index, not a server request for unrestricted HealthKit access. A future outbound live relay may
refresh missing days, but hosted query availability must not synchronously depend on an unlocked,
foreground phone.

## MCP protocol surface

The canonical hosted resource is expected to be:

```text
https://mcp.health.md/mcp
```

The service supports post-batch MCP Streamable HTTP revisions `2025-06-18` and `2025-11-25`, JSON responses, MCP cancellation, bounded request and response bodies, opaque sessions, and the negotiated MCP Apps extension. Initialization with another protocol revision negotiates the latest supported revision rather than silently claiming unsupported semantics. A session expires after ten idle minutes and accepts at most 16,384 unique bounded request identifiers; MCP clients must not reuse an identifier within that session. The repository-provided server entry point
is `healthmd mcp serve-hosted`. It requires explicit `--allowed-host`, `--oauth-resource`,
`--oauth-issuer`, `--oauth-jwks-uri`, `--data-directory`, `--generation-anchor-directory`, and
`--data-key-file` values. The key file
contains exactly one base64-encoded 32-byte key, must not be a symlink, and must have mode 0600 on
Unix. An optional `--oauth-tenant-claim` makes that required signed claim an additional partition
boundary. It accepts only configured `Host` values
and rejects browser `Origin` values unless explicitly allowlisted. Allowlisted browser clients receive bounded preflight responses plus exact-origin CORS headers on successful and OAuth error responses; bearer credentials are never enabled for arbitrary origins. Deploy the Rust listener on loopback behind an HTTPS reverse proxy; the service intentionally does not terminate public TLS.

The hosted profile exposes the 13 read-only readiness, discovery, typed query, chart, sleep,
workout, comparison, coverage, and evidence tools. It omits the four local generated-file export
and job tools. Raw or generated remote exports are not enabled. If they are added later, they must
be separate asynchronous jobs that return short-lived, audience-bound download URLs rather than
server-local paths.

Tool results preserve `healthmd.query_request` and `healthmd.query_response` schema version 1.
JSON/text is authoritative. Clients that negotiate `io.modelcontextprotocol/ui` can render the same
self-contained MCP App; image-capable clients can use the PNG chart fallback.

## OAuth resource-server contract

The service publishes RFC 9728 metadata at both:

```text
/.well-known/oauth-protected-resource
/.well-known/oauth-protected-resource/mcp
```

Tokens are OAuth 2.1 bearer access tokens obtained with Authorization Code + PKCE by the client.
Authorization-server discovery, resource indicators, CIMD and/or dynamic client registration are
provided by the chosen authorization service. The MCP service validates the exact issuer and
resource audience, asymmetric JWT signature from bounded JWKS, `exp`, `nbf`, `sub`, and scopes. It
allows RS256, ES256, and EdDSA only. It never accepts shared-secret JWT algorithms.

Scopes are independent grants:

| Scope | Effect |
|---|---|
| `health.summary.read` | Read readiness, coverage, summaries, and summary query pages |
| `health.detail.read` | Request lossless detail and source evidence; summary read is still required |
| `health.sync.write` | Upload already-consented compact query days from an enrolled first-party device |
| `health.account.manage` | Create/reduce/revoke synchronization consent and delete the hosted corpus |

The temporary legacy `healthmd:read` scope is accepted only for compatibility during migration.
New hosted clients should request the standard narrow scopes above. Initial MCP challenges request only `health.summary.read`; a lossless tool call without detail access returns an OAuth `insufficient_scope` challenge for only `health.summary.read health.detail.read`. Synchronization and account scopes are never included in a read-only MCP challenge. No access token is placed in MCP tool arguments, persisted in the corpus, or logged.

Each MCP session is bound to the token's issuer, subject, audience, and trusted tenant claim. A
session cannot be reused with another grant, and every tool call is authorized with the scopes from that request's freshly verified token rather than scopes retained at initialization. The corpus partition is derived from tenant plus
subject with a keyed KDF; raw identities never appear in paths. If no tenant claim is configured,
the configured issuer plus subject is the ownership boundary.

## Synchronization and consent API

First-party mobile synchronization uses OAuth-protected routes on the same resource server. These
are data-plane routes, not MCP tools:

| Route | Required scope | Purpose |
|---|---|---|
| `GET /data/v1/status` | `health.summary.read` | Read retained-day readiness, date bounds, dataset revision, and the caller's opaque owner binding |
| `GET /data/v1/control-status` | `health.account.manage` | Read only the health-free owner binding and consent state/revision needed for mobile lifecycle reconciliation |
| `PUT /data/v1/consent` | `health.account.manage` | Set exactly the stored revision plus one, or verify an exact same-revision policy replay idempotently; acknowledge only consent revision/state |
| `POST /data/v1/days` | `health.sync.write` | Idempotently upload a bounded batch of compact days under the exact consent revision; acknowledge only changed/unchanged acceptance counts |
| `DELETE /data/v1/consent` | `health.account.manage` | Revoke at exactly the active revision plus one and crypto-erase synchronized data; acknowledge only consent revision/state |
| `DELETE /data/v1/account` | `health.account.manage` | Delete consent, encrypted corpus, and owner key material |

The iPhone client now implements enrollment, exact-resource OAuth Authorization Code + PKCE, dedicated nonmigrating when-unlocked Keychain credentials/consent, explicit metric/detail/retention UI, consent-minimized compact-day projection, digest-bound bounded upload, protected receipt journaling, opt-in foreground latest-day refresh (off by default), revocation, and account deletion. Summary projection removes evidence values/notes, workout details, and sleep-stage intervals before hashing; both summary and lossless projection remove sleep-stage aggregates or intervals whose corresponding sleep metric was not selected. Consent replacement, revocation, and deletion first fetch the health-free control status, persist its exact predecessor state/revision plus a destination-, issuer-, and opaque-owner-bound pending mutation, and pause every upload and subsequent consent/privacy mutation. An authoritative pre-commit rejection retires the tombstone and restores verified local state; an unknown outcome retains it. Recovery retries only from the exact recorded predecessor; when the target revision is already active, the client replays the exact consent policy and the server accepts it only if it is byte-for-byte equal to the stored policy. Later remote revisions and equal target revisions with a divergent state supersede stale local recovery without locking the account. Reauthorization cannot execute a pending mutation for another OAuth principal. A minimal independently persisted owner binding permits a corrupted detailed tombstone to recover only through same-owner reauthorization and destructive account deletion. Deletion retires its tombstone only after the owner-bound protected journal, local consent, refresh candidate, and token are removed. Rotated refresh credentials are saved to a separate owner-bound Keychain candidate before status verification and promoted after the server confirms the same owner, including after relaunch. Keychain state is re-read and the journal is lazily recreated after protected data becomes available. Provider-native data is not included in the first-party mobile grant. Builds without exact `HEALTHMD_HOSTED_RESOURCE_URL` and `HEALTHMD_HOSTED_OAUTH_CLIENT_ID` settings fail closed as unconfigured. Implementation is not deployment qualification: the registered OAuth client, co-resident TLS service, retention/deletion controls, and exact physical-device matrix in `apps/apple/docs/features/hosted-account-sync.md` must still pass.

Every response uses `Cache-Control: no-store`. Bodies and batches are bounded. Consent contains:

- an exact contiguous revision: each mutation is the stored watermark plus one, while only an identical same-revision policy replay is idempotent;
- no more than 512 explicit metric IDs;
- explicit source and provider IDs;
- maximum `summary` or `lossless` detail;
- retention from 1 through 3,650 days;
- optional expiration.

An upload contains at most 31 independently encoded `healthmd.query_context_day` v1 records. Each
encoded day is at most 2 MiB and the complete request at most 8 MiB. The uploader supplies a
SHA-256 digest using `healthmd.hosted.semantic-json-digest.v1`: JSON types are explicitly tagged,
lengths are fixed-width, object keys use UTF-8 byte order, signed/unsigned integers use canonical
decimal, and other finite numbers use a normalized IEEE-754 binary64 bit pattern (all positive and
negative zero spellings map to `0`). Exponent and decimal spellings that parse to the same binary64
value therefore agree across Foundation and serde. The server recomputes that cross-language digest before committing and
strictly rejects unknown fields, malformed nested values, duplicate identities, invalid local-day
intervals, unknown catalog metrics, dangling/unreferenced/empty-scope evidence, evidence attributed to
a different record metric, source/provider mismatches, and summary
payloads containing any lossless field. Ordinary values use the declared midnight-to-midnight local
owner interval; sleep sessions use that owner date's timezone-aware noon-to-noon journaling window,
including 23/25-hour daylight-saving transitions. Equal digests are idempotent. A changed authenticated day
is an atomic replacement and increments the immutable dataset revision.

Reducing consent must not merely hide retained fields. Health.md deletes affected encrypted day
objects (a full corpus purge is the safe fallback), increments the dataset revision, and requires a
new projection under the narrower grant. Revocation and account deletion crypto-erase the corpus.
Expired consent rejects uploads and reads. Retention is independent from query limits and is
enforced before every query/status snapshot, during every mutation, at service startup, and by an
hourly fail-closed maintenance sweep. Purges advance the dataset revision and stale every cursor.

## Storage and query model

Both status profiles include a 64-character opaque `owner_binding` derived from the authenticated issuer/tenant/subject corpus. It is stable across corpus deletion but differs across principals and is used by first-party clients only to prevent token, consent, journal, refresh-candidate, or tombstone state from crossing accounts; it is not an OAuth subject and must not be logged. Only the read-scoped status returns retained-day counts/date bounds/readiness; the account-management control status omits them.

The hosted corpus follows the same logical design as the macOS encrypted context store:

- one independently authenticated encrypted blob per owner day;
- an encrypted bounded manifest/index;
- a random per-owner data-encryption key wrapped by an HKDF-SHA256 key-encryption key derived from
  the deployment master key and an issuer/tenant/subject-bound opaque owner partition;
- ChaCha20-Poly1305 with random nonces and AAD binding owner, schema, and object identity;
- atomic manifest publication after day objects are durable;
- no all-history plaintext or JSON document;
- immutable dataset revisions and stale-cursor rejection;
- crypto-erasure on revoke/delete through a retained, separately protected monotonic owner-generation tombstone plus a recoverable corpus-local deletion marker;
- exclusive no-follow filesystem leases in both roots, retained capability handles for every key/manifest/anchor/object/marker operation, and generation-anchored manifest publication that rejects restored old ciphertext even when it remains AEAD-valid.

The current encrypted manifest format is storage version 3. It binds every manifest ciphertext to a strictly advancing owner generation held under `--generation-anchor-directory`; storage version 2 and earlier pre-release manifests are rejected fail closed rather than guessed or silently rewritten. The anchor directory must be a durable independently protected anti-rollback store, must be disjoint from the ciphertext directory, and must never be restored from a ciphertext backup. Restoring an old owner key/manifest/object set while retaining the current anchor fails authentication; a retained deletion tombstone causes revived ciphertext to be deleted again. Because no public hosted corpus has been qualified, operators upgrading a pre-release sandbox must delete its corpus and resynchronize from the iPhone. Any future deployed-format migration requires an explicit offline migrator, backup/rollback evidence, and a new compatibility test.

The deployment master key must come from a secret file or KMS-mounted secret, never a command-line
argument, repository file, image, or log. The file is opened once through a no-follow handle and its
size, type, Unix privacy mode, encoding, and exact 32-byte decoded length are checked on that same handle. The generation-anchor directory must live outside the ciphertext tree under independently restricted backup, snapshot, and administrative policy; compromise or rollback of both that trust anchor and the ciphertext store is outside the file backend's guarantee and must be prevented operationally or replaced by an equivalent KMS/transactional monotonic service. Account deletion first advances and retains the separately protected owner tombstone, then records a corpus-local recovery marker and removes the complete owner directory; any interruption is completed before hosted startup or a later owner operation. Crash-created atomic-write temporaries are recognized only by their exact reserved filename shape and are boundedly removed from anchor, owner key/manifest, object, and deletion-marker directories before recovery. Deletion is not complete while a restorable backup still contains both the owner key envelope and a rollback-capable anchor snapshot.
Production backup expiry, deletion propagation, rotation, regional residency, and KMS policy are
deployment controls and must be reviewed before accepting real health data.

Authenticated manifests reject unknown fields and inconsistent consent/revision, duplicate object, status, digest, size, and timestamp metadata; each decrypted day is revalidated against its manifest owner date, interval, status, semantic digest, and active consent before exposure. The evaluator loads one day and bounded neighboring days at a time where possible. Retention/crash recovery uses a short exclusive phase, immutable scans share a read gate across queries, and final page sizing holds no store gate. Workout/sleep alignment retains only bounded compact workout fields, item-scoped evidence references, and projected sleep results; intermediate item and byte budgets are enforced while scanning. Query pages are limited to 1,000 items and 1 MiB. Oversized pages use cancellation-aware logarithmic sizing rather than repeatedly serializing every shorter prefix while blocking all tenants. Cursors are authenticated, opaque, owner-bound, request-bound,
detail-bound, and dataset-revision-bound. The shared MCP application additionally limits automatic
all-page traversal to 4,096 pages and 2 MiB of returned MCP data. Cancellation is checked during
store scans and between page-sizing attempts. Evidence-packet workout detail IDs are unique, limited to 128 ASCII identifiers of at most 128 bytes, and charged to a 100,000-probe cancellation-aware operation budget.

Coverage and missingness are explicit. Exact ranges enumerate every requested owner date under the scan bound, coalesce absent snapshots into bounded `not_synchronized` intervals, and apply source filters to metrics, workouts, and sleep sessions. Missing values never become zero. Comparison periods must remain inside the top-level date selection; comparisons require an explicit aggregation, compatible units, finite arithmetic, and exact checked integer deltas for count values. Aggregate-only sleep preserves authorized totals but reports zero interval observation coverage, and overnight sessions derive every crossed local calendar date plus timezone-local labels. Sleep/workout alignment is temporal only. Every hosted response retains the factual-observations-only limitation; no tool diagnoses, recommends treatment,
or infers causation.

The first hosted evaluator intentionally reports bounded projection limitations rather than
fabricating parity: source descriptors remain item/evidence-scoped, sleep physiology is not
reconstructed server-side, timezone-local sleep labels use the synchronized timestamps, and
workout/sleep alignment is temporal only. Cross-language differential fixtures must pass before any
of these projections are described as byte-identical to the native Swift evaluator.

## Threat model and required controls

| Threat | Control |
|---|---|
| Cross-user data access | verified token subject/tenant partition, keyed ownership ID, per-call scope checks, session-to-principal binding |
| Token replay against another API | exact OAuth resource audience and issuer validation; HTTPS; short token lifetime and per-client revocation |
| Browser DNS rebinding/CSRF | explicit Host allowlist, deny-by-default Origin allowlist, bearer authorization, no cookies |
| Overbroad client grant | summary/detail/sync/manage scopes separated; explicit metric/source/detail consent |
| Server/operator filesystem disclosure | encrypted manifest and day blobs; no plaintext identities, dates, consent, or health values in paths/logs |
| Tampered upload | TLS, OAuth, canonical digest verification, authenticated encryption, schema and consent validation |
| Stale or stolen cursor | owner/request/detail/revision binding and authentication; stale revision rejection |
| Resource exhaustion | bounded headers/tokens/JWKS/body/batch/day/page/traversal/concurrency; cancellation and timeouts |
| Consent reduction while data remains | physical purge or full corpus crypto-erasure before accepting the narrower revision |
| Unknown deployment outcome | idempotent digests and revisions; inspect status before retrying a mutation |

Telemetry is health-free: service version, route class, status/error code, duration bucket, byte/count
buckets, and random request ID. Never log tokens, subjects, tenants, dates, metric IDs, arguments,
query results, cursor bodies, paths, consent content, or uploaded documents.

## Deployment and lifecycle

A production deployment requires:

1. HTTPS reverse proxy with the exact public resource URL and Host policy.
2. OAuth authorization service configured for PKCE, resource indicators, client registration,
   narrow scopes, revocation, and account deletion.
3. KMS/secret-mounted 32-byte corpus master key, encrypted backups, rotation and residency policy.
4. Durable private storage with atomic rename semantics and a single-writer or distributed-lock
   strategy per owner partition.
5. Scheduled retention/revocation cleanup and tested deletion evidence.
6. Mobile account enrollment, explicit category/detail/retention UI, background upload policy, and
   user-visible last-sync state.
7. Rate limits, bounded sanitized telemetry, incident response, and independent authorization and
   tenant-isolation tests.
8. Legal/product approval for allowed metric categories, geography, retention defaults, privacy
   disclosures, deletion SLA, and support access.

The local stdio mode remains fully functional and does not require an account, hosted service, or
synchronized corpus. Hosted deployment must never become a silent fallback from local direct mode.
