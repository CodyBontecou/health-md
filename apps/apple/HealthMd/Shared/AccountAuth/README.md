# Disabled Apple account-auth source seam

Foundation/CryptoKit only; no app factory, UI, OS callback registration, browser, Keychain,
URLSession, health/profile/provider/purchase/root integration. Real registrations and consent
remain unavailable. This is not working sign-in or a qualified secure-store/transport adapter.

## Construction and authority

- `AccountAuthCoordinator()` is unavailable. Every operation is inert; even status/cleanup
  reads no port. Explicit `syntheticForSourceTests` injection requires both a pinned Apple
  client (iOS, iPadOS or macOS) and a synthetic metadata-consent marker. Missing either remains
  unavailable. The marker is **not** browser consent/identity proof.
- `AccountAuthRegistration` has private construction and only the five reviewed reserved-domain
  tuples. The raw decoder studies all five; the Apple coordinator selects only three Apple clients.
  No token/callback/endpoint/environment claim supplies trust. No real-environment registration exists.
- A decoded session is not authority. The coordinator checks the operation, captured tuple and
  local generation, then exact authoritative vault readback, then generation again at visibility.
  Source transport receipts are fake-only; no JSON Boolean or echoed endpoint qualifies real TLS.
- Status contains only a namespace/status/fence event and coarse in-flight counts. There is no
  credential, configuration, health or profile-selection getter. Profile sync always stays false.

## Closed source grammar

Raw UTF-8 token JSON is capped at 8192 bytes, checked for a raw BOM, decoded duplicate keys,
exact thirteen members and scalar types before constructing an immutable redacted DTO.
Canonical unsigned decimal safe integers exclude Boolean, fractions, exponents, negative zero
and overflow. Access/refresh/code kinds are disjoint canonical 32-byte base64url references.
Scopes are exact captured/unchanged canonical scopes, not reduced-grant negotiation.
Account namespace is issuer/environment/server-owned opaque account ID, not family/install/name.
Initial server generation is zero; refresh preserves all bindings and requires the next safe
server generation and new tokens. The local monotonic fence is separate.

Raw callbacks are `Data`, at most 4096 bytes, with literal registered base and only code/state/iss
or access_denied/state/iss. No normalized URL input, aliases, percent escapes, duplicate fields,
fragments, controls or authority/path substitutions. One attempt is consumed before suspension;
cancel, timeout, switch and signout invalidate it. Installation identity is process-owner-local
and stays stable across signout/re-auth; state/verifier are freshly generated for each attempt.
Entropy failure never falls back. SHA-256 is actual CryptoKit S256.

Synthetic reply headers retain immutable copied ordered String pairs, never map-first input.
Inactive reply-header source profile v1 bounds sixteen pairs, ASCII names1–64 bytes, printable
ASCII values0–1024 bytes and4096 aggregate name+value bytes. Identical/folded duplicates and
Cookie/Set-Cookie/Authorization/Proxy-Authorization reject before lookup insertion. Required
JSON (or exact UTF8 JSON), no-store and no-referrer values stay exact; safe unique extras are
inert and retain original order/case/value bytes. These decoded DTO bounds do not bound a real
HTTP stream or prove TLS/provenance. Receipts, header descriptions and errors remain nonreflecting.

## Custody, concurrency and ambiguity

`AccountAuthVault` requires a synchronous linearizable commit **under the commit fence** and fresh
complete readback. Holding a permit over staging then releasing it before a later durable write
violates the interface. `AccountAuthSyntheticVault` implements that exact memory commit seam.
NSLock protects only the process fence and the synchronous commit section; coordinator/refresh
ownership is an actor. Concurrent refresh callers coalesce across load/request/validation/commit.
Held access leases use a conservative **request-start** bound, never response arrival. Fresh source
clock checks reject rollback, timeout equality and TTL exhaustion at reply, actual custody commit,
readback and final visibility. Clock/elapsed-time/real-network guarantees are still adapter gates.
Lost code/refresh responses never cause proof replay or parent restoration.

Signout fences visibility immediately. Current normal erasure and durable-fence verification
are separate from pending/unknown/confirmed self-revoke obligations. A prior prepare-clear proof
is superseded before a possible new custody write. Expiry, clock failure or unreadable custody
never erase revoke knowledge just because access visibility disappeared. Minimum synthetic
self-revoke material (proof plus correlation bindings) stays private in a separate process-memory
compartment, inaccessible to normal refresh/config state. Only a current correlated exact
`{"revoked":true}` acknowledgement confirms a queued obligation; 2xx alone does not. Multiple
in-process re-authentications preserve queued obligations (bounded to twenty).

There is **no restoration API**. Fresh preparation clears stale normal custody only after an
explicit operation and verified postcondition; observing a stale populated row records an
unknown remote obligation without adopting its account or proof. Unreadable prior custody is
also unknown, not proof of absence. Nil-row custody with an install receipt is likewise unknown;
only coherent bootstrap/prepare/erase absence avoids inventing an obligation. Process recreation loses unsecured attempts and in-memory
revocation material and requires fresh authentication. A stale row alone cannot prove earlier
signout intent if the durable fence failed. The recreated hint can conservatively report unknown,
but is not durable evidence. No encrypted retention/deletion/backup policy is implemented here.

## Host verification, not native qualification

Invoke `apps/apple/scripts/test-account-auth-source.sh` **via bash under the unchanged fleet
heavy-slot guard**, using a new AS03 evidence directory each time. It preserves artifacts and
compiles the actual selected source/tests: Swift 6 complete strict concurrency, then Swift 5
MainActor/approachable settings comparable to the project. It also typechecks the conditional
XCTest imports against a selected-source testable module, not the full app. The optional second
runner argument supplies ONLY the read-only reply-header fixture root; original native/security
fixtures remain in the own source tree. Conditional imports require explicit already-installed
`ACCOUNT_AUTH_SELECTED_SDK`, `ACCOUNT_AUTH_DEVELOPER_FRAMEWORKS` and
`ACCOUNT_AUTH_DEVELOPER_USR_LIB` paths obtained by the admitted guarded metadata check. The
runner never searches/installs/stubs/skips XCTest. Source and fixture hashes are checked before/after.

The literal99 header fixture contributes86 representable String-pair rows (9positive/77negative)
per exchange/refresh/revoke. Its thirteen malformed shape/type rows cannot construct this typed
DTO and remain explicitly unrepresentable/unexecuted, not native rejection passes. No untyped
network interface or reference-parser verdict is supplied to inflate coverage.

The harness consumes the shared 73 response / 15 error / 3 PKCE / 32 callback corpus and executes
actual coordinator/memory-vault faults and deterministic actor races for all 22 lifecycle seams.
Temporal checks add TTL1 replies delayed by two/four seconds, deferred commits/readbacks,
rollback/deadline/visibility expiration and non-rebased still-valid leases on exchange and refresh.
These checks are verification surfaces, not claims of execution at a particular revision; consult
that revision's external lane report/retained receipts. No parallel symbolic success oracle or peer parser is used. Independent-state sentinels and the
absence of health/profile ports prove only this library boundary, not whole-app cold/foreground
zero HealthKit calls. Existing separately authorized local work is unchanged.

Still gated: real consent/browser/account authority, issuer/client/domain approvals, OS custody
and durable-fence attestations, secure retention/backup/erasure, actual TLS/redirect/replay behavior,
supported-OS callback delivery, full app/core builds, settings/navigation/UI/accessibility,
iPhone/iPad/macOS physical qualification, privacy/security/mobile/operations approval and rollout.
