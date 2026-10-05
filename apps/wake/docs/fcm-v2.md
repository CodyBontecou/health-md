# Notification-only FCM v2 Worker extension

Status (2026-10-04): **Worker slice implemented and locally tested; Android P3/B15
remains planned/incomplete.** Nothing here enables, provisions, deploys, or
qualifies a native/CLI release. The deployed APNs P2 service is not replaced.
The canonical RFCs, direct-channel contracts, native trust stores, and CLI
consumer changes belong to later coordinated work.

## Outcome and boundary

An opted-in paired owner can receive a generic visible nudge, tap it, and open
Health.md. The notification grants no read permission or direct-session
execution authority. All health data remains on the existing authenticated
peer-to-peer path.

FCM is selected explicitly at new `/wake/v2/*` endpoints. Legacy
`/wake/register` still accepts APNs `deviceToken`, not FCM tokens. The additive
migration gives existing rows and legacy inserts `transport='apns'` and
`registration_version=1`; it does not reinterpret tokens. V2 currently permits
only `transport='fcm'`. V1 endpoints cannot rotate, revoke, clear the counters
of, or ring a v2 row. V2 endpoints cannot manage or ring a v1 row.

### Legacy security semantics (not strengthened retroactively)

- V1 initial enrollment is open resource creation, not authenticated install or
  account ownership. V1 rotation checks `userId` and an existing opaque `wakeId`;
  v1 revocation matches those identifiers. **`userId` alone is not cryptographic
  authentication, and knowing both IDs is sufficient for legacy management.**
- The legacy DELETE also clears v1 counter/nonce state for the supplied wake ID,
  even when the install identifier does not match. This legacy behavior is not
  a security claim and is not copied into v2. New v2 rows are protected from it.
- V1 wake HMAC proves possession of the registered SHA-256 hash. The hash itself
  is a bearer signing secret, not a safe public verifier or proof that the raw
  wake key is the only possible authenticator. The same applies to v2 hashes.
- V1 HMAC does not bind the supplied peer label; legacy sanitization and copy
  remain unchanged. Legacy nonce uniqueness is global in its historic table;
  v2 replay state is scoped per wake ID.
- Documented v1 fields, HMAC bytes/vector, defaults, visible APNs payload,
  delivery/dedupe/rate responses, and idempotent deletion remain supported.
  Unapproved extra fields (previously ignored) now return `400 Invalid fields`,
  and oversized/stalled bodies or duplicate decoded object keys return the
  existing `400 Invalid JSON body`. Escaped key aliases and identical repeated
  values are duplicates too; a later field cannot hide an earlier unapproved
  value. This validation hardening prevents mixed transport fields or health arguments
  from being silently accepted. Provider/D1 exceptions are contained without
  raw exception logging. APNs JWT signing is request-local, not globally cached.

## V2 HTTP contract

All requests are JSON objects with **exactly the approved fields**. There are no
labels, health fields, operation arguments, metric IDs, calendar dates, URLs,
provider payloads, topics, conditions, or arbitrary notification copy. Responses
are JSON with `Cache-Control: no-store`; errors contain fixed codes only.
Request objects must have unique decoded field names. Duplicate rejection occurs
before authentication, D1 access or provider dispatch, without reflecting the
request or logging it. Ordinary v1/v2 fields and proof transcripts are unchanged.

### POST `/wake/v2/register`

Required fields:

| Field | Meaning |
| --- | --- |
| `operation` | `enroll` or `rotate` |
| `wakeId` | Fresh phone-generated 128-bit random ID, encoded as 32 lowercase hex characters; never reuse a revoked ID |
| `userId` | Opaque install metadata, existing `[A-Za-z0-9_-]{16,64}` grammar; not an authenticator |
| `transport` | Literal `fcm` |
| `deliveryToken` | Opaque FCM registration token; private delivery state, never a URL |
| `wakeKeyVerificationHash` | Lowercase hex SHA-256 of a fresh independent 32-byte wake secret |
| `managementKeyVerificationHash` | Lowercase hex SHA-256 of a second fresh independent phone-only 32-byte secret; must differ from the wake hash |
| `nonce` | Fresh lowercase hex, 32–128 characters, even length |
| `timestamp` | Canonical UTC seconds, `YYYY-MM-DDTHH:mm:ssZ` |
| `proof` | Lowercase hex HMAC-SHA256, 64 characters |

The management transcript is UTF-8 bytes of this compact JSON array, in this
exact order (no whitespace between tokens):

```text
["healthmd.wake.manage.v2",operation,wakeId,userId,transport,deliveryToken,
 wakeKeyVerificationHash,managementKeyVerificationHash,nonce,timestamp]
```

The line wrap above is explanatory, not part of the bytes. For `enroll`, the
HMAC key is the proposed management hash decoded to 32 bytes. For `rotate`, it
is the **currently stored** management hash, not the proposed replacement.
All changed delivery/key fields are bound by the proof. Rotation also rejects
reusing the current wake hash as management material or vice versa. Success is
`200 {"wakeId":...}`. Existing/revoked IDs cannot be enrolled again (`409
wake_exists`). Rotation preserves delivery policy and replay history, rejects
old proofs after management-key replacement, and requires a fresh nonce.

Initial enrollment is proof of possession of caller-selected material, **not
app attestation, account authentication, or proof of token ownership**. A caller
who knows a recipient token can create another resource. Limits are per wake
ID, not per account/token/IP. Registration abuse/ownership controls therefore
remain a production security review gate; this slice makes no stronger claim
than the existing bootstrap trust contract.

### DELETE `/wake/v2/register`

Required fields: `wakeId`, `userId`, `nonce`, `timestamp`, `proof`.

```text
["healthmd.wake.manage.v2","revoke",wakeId,userId,nonce,timestamp]
```

Key: current phone-only management hash. A CLI holding only the wake hash
cannot revoke or rotate. Authenticated revocation atomically removes private
registration, counters, and replay rows and retains only an opaque ID/time
revocation tombstone, preventing enrollment replay from resurrecting the row.
Success is `200 {"ok":true}`; unknown/already revoked resources return `404
wake_unknown`, not v1's unauthenticated idempotent success. Tombstones are not
pruned automatically; any future deletion policy must preserve non-resurrection.
An already accepted/in-flight provider push cannot be recalled by revocation.

### POST `/wake/v2/request`

Required fields: `wakeId`, `nonce`, `timestamp`, `hmac`.

```text
["healthmd.wake.request.v2",wakeId,nonce,timestamp]
```

Key: registered wake hash decoded to bytes. This is deliberately distinct from
both management proofs and the unchanged ASCII-concatenated v1 transcript.
`peerLabel` is not accepted. Generic copy is the deliberate fallback because
v2 has no reviewed authenticated display-name channel; no per-request label or
fallback log is emitted.

- Unknown/wrong-version ID: `404 wake_unknown`.
- Wrong HMAC/proof: `401 wake_hmac_invalid` / `wake_proof_invalid`.
- Timestamp outside ±120 seconds: `401 wake_timestamp_stale`.
- A nonce consumed by either v2 domain for this ID: `401 wake_nonce_replayed`.
- Replay nonces retain server `seen_at` times for 300 seconds and are pruned for
  the same wake ID when it is used again. Idle rows may remain until next use or
  revocation; this is not a scheduled TTL deletion guarantee.
- Dedupe: `200 {"status":"deduplicated"}` within 30 seconds of known provider
  acceptance. At most six known acceptances per UTC hour bucket per wake ID:
  `429 wake_rate_limited` with `retryAfterSeconds` beyond that limit.
- D1 transactions burn the nonce and conditionally acquire a 30-second delivery
  lease. A distinct request during a pending lease gets `429 wake_in_flight`
  with `retryAfterSeconds`, not a false delivered/deduplicated receipt. A crashed
  lease expires. Only known provider acceptances consume the delivery budget.
- Missing/malformed credentials: `503 fcm_not_configured` /
  `fcm_config_invalid`, no provider contact. Other provider/network/timeout/body
  failures: `200 {"status":"undeliverable"}`. A consumed nonce is never retried.
- Success: `200 {"status":"delivered"}` means **provider acceptance only**,
  not display, tap, unlock, execution, or data authorization. Timeouts can have
  uncertain provider outcomes; this is not an exactly-once delivery guarantee.
- A concurrent credential change can return `409 wake_auth_changed`. After
  signing, OAuth and notification-body preparation, a required non-wire callback
  re-reads the original wake key/token/version and exact lease owner, then checks
  trusted live time and the original timestamp window immediately before starting
  the FCM request. Revocation, wake-key/token replacement, lost/expired lease or a
  now-invalid timestamp reject with that same code without newly dispatching the
  notification. They do not renew/replan the consumed nonce or lease. Cleanup is
  conditional on this invocation's nonce and cannot clear another active lease.
  Storage failures return fixed `503 wake_storage_unavailable`, without bound values.
  OAuth contact may already have happened; this is not a zero-provider-I/O claim.
- The check is not a global transaction across D1, wall time and HTTP dispatch.
  A mutation after the observed read or a provider push already started/accepted
  may race and cannot be recalled. Provider acceptance remains the only meaning
  of `delivered`; no exactly-once, display, lifecycle or permission claim is added.

Independent synthetic vectors are pinned in tests. For raw wake secret `[7;32]`,
management secret `[9;32]`, ID `12` repeated 16 times, install
`synthetic_install_001`, token `synthetic-fcm-token`, timestamp
`2026-10-04T12:00:00Z`, enrollment nonce `ab` repeated 16 times:
management proof =
`55b5da42049b31347200bcb2e0dd6b2b1c7513bc411d7b44d9b0651e4504c3fc`.
The request nonce `cd` repeated 16 times gives v2 HMAC =
`01f561ffd63763181697f2186419f2487e48e9b0947f5b2986812e1b866f9819`.
These are Worker-local extension vectors, not adopted direct-channel fixtures.

## Private configuration and fixed provider authority

Optional secret binding: **`FCM_SERVICE_ACCOUNT_JSON`**. No config, resource ID,
environment, compatibility date, account, or credential is changed by this
slice. Provisioning/deployment requires separate explicit authorization.

The secret must describe a service account with `type`, `project_id`,
`client_email`, and a PKCS8 RSA `private_key`. Optional `private_key_id` becomes
JWT `kid`; optional `token_uri` must equal `https://oauth2.googleapis.com/token`.
Project IDs are constrained to lowercase `[a-z][a-z0-9-]{4,28}[a-z0-9]`; the
service-account email must belong to that project's `iam.gserviceaccount.com`
domain. Cross-project service-account credentials are intentionally not
supported by this extension. Other credential metadata cannot provide HTTP
or delegation authority.

WebCrypto signs an RS256 assertion with `iss`, `iat`, `exp=iat+3600`, the fixed
OAuth audience, and only `https://www.googleapis.com/auth/firebase.messaging`.
A request-local access token is exchanged using the JWT-bearer grant. There is
no module-level OAuth token/key/registration cache, refresh loop, retry, remote
credential discovery, user impersonation, or extra runtime dependency.

Delivery goes only to
`https://fcm.googleapis.com/v1/projects/{validated_project_id}/messages:send`.
Provider fetches use `redirect: manual`; every 3xx is rejected, so neither a
JWT assertion nor an authorization header follows a redirect. The deployed
compatibility profile rejects `redirect: error`; the local workerd test pins
this working behavior without changing the profile.

Local implementation budgets (not Firebase/Android platform quotas): request
and parsed provider JSON ≤16 KiB; each request-body read/provider fetch+body
≤5 seconds; private config ≤16 KiB; PEM ≤8192 characters; RSA modulus 2048–4096
bits; delivery/OAuth tokens ≤4096 ASCII characters. Request/provider streams
are cancelled on overflow/deadline; error bodies are discarded without parsing.
Parsed request/provider JSON rejects duplicate decoded keys in every object,
including objects nested in arrays. Key comparison follows decoded JSON strings,
without case folding or Unicode normalization. Repeated keys in separate sibling
objects and punctuation/escapes inside string values remain valid. An ambiguous
OAuth response prevents FCM dispatch; an ambiguous FCM acknowledgement cannot
count as known acceptance. A valid authenticated request has already consumed
its nonce before provider parsing, even when that parsing later fails; it cannot
retry that nonce. This is not a claim that a provider notification can be recalled.
Private service-account configuration parsing is outside this bounded I/O change.
APNs success/error bodies are discarded, and APNs uses the same bounded
provider timeout. No provider response, token, hash, raw key, identity, request
body, or error text is logged or included in public receipts.

The FCM body is a fixed visible `notification` (no `data`): title `Health.md`,
body `A paired computer is requesting data. Tap to continue.`, Android priority
`HIGH`, TTL `300s`, package `com.healthmd.android`, channel
`healthmd_direct_wake`, click action `com.healthmd.DIRECT_CLI_WAKE`, private
lock-screen visibility, fixed tag and default sound. There is no image URL,
analytics label, direct-boot override, full-screen intent, or service directive.
Native integration must create the channel/action and validate foreground
notification handling before this payload can be qualified.

## Official sources reviewed 2026-10-04

- [Workers best practices](https://developers.cloudflare.com/workers/best-practices/workers-best-practices/):
  request-local state, bounded streaming, awaited work, bindings, secrets.
- [WebCrypto](https://developers.cloudflare.com/workers/runtime-apis/web-crypto/),
  [Request](https://developers.cloudflare.com/workers/runtime-apis/request/),
  [Fetch](https://developers.cloudflare.com/workers/runtime-apis/fetch/):
  RSA/HMAC APIs and redirect/header safety. Published request docs list `error`,
  but local workerd under the unchanged profile rejects it; `manual` is tested.
- [D1 batch](https://developers.cloudflare.com/d1/worker-api/d1-database/),
  [D1 SQL](https://developers.cloudflare.com/d1/sql-api/sql-statements/):
  sequential transactional batches, SQLite semantics. Local D1 testing caught
  metadata changes including cascaded deletes, unlike SQLite `changes()`.
- Latest published `@cloudflare/workers-types` retrieved as `5.20261004.1` and
  used for an additional type-check; locked build types remain `5.20260903.1`.
- [Firebase HTTP-v1 send/authorization](https://firebase.google.com/docs/cloud-messaging/send/v1-api),
  [Google service-account OAuth](https://developers.google.com/identity/protocols/oauth2/service-account):
  fixed JWT grant, RS256, scope, token endpoint, maximum one-hour assertion.
- [FCM REST payload](https://firebase.google.com/docs/reference/fcm/rest/v1/projects.messages):
  notification/Android fields, TTL, priority, channel, click action. Current docs
  mark `token` deprecated in favor of `fid` while explicitly accepting registration
  tokens during transition; this slice deliberately uses the requested explicit
  registration-token field, not a silent FID reinterpretation. Recheck at rollout.
- [Android FCM receive](https://firebase.google.com/docs/cloud-messaging/android/receive-messages),
  [Android FCM priority](https://firebase.google.com/docs/cloud-messaging/android-message-priority),
  [Android FCM setup](https://firebase.google.com/docs/cloud-messaging/android/get-started):
  background notification messages go to the tray; foreground messages reach
  `onMessageReceived`; high priority is an attempt, can be downgraded/delegated,
  and does not guarantee display. Check compatible Play services and opt-in
  initialization; a denied notification permission is not a hidden wake path.
- [Android notification permission](https://developer.android.com/develop/ui/compose/notifications/notification-permission),
  [normal notification creation](https://developer.android.com/develop/ui/compose/notifications/create-notification):
  Android 13+ runtime permission, channels, ordinary user-tap activity opening.
  Full-screen intents are not used for this feature.
- [Foreground-service background restrictions](https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start):
  restrictions/exceptions are not authorization for hidden data-sync starts.
  Only an ordinary user tap may open the app and resume existing consent rules.
- [Android stopped state](https://developer.android.com/about/versions/15/behavior-changes-all#stopped-state):
  force-stop persists until user action; Android 15 cancels pending intents.
  Do not promise push delivery, an always-present notification, or a lifecycle
  bypass for a force-stopped app. Manual opening/P1 waiting remains the path.

No numeric delivery latency, display reliability, background execution budget,
or provider quota is inferred from these sources.

2026-10-05 bounded validation follow-up: Workers best-practices and Streams
references were retrieved again; installed types remain `5.20260903.1`, with an
additional scratch-only `5.20261005.1` type check. Synthetic HTTP and the existing
ephemeral local workerd/D1 test cover duplicate enrollment/ring/provider rejection
and valid legacy/v2 behavior. This is Worker-source qualification only, not native
FCM enrollment, device notification, deployment or complete B15 qualification.

2026-10-05 bounded send-admission follow-up: synthetic public HTTP requests cover
successful revocation/rotation during OAuth, exact lease expiry and competing
lease ownership, live timestamp failure, contained admission-read failure,
separate management-key rotation and already-started provider acceptance. The
existing ephemeral local workerd/D1 test also exercises actual Worker revocation
and token rotation while awaiting mocked OAuth. These are exercised local source
boundaries, not native FCM delivery or atomic send qualification. The unchanged
D1 access uses no Sessions API; [D1 read-replication documentation](https://developers.cloudflare.com/d1/best-practices/read-replication/)
states that queries without it go to the primary database. New replica/session
adoption must separately preserve current-authority reads. Current best-practices
and D1 references were retrieved; `5.20261005.1` remains a scratch-only type check,
not a lockfile/configuration/compatibility-profile change.

## Later gates (not performed here)

1. Coordinate RFC/contract adoption and reviewed cross-language v2 transcripts,
   HTTP endpoint/version negotiation, enrollment control messages and fixtures.
   Pairing selectors, frame bytes, export schemas, and unrelated contracts stay
   frozen. B15 and the separate existing P2 production-enable/import task remain
   with their current owners.
2. Play-only native opt-in, compatible Play services/notification permission,
   independently generated phone management secret, protected trust storage,
   authenticated enrollment handoff, token/key rotation and unpair revocation.
   The CLI receives only wake material, never management or provider secrets.
3. Normal visible notification/channel/foreground handler and tap routing,
   consent-preserving direct-session start, truthful P1-only degradation for
   F-Droid, missing services, denied permission, first-unlock/force-stop cases.
   No silent capture, full-screen intent, hidden FGS start, or unlock bypass.
4. Rust fallback/versioned endpoint signing tests, Kotlin trust/enrollment/tap/
   revocation tests, Play/F-Droid builds, capability ledger/docs consumer gates.
5. Security/privacy/registration-abuse and retention review; isolated credential
   authorization, remote migration-state review, committed/pushed source and
   separately authorized deployment. Review inherited development dependency
   audit warnings. No deployments or secret/account calls were made here.
6. Owner-approved Pixel LAN/Tailscale matrix: active service while locked,
   inactive app, process loss, before-first-unlock, denied permission, unavailable
   services, F-Droid, force-stop, key/token rotation, revocation, and waiting CLI
   cancellation/expiry. Provider acceptance is not physical notification QA.
