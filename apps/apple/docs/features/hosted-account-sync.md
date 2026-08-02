# Hosted account synchronization on iPhone

## Status

The iPhone client implementation exists, but hosted synchronization is **disabled unless the exact build is configured** with both:

- `HEALTHMD_HOSTED_RESOURCE_URL` — the exact HTTPS MCP resource URL, including its `/mcp` path;
- `HEALTHMD_HOSTED_OAUTH_CLIENT_ID` — the registered first-party public OAuth client.

An unconfigured build shows Hosted Health.md as unavailable. It does not fall back to a local CLI, the Mac app, another host, or plain HTTP. Production availability remains blocked until the OAuth client, co-resident TLS deployment, privacy controls, and physical-device qualification in this document pass.

## User flow and consent

On iPhone, **Settings → Integrations → Hosted Health.md** provides the complete account flow:

1. Connect through OAuth 2.1 Authorization Code + PKCE. The app discovers the RFC 9728 protected-resource metadata and authorization-server metadata, requests only `health.sync.write` and `health.account.manage`, binds the request to the exact resource indicator, uses an ephemeral authentication browser, and verifies one exact callback state and code.
2. Review and activate an explicit synchronization grant. The user selects metric IDs, maximum `summary` or `lossless` detail, and retention from 1 through 3,650 days. The source grant is fixed to Apple Health and Health.md summary evidence; provider-native sources are not uploaded by this first-party path.
3. Synchronize up to the selected retention window. Only completed calendar days are eligible. The user can separately opt in to an idempotent latest-completed-day refresh after a later foreground activation; it is off by default and never runs while protected data is unavailable.
4. Replace consent, revoke synchronization and crypto-erase synchronized data, or delete hosted account data and owner key material. These operations do not delete local Apple Health data.

Read-only MCP authorization is separate. The mobile enrollment grant requires the token response to contain exactly `health.sync.write` and `health.account.manage`; it rejects `health.summary.read`, `health.detail.read`, or any other extra scope. An MCP read challenge never asks for synchronization or account-management scopes.

## Projection and minimization

The uploader creates canonical `healthmd.query_context_day` version 1 documents on iPhone. HealthKit acquisition is restricted to the selected metric set, except that selecting `sleep_total` also preserves local bedtime/wake boundaries needed to derive the complete sleep session; those structural fields do not become separately uploaded metrics unless selected. Before hashing or upload, a second consent projection:

- removes metrics outside the selected set;
- removes workouts unless `workouts` is selected;
- removes sleep sessions unless `sleep_total` is selected;
- retains only referenced evidence from explicitly allowed sources/providers when every attributed metric is selected; mixed-scope, empty-scope, and unreferenced evidence is discarded before hashing;
- removes stale references to discarded evidence;
- for summary grants, removes evidence values and notes, workout detail dictionaries, and sleep-stage intervals;
- for every grant, removes sleep-stage intervals and aggregate keys unless the corresponding `sleep_total`, `sleep_deep`, `sleep_rem`, `sleep_core`, `sleep_awake`, or `sleep_in_bed` metric is selected;
- for lossless grants, retains the remaining details only when the selected HealthKit acquisition produced them.

Each minimized day is bound with the versioned `healthmd.hosted.semantic-json-digest.v1` SHA-256 construction: JSON types have explicit tags, lengths are fixed-width, object keys use UTF-8 byte order, signed/unsigned integers use canonical decimal, and other finite numbers use a normalized IEEE-754 binary64 bit pattern. Positive and negative zero both map to `0`. This avoids platform-specific JSON exponent, decimal-threshold, and negative-zero spelling. The client rechecks the semantic digest immediately before dispatch. Range synchronization captures one day at a time and flushes an accepted/journaled batch before acquiring the rest; it never retains the complete requested range in memory. The server independently recomputes the same digest and strictly revalidates every top-level and nested field, type, identifier, source/provider/evidence relationship, local-calendar interval, summary redaction, catalog metric, and expected consent revision. Day ownership is timezone-aware midnight-to-midnight, while attributed sleep sessions must remain inside the same owner date's noon-to-noon sleep window so normal overnight sessions cross midnight safely.

One day is limited to 2 MiB. One request contains at most 31 unique owner dates and is limited to 8 MiB. Equal day digests are idempotent. The client writes the local synchronization journal only after the server accepts a batch.

## Credential, network, and local-state policy

OAuth access/refresh tokens, local consent, and pending mutation tombstones are stored only in a dedicated Keychain service using `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`; they are unavailable while locked and do not migrate through backup. Every persisted credential is bound to the exact resource URL, public client ID, discovered issuer, and a server-issued opaque binding for the authenticated issuer/tenant/subject corpus. Local consent, automatic-refresh preference, and recovery tombstones carry the same owner binding. A build-configuration, issuer, or principal change therefore requires fresh authorization and explicit consent instead of replaying old state against a different corpus. Immediately before consent replacement or revocation, the client fetches health-free control status and uses its authoritative predecessor state/revision; this prevents an app restart after revocation from reusing revision 1. Before replacement, revocation, or deletion is dispatched, the client durably records intent and immediately pauses every upload and subsequent consent/privacy mutation. A definitive pre-commit rejection retires the tombstone and restores verified local state, while a lost or malformed response remains unknown and retains recovery. A lost response is reconciled only when the remote state is the exact recorded predecessor or target revision; a target-revision consent is replayed byte-for-byte and accepted only when the server confirms that exact policy as idempotent. Every non-replay mutation must use the exact authoritative predecessor plus one; revision jumps and overflow fail stale. A later authoritative revision, or an equal target revision with a divergent state, supersedes stale local recovery without permanent lockout; rollback states remain fail closed. If the credential is unavailable, reauthorization may recover only the same opaque owner; another account is rejected without executing the pending operation. A minimal independently persisted owner-binding record means corruption of the detailed tombstone can recover only through same-owner reauthorization and destructive hosted-account deletion. Deletion resets the protected journal, removes local consent, a rotated-refresh candidate, and the token with stop-on-failure semantics, and retires the tombstone last. A newly rotated refresh token is persisted in a separate owner-bound candidate slot before status verification and promoted only after the server confirms that owner; candidate verification resumes after relaunch, refreshes the candidate first if its access token expired, and allows reauthorization after a definitive invalid-grant rejection. Keychain state is re-read and the protected journal is recreated lazily after protected data becomes available. Automatic refresh is off by default. Persisted tokens, scopes, consent identifiers, revisions, mutation state, owner bindings, and bounds are validated before use. Bearer tokens containing whitespace, controls, invalid token characters, or excess bytes are rejected.

OAuth metadata, authorization, token, and data-plane URLs must be HTTPS and free of embedded credentials or fragments. Resource URLs also reject query parameters. Authorization and token endpoints must have the exact issuer origin. The URL sessions are ephemeral, have no cookie store or URL cache, reject redirects, cap response bytes, and require `Cache-Control: no-store` on token and data-plane responses. Mobile consent/revocation acknowledgements contain only consent revision/state, and upload acknowledgements contain only consent revision plus accepted changed/unchanged counts; the client rejects unknown response keys. Corpus date bounds, retained-day counts, purge counts, readiness, and dataset revisions require read scope and are not returned to the enrollment grant.

The synchronization journal contains the exact resource/client/issuer/opaque-owner binding, consent revision, owner-date-to-digest receipts, and the last successful synchronization time. Manual and automatic uploads require every binding field and the exact consent revision to match, then perform a health-free `/data/v1/control-status` preflight before any HealthKit capture or health-data dispatch. The read-scoped `/data/v1/status` route, which can expose retained-day counts and date bounds, is never called with the mobile enrollment grant. Automatic latest-day refresh is throttled to at most once per 15 minutes, runs in a dedicated activation task, is cancelled on background entry, and rechecks foreground state before capture and every upload dispatch. It is excluded from backup and uses complete iOS file protection. The implementation opens one trusted application-support directory capability, traverses/creates private children with `openat`/`mkdirat` and `O_NOFOLLOW`, rejects links and non-regular journals, caps the file at 512 KiB/3,650 dates, writes a mode-0600 temporary file, synchronizes it, atomically renames it, and synchronizes the directory. If this protected journal cannot be established, consent activation and upload fail closed.

No token, health value, document, owner date, metric selection, or digest is logged. User-visible failures use bounded generic descriptions.

## Deployed physical-device qualification

Use an exact candidate iPhone build produced from a fixed source commit. Do not qualify with an ad hoc locally modified app or a different OAuth client. The endpoint must be the intended public HTTPS resource behind its co-resident reverse proxy; direct public access to the loopback Rust listener is invalid.

Record only health-free evidence. Evidence may include fixed build/source identifiers, device and OS versions, route/status classes, bounded byte/count buckets, pass/fail outcomes, consent/dataset revision numbers, and SHA-256 digests of sanitized evidence files. Do not record tokens, OAuth subjects, dates, metric IDs, selected categories, health values, query bodies/results, day digests, corpus paths, or screenshots containing those fields.

### Required matrix

1. **Configuration, disclosure, and TLS**
   - Before enabling either build key, update `PrivacyInfo.xcprivacy`, App Store Connect App Privacy answers, `NSHealthShareUsageDescription`, the customer privacy policy, and in-app disclosure for linked Health/Fitness data collected solely for app functionality; keep tracking false. An unconfigured local-only build must not falsely imply an active hosted collection path.
   - Verify the built `Info.plist` contains the exact registered resource and client ID.
   - Verify the public certificate chain, exact Host policy, redirect rejection, and that the backend listener is loopback-only.
   - Verify protected-resource metadata names the exact resource and required scopes; verify authorization metadata uses same-origin HTTPS authorization/token endpoints and advertises S256.
2. **Enrollment and token lifecycle**
   - Complete Authorization Code + PKCE on the physical iPhone.
   - Reject callback state mismatch, duplicate state/code, OAuth error, fragment, wrong custom-scheme host/path, insufficient scopes, malformed token, missing `no-store`, redirect, and oversized response.
   - Expire the access token and verify one refresh/rotation path. Interrupt after token rotation but before owner-status verification, relaunch, and verify the owner-bound candidate is verified/promoted without losing the rotated credential; verify an invalid refresh grant fails without sending data under an unverified credential.
3. **Explicit consent**
   - Activate a narrow summary grant and verify exact revision/status.
   - Replace it with a narrower grant and prove the prior corpus is purged before new upload.
   - Exercise retention boundaries 1 and 3,650 and reject 0/3,651, empty metric scope, unknown identifiers, stale revisions, and over-limit sets.
4. **Compact-day upload**
   - Synchronize 1 day, 31 days, and multiple bounded batches.
   - Verify summary minimization and a separately consented lossless projection without capturing values in evidence.
   - Retry an accepted digest and verify unchanged/idempotent accounting.
   - Reject a digest/document mismatch, duplicate owner date, over-2-MiB day, over-8-MiB request, out-of-consent metric/source/provider/detail, and stale consent revision; verify that an authenticated changed day is accepted as an atomic replacement and advances the dataset revision.
   - Interrupt before a consent/revoke/delete response and verify the persisted mutation tombstone immediately suppresses uploads, then inspect the exact predecessor/target revision watermark and reconcile safely. Attempt recovery with a different OAuth principal at the same issuer and verify its opaque owner binding is rejected without dispatching the pending mutation. Interrupt an upload before response and retry its digest idempotently; interrupt after one accepted batch and verify only accepted batch receipts are journaled.
5. **Lifecycle and recovery**
   - Relaunch the app, verify Keychain-backed connection/consent recovery and owner-bound journal validation, then foreground-sync the latest completed day. Launch once while protected data is unavailable, unlock, and verify credentials/tombstones are rehydrated and the journal is recreated rather than remaining permanently absent. Corrupt a non-pending local record and verify explicit local reset; corrupt a detailed pending tombstone and verify only same-owner reauthorization plus destructive hosted deletion can clear it.
   - Interrupt server account deletion after its durable marker and after partial corpus removal; verify startup completes deletion before serving and never reports success for permission/I/O failures.
   - Verify locked/protected-data state suppresses automatic synchronization.
   - Corrupt/oversize the journal and substitute linked directory/file entries; verify upload fails closed and no destination outside the capability changes.
   - Verify retention maintenance, consent expiration, revocation, account deletion, and backup/key deletion evidence at the service.
6. **Read-only MCP parity and isolation**
   - With a separately authorized read client, verify hosted summary tools read only the enrolled owner corpus.
   - Verify lossless calls require `health.detail.read` and synchronization/account scopes do not grant reads.
   - Run two test principals/tenants and prove session, cursor, status, upload, revoke, and delete operations cannot cross partitions.
7. **Privacy audit**
   - Inspect iPhone unified logs, reverse-proxy/service telemetry, OAuth logs, crash reports, and generated evidence for prohibited fields.
   - Confirm all captured artifacts satisfy the health-free evidence rules above.

### Qualification record

Store the signed candidate record with release evidence, not in app telemetry:

```text
source_commit=<40 lowercase hex>
mobile_build=<marketing version> (<build>)
device_model=<model>
device_os=<version>
hosted_resource_sha256=<digest of exact resource string>
oauth_client_sha256=<digest of exact public client ID>
tls_profile_sha256=<sanitized evidence digest>
enrollment=pass
summary_sync=pass
lossless_sync=pass
refresh_recovery=pass
consent_reduction_purge=pass
retention=pass
revoke_delete=pass
tenant_isolation=pass
privacy_log_audit=pass
evidence_sha256=<digest of health-free evidence bundle>
```

Hosted account synchronization remains unqualified while any row is missing, pending, malformed, executed against another artifact/deployment, or supported only by simulator tests.
