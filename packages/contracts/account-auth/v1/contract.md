# Account-auth v1 — disabled source interface

**Proposed / synthetic-only / not manifest-registered.** This directory is an AS01 design and test surface, not runtime authentication, an OAuth/OIDC deployment, a production registration or owner approval. The [architecture and approval ledger](../../../../docs/architecture/account-profile-sync-source-design.md) distinguishes source proposals from baseline evidence and unresolved gates. No existing contract bytes change.

## Source seam / dependencies

AS02 may implement an account-authority module behind an unavailable-by-default interface. Its callers supply a trusted registration, clock, entropy, transactional state adapter, and browser-identity adapter. The synthetic adapter may hold only deterministic in-memory sentinels. No production adapter is provided here. Identity comes only from the existing account login module; do not import a website/provider broker or accept native passwords/cookies.

Suggested interface outcomes (source proposal):

- `beginAuthorization(validatedQuery)` -> bounded pending transaction, no session;
- `decide(pendingId, browserIdentity, csrfProof, explicitDecision)` -> verified one-time callback or fixed local error;
- `exchange(closedCodeRequest)` / `refresh(closedRefreshRequest)` -> verified native config session or fixed error;
- `authorizeConfig(accessProof, exactRoute)` -> configuration principal, never health authority;
- `listSessions(authenticatedPrincipal)` / `revokeSession(authenticatedProof, target)` -> redacted owner-bound metadata or verified revocation.

Transactional store operations must enforce compare-and-set claims, exact tuple/account checks, audit atomicity and durable readback; change counts or transport success are not proof. Real AS02 integration must test through this interface with lost responses, races and unreadable postconditions. This directory's Python test oracle is not that adapter.

## Registration and activation

[source-policy.json](source-policy.json) contains only an injected synthetic environment/issuer/audience and exact `.example` client callbacks. Callback bases include no query/fragment. Each public client has exactly one callback in this registry. No wildcard, prefix, case-folded, normalized URL, dynamic endpoint, custom scheme, loopback or provider-discovered trust is accepted. For real registration, approving multiple callbacks would require each exact tuple to be listed and reviewed.

Proposed independent settings:

| Setting | Default / interface |
|---|---|
| `ACCOUNT_NATIVE_AUTH_ENABLED` | absent or `0`: deny all new auth routes; no native credential issuance |
| `ACCOUNT_PROFILE_SYNC_ENABLED` | absent or `0`: deny profile reads/writes independently of sign-in |
| `ACCOUNT_AUTH_ENVIRONMENT` | explicit `synthetic`, `development`, `staging`, or `production`; no fallback to legacy `ENVIRONMENT` |
| `ACCOUNT_AUTH_REGISTRATION_JSON` | explicit reviewed issuer/config audience/client callback tuples; absent/invalid/wrong environment denies |
| `CONFIGURATION_PRIVACY_POLICY_VERSION` | absent: no persistent real profile store/transfer; full reviewed policy is required, not just a version marker |

Synthetic tests inject policy and registration directly, never set live environment variables. Development/staging/production registrations are null. Runtime activation requires a separate owner-authorized rollout record and applicable named-role evidence outside untrusted requests/config claims. Existing `CLOUD_RUNTIME_APPROVED`, password pilot acknowledgement and repair flags cannot enable this design. Keep production, staging, development and synthetic stores/credentials/clients disjoint; do not repoint pilot hostnames or migrate identities implicitly.

## Exact route reservations

The source policy positively enumerates these routes. They are **not installed** by AS01. Future allowlist additions must be explicit in every relevant account adapter and its negative tests; never widen the ingest/MCP/router defaults.

| Method / path | Auth / request | Result and independent gate |
|---|---|---|
| `GET /account/authorize` | Validated non-secret authorization query; browser identity established separately | First-party consent page/pending transaction; auth enabled + registered client. No native secret returned. |
| `POST /api/account-auth/v1/decision` | Existing cookie, exact same Origin, CSRF proof, `{authorization_id, decision}` where decision is `approve` or `deny` | Bound consent/code callback; explicit scope review, no cookie returned to native |
| `POST /api/account-auth/v1/token` | Closed JSON code or refresh request; no Cookie, client secret, Basic auth or unrelated bearer | Only config-scoped access/refresh; auth enabled |
| `GET /api/account-auth/v1/sessions` | Browser cookie + same Origin, or native config access + `account:sessions:read` | At most 20 redacted native families; browser owns account list, native sees only current family |
| `POST /api/account-auth/v1/revoke` | Browser cookie + same Origin/CSRF/recent reauth with `{session_id}`; or native access + self-revoke scope with `{}`; or native refresh proof in closed JSON with `{refresh_token, client_id, installation_id}` | Only verified revocation; browser target owner-bound, native/refresh target implicitly self. Refresh proof is not general bearer authorization. |
| `POST /api/profile-sync/v1/read` | Native access + `config:profiles:read`, or opted-in browser cookie + same Origin/CSRF | Bounded profile reads only; sync enabled + opt-in + reviewed privacy adapter |
| `POST /api/profile-sync/v1/mutate` | Native access + `config:profiles:read` and `config:profiles:write`, or opted-in browser cookie + same Origin/CSRF | Config mutation only; same independent gates. AS05 owns body/revision grammar. |

No account/profile/native ID is an authority-bearing URL selector in these new routes. Non-authorization routes reject every query/fragment and unknown method/path, including encoded path aliases or trailing slash. `GET /account/authorize` is the only narrowly scoped query exception: implementation must update `requestMatchesPublicEndpoint`/core query checks only for this exact route, not weaken their global rules. Existing password/email auth, account, repair, upload and MCP paths retain their current query rules. Positive service profile is isolated account authority; a combined in-memory **test** adapter is permitted only by explicit synthetic injection, never as a production listener fallback.

All new responses, including errors and redirect, are no-store, no-referrer and non-reflecting. Consent page has first-party assets, strict CSP, no third-party network and no persistent browser storage. No wildcard CORS/credentialed cross-origin browser reads. New native bearer/resource/token routes reject mixed cookie/bearer input; browser routes reject unrelated Authorization input. Errors do not echo email, IDs, code, verifier or profile text. New authority never falls back to existing browser/ingest/read/device token parsers.

## Authorization query and browser decision

Exactly one of each required key is allowed:

`client_id`, `redirect_uri`, `response_type=code`, `scope`, `state`, `code_challenge`, `code_challenge_method=S256`, `audience`.

The callback tuple and audience must equal trusted registration before any redirect or persisted authorization request. Duplicate/unknown/percent-encoded key aliases, invalid encoding, controls, fragments, oversized URI/query and unsupported values deny. `scope` is a canonical ASCII-space-separated lexicographically sorted unique subset of the four source scopes; write without read denies. State and challenge are unpadded base64url representations of 32 random bytes (43 characters). Only S256 PKCE; verifier is 43–128 RFC 7636 unreserved ASCII characters, freshly generated per attempt. SHA-256 base64url(verifier) must match the bound challenge. Native scopes are restricted regardless of requested arbitrary OAuth-looking names; there is no `openid`, identity token or health scope here.

Pending authorization ID is an opaque random public reference with **no standalone authority**; it never bypasses session+CSRF+consent. Pending tuple additionally binds browser account/session at decision time, installation from the later exchange binding, timestamps, and fixed consent-policy version. Before decision, validate current browser account against the account shown in the review; a switch requires a new consent transaction. `deny` consumes pending transaction, produces no grant and returns only the validated callback with fixed `access_denied`, matching state/issuer. An unregistered callback receives only a local fixed error, not that redirect.

Bound source-test caps: authorization query/callback URI 4 KiB; JSON auth body 8 KiB; pending authorization five minutes; code 120 seconds; one outstanding native attempt per installation; at most five pending account/client transactions and 20 active native families per account. Admission caps/rate decisions must be atomic; reject before credential issuance. Suggested purpose-HMAC IP/client/account hourly limits are 20 authorization starts per IP/client, five decisions per account/client and 30 token attempts per installation; numeric production choices and abuse qualification remain security/product gates. Raw IP and identifiers are not logged.

The initial GET cannot receive installation identity as an extra URL selector. The native pending attempt holds a random installation ID; exchange supplies it, and first consumption binds the new family to that ID. A code is already bound to client/callback/challenge/account, so changing an installation label cannot overcome PKCE. A production design wanting stronger pre-exchange installation binding must add a reviewed non-URL start-request seam, not pretend this label is hardware identity.

## Callback receiver / token requests

Synthetic success callback is exactly `<registered-base>?code=<code>&state=<state>&iss=<issuer>` (query ordering need not be fixed). Fixed error callback has exactly `error=access_denied`, `state`, `iss`, no code. Raw base equality precedes parsing; parse one time, reject duplicates/unknown fields, percent-encoded parameter names, `%` escapes/control characters in values, fragment/userinfo/port/host/path substitution, and size overflow. Source issuer bases contain only URL-safe characters. Receiver requires exact matching state/issuer and a still-pending same-client/environment/account-generation attempt. A callback on `healthmd://cloud/requests`, or access/refresh/session/token selectors on any callback, always denies. Clear attempt after accepted callback, deny replay/cancelled/unsolicited callback, and do not read health or apply settings on callback.

Native uses closed UTF-8 JSON (first-party interface, not advertised standards-compatible token endpoint):

```json
{"grant_type":"authorization_code","client_id":"<registered>","redirect_uri":"<exact-base>","code":"<one-time-code>","code_verifier":"<private-verifier>","installation_id":"<local-random-id>"}
```

```json
{"grant_type":"refresh_token","client_id":"<registered>","installation_id":"<same-id>","refresh_token":"<rotation-proof>"}
```

Reject unknown/missing/mistyped members, Boolean/null IDs, duplicated JSON keys, non-UTF-8, controls, size/depth overflow, token in URL, cookie or foreign bearer, unapproved issuer/env/client/audience and invalid verifier before attempting consumption. Server has no client-supplied account/scope/audience override at this endpoint; grants use only trusted pending/family records.

Proposed opaque random 32-byte token types have disjoint prefixes `hmd_acode_`, `hmd_nac_`, `hmd_nrf_` followed by 43 base64url characters. Codes have no resource authority; access cannot refresh; refresh cannot read/mutate config. Only short-lived code may traverse auth callback. Access/refresh appear only in TLS JSON success/secure native storage or a native bearer header as appropriate, never exported setup, URLs, telemetry, crash logs or browser storage. Server stores purpose-separated digests, never plaintext secret recovery material. No JWT/ID-token format, signing algorithm, external issuer or production key strategy is selected here.

Locally reviewed AS02 synthetic success shape: `{token_type:"Bearer", access_token, expires_in:300, refresh_token, session_id, scope, issuer, environment, audience, client_id, installation_id, account_id, session_generation}`. The closed member set is pinned in [source-policy.json](source-policy.json). This is still a source interface, not a real browser/native registration or qualified secure-storage adapter.

`account_id` is the stable, non-secret opaque account key resolved from authoritative account/grant records. Account namespace is exactly `(issuer, environment, account_id)`; it remains stable across new families and refresh for the same account. An email, session/family ID, profile ID, native ID, name or caller selector cannot supply it. The subject is a partition reference, never independent authority. `client_id` and `installation_id` must match the captured exchange/refresh tuple; `session_generation` is a positive safe integer identifying the server grant generation, **not** the native monotonically changing account-switch generation. Audience/client/installation/session bindings scope the credential, not account identity.

Before secure-store commit, the native adapter must strictly parse the bounded duplicate-safe JSON response, verify the exact registered issuer/environment/audience, requested or reduced canonical scopes, captured client/installation/current attempt, opaque account key, valid token kinds and positive server generation, and recheck its local account-generation fence. The AS02 typed in-memory `NativeAttempt` does not itself qualify this wire parser, OS presentation, transport, secure storage or process lifecycle. A refresh must preserve the verified account namespace; account replacement requires a fresh reviewed sign-in. Sign-in selects/transfers no profiles and sets no sync opt-in. Session ID is not a token; redacted inventory exposes only session ID/client/platform/created/expiry/revoked/current, no raw install ID/name/health/email/last-four refresh material.

## Rotation, revocation and ambiguous results

Refresh family has provisional five-minute access, 30-day absolute / seven-day idle lifetime, never reset past absolute expiry. Rotation atomically consumes parent and produces exactly one child/access pair with unchanged or reduced scopes, plus a durable audit marker. Scope expansion needs fresh consent. Reuse of any retained spent refresh digest revokes the family and all access tokens, including the winning concurrent refresh. Native serializes calls; this strict/no-grace trade-off is a proposal needing review.

Expiration equality is expired. Verify account active, session/family active, exact issuer/environment/audience/client/installation and scope for every request. Revocation/account disable invalidates already-issued access immediately through authoritative lookup, not merely short TTL. Target ownership is checked in transactional mutations; wrong account never returns another account's details. Refresh revoke-only recognition of spent digests cannot mint or read anything.

Return issuance/rotation success only after exact durable tuple/audit readback. If commit proof is unreadable return `503 verification_pending`, no secret. If a replacement was committed but its response is lost, the client must reauthenticate; retrying a consumed code/refresh cannot reconstruct credentials or create another family. Revocation success needs durable revocation+audit proof; unreadable state is pending, not success. Account deletion wins all races. Native generation fences reject late callbacks/token/refresh/apply responses after sign-out or account/env switch even if the server committed.

Local sign-out and remote revocation are distinct. Offline UI reports local signed-out / remote pending. Any retained encrypted revocation-only proof must be invisible to refresh/config callers and cleared after verified acknowledgement/expiry under reviewed retention. No independent ingest/device/MCP/provider/direct grant is silently revoked or converted.

## Configuration field/activation seam

[field-scope.json](field-scope.json) imports **reviewed dispositions only** from byte-pinned Shared Setup v2 ledgers and uses its closed typed sections, bounds, recursive prohibited-content scan and exact metric registry evidence. It does not embed a v2 bundle or claim native snapshot containers are safe. AS05 specifies its independent wrapper; artifact `bundle_id`, `active_profile`, native IDs/credentials/grants/engine/runtime state and app-global preferences are excluded. Preserve foreign typed extensions, including unsupported semantics, without applying them. Apple's baseline extension loader returns an empty map when sidecar state cannot be read; that result is not proof of foreign-field absence. A sync writer must verify mapping/sidecar provenance or quarantine publication, never publish foreign deletions from a failed load. Unsupported optional future content requires AS05 compatibility rules; never persist unknown input opaquely.

Profile-sync endpoints are reserved auth seams, not an implemented sync grammar. Real persistence/transfer requires an independently approved configuration privacy policy, opt-in and selected profiles. Missing policy fails closed. Sign-in alone transfers nothing. AS05/AS10 must prove publish/adopt/keep-both identity mapping, offline conflicts/deletions, last-native-profile invariant and local immutable-revision review. Adoption/new intent is unbound/blocked with disabled schedules; updating a remotely selected revision never activates or retargets running work. Fetched content remains separate from accepted local execution snapshots. Clearing an identity-only import bit does not approve the next revision; local approval binds exact immutable revision/hash plus destination/credential scope. Unchanged accepted local snapshots may continue under their existing qualified authority while new remote content stays pending. Active profile, local destinations, permissions, credentials, purchases and health are unchanged by sync.

## Tests and non-claims

Run from repository root:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 packages/contracts/account-auth/v1/test_source_contract.py
python3 packages/contracts/validate.py
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s packages/contracts -p test_validate_shared_setup.py
```

[security-vectors.json](fixtures/security-vectors.json) contains callback templates and abstract principal/lifecycle sentinels. The standalone standard-library tests exercise design predicates and symbolic transitions only; no credentials, network, deployed handler, OS callback registration, cryptographic custody or transactional database adapter are involved. Downstream TypeScript/Swift/Kotlin tests must consume the same scenarios and add parser/cryptographic/race/fault/physical evidence before claiming implementation or review completion. The new directory is intentionally absent from CI/manifest registration until an authorized follow-up updates ownership explicitly.

Named owner/product/security/privacy/operations/mobile approvals, actual issuer/callback/linking/recovery decisions, real config encryption/retention/deletion policy, mobile qualification and any pilot/production activation remain blocked. P2 request/upload/receipt and AS18 chart presentation decisions are outside this contract.
