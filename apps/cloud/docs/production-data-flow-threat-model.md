# Multi-user production data flow and threat model

Status: proposed review artifact; no production resources or approvals. Scope: the future service in ADR-0008, excluding the isolated VM pilot and deferred production MCP.

## Data classes

| Class | Examples | Storage/handling rule |
|---|---|---|
| Health content | complete compatibility envelopes, free text, embedded binary, metric values | TLS; application-encrypted R2 only; decrypt only for owner reads; never logs/telemetry/D1 |
| Sensitive health metadata | owner dates, schema/source, object/export relations, byte counts, status | minimum owner-bound D1; no logs/support tools |
| Identity/authentication | encrypted email, lookup HMAC, session/token hashes, invite state | D1 ciphertext/hash only; secrets outside D1; generic responses |
| Operational aggregate | fixed route/status/latency/size buckets and counts | isolated Analytics Engine; no identifiers, URLs, exact sizes/durations, dates or values |
| Key material | identity key, legacy read keys, account KEKs, password/email provider credentials | approved secret/key system only; separate deployment access; never D1/R2/logs/CLI arguments |

## Data flow and trust boundaries

```text
Apple/Android API Endpoint
  | TLS + write-only hmd_ing credential
  v
[Public edge / Cloudflare transport boundary]
  v
Ingest Worker (no cookies/read/session routes)
  | authenticate -> bounded parse -> D1 reservation (<=2/account, quota)
  | per-account DEK encryption
  +---- ciphertext ----> private R2
  +---- minimal metadata/pointers/receipt ----> production D1

Owner browser
  | TLS + Secure HttpOnly SameSite=Strict session
  v
Account Worker (no ingest/MCP route)
  |---- identity/session/token/deletion metadata ----> D1
  |---- owner-scoped ciphertext read ----> R2 -> decrypt -> no-store response
  |---- deletion job ----> lifecycle Queue
  +---- first-party static assets (no third party)

Cron / lifecycle Queue
  v
Maintenance Worker (no public route)
  |---- bounded deletion/reconciliation/retention/DEK rewrap ----> D1 + R2
  +---- fixed health-free outcomes ----> maintenance metrics

All Workers ---- fixed aggregate buckets only ----> isolated Analytics Engine
Email provider <---- destination email + generic sign-in message ---- Account Worker
```

The public website, Practice, Wake, pilot VM, pilot MCP, preview resources, support/ticket tools and mobile analytics are outside these boundaries and receive no production binding, cookie, token, object, database, key or proxy path.

Cloudflare terminates TLS before application encryption and hosts compute/storage/key-bearing Worker processes. It can observe transport and infrastructure metadata and is a required processor. Application encryption reduces accidental storage/log exposure; it does not remove provider trust.

## Entry points and authority

| Entry point | Accepted authority | Explicitly denied |
|---|---|---|
| Ingest `POST /api/v1/exports` | active write-only ingest bearer | cookie, account session, read/agent/MCP/deletion token |
| Ingest `/health` | none | all data/account behavior |
| Account auth | invite + email-link proof | account enumeration, open signup, support bypass |
| Account APIs/assets | valid owner session; same-origin intent on mutations | ingest, MCP, cross-account IDs |
| Deletion status | high-entropy hashed-at-rest receipt | account/read/write authority; identity/content disclosure |
| Maintenance | scheduled event or bound Queue | public HTTP, browser/device credentials |
| Metrics | Worker binding only | raw request context and joins to account data |

## Threats, controls, and residual risk

| Threat | Existing/source control | Required qualification or residual risk |
|---|---|---|
| Credential theft/replay | hashed tokens/sessions; Secure strict cookie; write/read authority separation; a random server-only claim nonce atomically binds the winning single-use magic link to its exact session/audit state; session issuance/revocation and write-token creation/revocation commit with operation-specific reviewed audit records atomically and reconcile exact durable postconditions after ambiguous D1 responses; unreadable issuance withholds the cookie and unreadable revocation never claims success or clears a current cookie; bounded expiry; split account deployment rejects password mode/pepper and accepts only closed/invite email-link identity | passkeys/recovery decision before open signup; email account compromise remains beta risk |
| Account enumeration | generic link request response; keyed email/IP buckets; race-safe first-account creation and durable-link postcondition reconciliation; closed/invite enum validation (unknown values fail closed) | email provider bounce/suppression side channels and edge abuse review |
| Cross-tenant object/reference access | every SQL/object key starts from authenticated `user_id`; random IDs; cross-account tests; account-bound AEAD | exhaustive route matrix and independent assessment |
| CSRF/cross-origin mutation | SameSite=Strict, exact Origin checks, no wildcard CORS; bearer ingest is not browser session | browser compatibility and proxy-header review |
| Token confusion | distinct prefixes/tables/authenticators; split route allowlists; ingest strips cookies; account denies ingest/MCP; account runtime metadata requires a distinct credential-free bare HTTPS ingest origin | repeat negative matrix on every route or hostname change |
| Privilege creep from deployment configuration | ingest rejects assets, Queue and identity/email secrets; maintenance rejects assets, identity/email and legacy-decryption secrets; repair enrollment/dispatch flags are invalid in split production | deployed service identities/bindings and provider access policy still require independent verification |
| Quota/concurrency race | D1 trigger reservation, <=2 active intents/account, committed/reserved ledger, exact digest uniqueness; write-token cap is a serialized conditional insert with durable token+audit verification after ambiguous responses | 2x concurrent D1 benchmark; provider contention/availability |
| Disconnect/crash slot leak | stream pipeline on VM; durable leases/reservation reconciliation in Worker design | dependency-failure and isolate-termination drills |
| Duplicate/stale snapshot | account digest idempotency; normalized newest `exported_at` pointer; revisions retained | mobile operation IDs are still needed for deliberate Cloud destination |
| R2/D1 partial or ambiguous commit | staged object + transactional metadata, durable postcondition read after lost batch response, no ciphertext cleanup on an unreadable outcome, durable orphan reconciliation | no cross-service transaction; orphan scanner/alerts and provider fault drills required |
| Ciphertext substitution/tamper | account/export AAD, object digest, per-account wrapped DEK AAD, exact container-size rejection before R2 body materialization, download verification | provider/key compromise remains; independent crypto implementation review |
| Key loss/compromise | versioned keys, historical resolution, conditional bounded KEK rewrap, rotation runbook | approved KMS/escrow/restore evidence absent; DEK/object rotation not implemented |
| Missing/malformed runtime configuration | account/combined profiles validate a 32-byte identity key; ingest/account/combined validate the legacy keyring/current key; all split profiles validate current account KEKs; normalized key material must be unique across identity, legacy-export, account-KEK and pilot-pepper domains and version IDs; split profiles validate relevant payload/session/magic-link/deletion/revision bounds | deployed secret injection, key-provider evidence and approved retention decisions absent |
| Excessive payload/parser DoS | declared/exact plaintext and ciphertext bounds, pre-materialization R2 size checks, JSON/content/schema checks, account admission, explicit token/account hourly limits | whole-envelope memory up to cap; edge/WAF and 2x worst-case load gate |
| Email abuse | invite-only mode, generic responses, identity/IP HMAC windows, explicit global hourly send budget with fixed health-free exhaustion event | provider account-side budget/alerts, edge bot controls and suppression/privacy review absent |
| Session persistence after deletion | user disabled transactionally before Queue; authenticators recheck active user; Queue processing requires the same complete approved production configuration as scheduled maintenance | deletion SLA, Queue/DLQ alerts and backup expiry evidence absent |
| Deletion skips ciphertext or loses status authority | ciphertext-first bounded deletion, retries, scheduled fallback, client-known pre-mutation status receipts, one unique internal job with independently hashed concurrent/exact-retry authorities, atomic disablement/job/receipt transaction and postcondition read that survives concurrent completion; final user erasure+job completion is atomic and reconciled by its exact terminal state after lost responses | R2/D1 outage can delay completion; disclose and monitor SLA |
| Portability exfiltration | owner session, no-store, five-object pages, per-object digest/key check, no staged plaintext | compromised browser/session can read by design; reauthentication decision before GA |
| Sensitive observability/support | fixed low-cardinality metrics only; no app error logging; no routine content tooling | provider edge logs and emergency break-glass design need approval |
| Supply-chain/deployment compromise | lockfile, CI type/test/audit/dry-run, separate profiles, placeholders/fail-closed marker, service-specific runtime binding-presence checks | provenance/signing/deployment identity policy and external assessment pending |
| Region/residency mismatch | no claim in source | D1/R2/Queue/Workers/AE/email placement and contracts must be verified before user promise |
| Backup restores deleted/other-tenant data | proposed separate recovery and deletion expiry | no production backup/restore implementation or drill yet |
| Insider misuse | least-privilege profiles; no content support UI; health-free metrics | named access approvers, audit, two-person key operations and break-glass policy pending |

## Abuse and failure invariants

- Never convert a write credential into read authority.
- Never return 2xx for ingest until durable encrypted object + metadata commit.
- Never release reservation correctness to an in-memory/process-global queue.
- Never skip an unreadable/tampered key row during rotation or deletion.
- Never log an exception/request object from health-data paths.
- Never weaken account boundaries to restore availability.
- Disable invitations/token issuance before increasing risky limits during an incident.
- Preserve owner read, revocation, portability and deletion when safe; otherwise fail closed with no-store responses.

## Planned subprocessors and decision ledger

No row is approved merely by appearing here.

| Provider/function | Data exposed | Required decision/evidence | Status |
|---|---|---|---|
| Cloudflare Workers/D1/R2/Queue/Analytics Engine/DNS/TLS | health content in transit/runtime/ciphertext storage; sensitive metadata; aggregate metrics; service keys | contract/DPA, locations, retention/deletion, access/audit, incident terms, recovery capabilities | blocked |
| Transactional email provider (source currently models Resend) | destination email, delivery metadata, generic sign-in message | contract/DPA, regions, retention, suppression/bounce behavior, account security, alternative/provider choice | blocked |
| Domain registrar/DNS account | hostnames and traffic-routing metadata | MFA/access/recovery and change audit | blocked |
| Monitoring/paging provider | only fixed service/route/status/threshold/time alerts | retention, access, region, payload template verification | blocked |
| Support/ticket provider | user-provided contact text; no credentials/health payloads by policy | retention, deletion, access, user warning, escalation policy | blocked |
| Independent security assessor | synthetic staging and source/config evidence by default | NDA/DPA, scope, secure evidence exchange, finding retention | blocked |
| Apple/Google app distribution | app disclosures and platform/device metadata; no Cloud export content from server | policy/disclosure review | blocked |

No analytics, session replay, advertising, third-party browser asset, public object URL, broad Logpush, or health-content support vendor is proposed.

## Cost and capacity model

Use current provider quotes at approval time; do not copy volatile prices into architecture. For cohort `A` accounts:

- retained object bytes = `A × average retained bytes/account` (bounded by quota, not assumed fully used);
- monthly R2 writes = uploads + deletion/reconciliation/rotation object operations;
- monthly R2 reads = dashboard/explorer/download/portability reads + synthetic probes;
- D1 writes/upload = reservation + object-written transition + export/daily-pointer transaction + intent commit, plus auth/rate/lifecycle writes;
- Queue operations = deletion messages/retries + DLQ handling;
- email sends = invited sign-in attempts after rate/budget rejection;
- telemetry points = one per HTTP invocation plus maintenance invocation/batch;
- egress = exact downloads + portability + account views, not just ingest.

Cost review must model p50/p95/p99 envelope sizes, revision retention, download/export rates, email abuse, Queue retries, D1 rows/queries, telemetry retention, backup/PITR and 2x load qualification. Set warning/hard budgets for staging and each cohort. A cost ceiling may close invitations or shed new ingest; it must not silently delete data or acknowledge uncommitted uploads.

## Review evidence required

1. independent confirmation of the source evidence mapped in `production-authorization-matrix.md` against the deployed route/credential/cross-tenant matrix;
2. dependency-failure, crash, duplicate, stale-token, quota-race and disconnect tests;
3. synthetic KEK rotation and isolated restore with object/metadata hashes;
4. deletion through Queue retry/DLQ and backup-expiry evidence;
5. provider edge/runtime logging capture proving prohibited fields absent;
6. 2x cohort and 2x GA load/cost reports;
7. Apple/Android physical-device API compatibility and secure-storage evidence;
8. independent assessment and remediation record; and
9. named, revision-specific product/security/privacy/operations approvals.

Update this model whenever identity, recovery, region, storage, keys, mobile envelope, MCP, support access, subprocessors, logging or signup changes.
