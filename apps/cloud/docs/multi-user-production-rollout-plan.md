# Multi-user production rollout plan

**Status:** proposal only. This document does not approve deployment, public signup, migration of pilot data, or production claims.

## Decision summary

Build the multi-user service as a new Cloudflare production profile, not by scaling the current EXE.dev VM. Preserve the VM, its account, credentials, storage, Tunnels, and disposable-pilot risk acceptance as an isolated legacy pilot until the owner explicitly migrates or retires it.

The first production release should retain the existing mobile compatibility contract:

- explicit opt-in only;
- `POST /api/v1/exports` accepts the existing `healthmd.api_export` v1/v2 compatibility envelope;
- Apple v8 and Android v4/v5 remain distinct retained documents;
- Android Raw API Snapshot remains unsupported;
- a successful response remains a durable receipt only after encrypted-object storage and metadata commit;
- ingest credentials remain write-only and cannot read account or MCP data.

Do not open the current password profile to more accounts. Production identity should use a separately reviewed multi-user flow. General-user MCP access, repair-device handoff, supplemental mobile upload, billing, and organization/team accounts are later releases, not launch dependencies.

## Provisional launch envelope

These are qualification targets, not public promises. Replace them with approved product and cost targets before implementation is declared complete.

| Dimension | Private beta | GA qualification target |
| --- | ---: | ---: |
| Registered accounts | 100 | 10,000 |
| Concurrent upload requests | 50 | 250 |
| Sustained accepted uploads | 5/second | 25/second |
| Burst | 25/second for 1 minute | 100/second for 1 minute |
| Concurrent commits per account | 2 | 2 |
| Payload limit | 25 MiB | 25 MiB, retained only if memory/load tests pass |
| Retained bytes per account | 1 GiB default | Product decision before GA |
| Ingest availability objective | 99.5% | 99.9% monthly |
| Metadata recovery point | 24 hours for beta | 15 minutes or better before GA |
| Recovery time | 24 hours for beta | 4 hours or better before GA |
| Primary deletion completion | 24 hours | 24 hours |
| Backup deletion expiry | documented | 35 days or an approved alternative |

Load tests must use synthetic envelopes and include worst-case valid 25 MiB requests. If the Worker cannot safely validate and application-encrypt that size within measured memory and CPU limits, either implement a versioned chunked encrypted-storage format or lower the advertised limit with explicit mobile/product documentation. Do not silently accept and truncate large days.

**Source milestone:** `npm run qualify:staging-load` implements the fail-closed synthetic procedure in `production-load-qualification.md`: it refuses known live/non-staging hosts, binds to the exact deployed revision, requires owner-only tokens from enough attested distinct disposable accounts to preserve per-account budgets, exercises 500 concurrent, 50/second for ten minutes and ten concurrent exact-25-MiB uploads, and emits only fixed aggregate evidence. It has not been run against provider infrastructure; a harness pass cannot replace provider metrics, cost review or owner sign-off.

## Target production topology

**Source milestone:** positive-route entrypoints `src/ingest-worker.ts` and `src/account-worker.ts`, scheduled-only `src/maintenance-worker.ts`, separate placeholder Wrangler profiles, CI dry-runs, and route-boundary tests are implemented. Placeholder IDs keep every profile non-deployable; no production resources, secrets, routes, or approval marker have been provisioned.

Use new, production-only resources and credentials:

1. **Write-only ingest Worker** at `api.healthmd.app`
   - Exposes only `POST /api/v1/exports` and `GET /health`.
   - Authenticates the write token before admission.
   - Applies token, account, IP-risk, payload, and edge abuse limits.
   - Writes application-encrypted objects to a private production R2 bucket.
   - Has no dashboard, download, session, MCP, signup, or read route.

2. **Account Worker** at `account.healthmd.app`
   - Owns signup/sign-in, sessions, token management, inventory, download, export, and deletion requests.
   - Uses a separate deployment identity and explicit route allowlist.
   - Serves first-party assets only, with strict CSP and no analytics or session replay.
   - Cannot accept exports or MCP requests.

3. **Control and metadata storage**
   - Use a new production D1 database initially, subject to the load gate below.
   - Keep every query account-bound and retain cross-account negative tests.
   - Add an atomic quota/reservation ledger rather than calculating quota only with `SUM(exports.byte_count)`.
   - Use forward-only migrations; never reuse the VM SQLite file or preview D1 state.

4. **Private encrypted object storage**
   - **Source milestone:** migrations `0011_account_export_keys.sql`/`0013_account_key_rewrap.sql` and the account-key resolver create one random DEK per account, wrap it with versioned AES-256-GCM KEKs, bind wrapping to account/key IDs, use it for new exports, preserve legacy reads, and fail closed on tampering. Maintenance conditionally rewraps at most 25 DEKs per invocation and counts an update only after reading back its exact randomized wrap, IV, current KEK ID and timestamp, so lost/zero-change D1 responses and concurrent winners remain idempotent; this follows the reviewed procedure in `account-key-rotation-runbook.md`; this does not replace the separate design required for compromised-DEK/object rotation. Split production profiles require per-account mode, while the VM stays legacy by default. No production KEK or migration is deployed.
   - Use a new private R2 bucket with public access disabled.
   - Add a versioned ciphertext format and key ID to every object.
   - Use per-account data-encryption keys wrapped by a managed production key-encryption key. Do not use one JSON root-key list as the long-term key-management system for all users.
   - Keep historical key versions until every referenced object is re-encrypted or verifiably deleted.

5. **Maintenance and lifecycle Worker**
   - **Source milestone:** finite revision retention conditionally deletes only metadata still unreferenced by current or supplemental pointers, reads back durable absence after normal/lost D1 responses before deleting ciphertext, and preserves ciphertext when verification is unreadable. Migration `0014_maintenance_cursors.sql` and `object-reconciliation.ts` then persist only an opaque provider cursor, scan at most 25 exact `v1/<uuid>` objects per invocation, preserve every export/upload-intent reference, delete only unreferenced ciphertext (including a safe orphan left by an unreadable retention outcome), and refuse cursor advancement on list/delete/unexpected-key failure. It runs only in the split maintenance profile; the VM keeps its existing local reconciliation. No production bucket was scanned.
   - Use Queues or another durable job mechanism for deletion, expired-session cleanup, revision retention, orphan reconciliation, and key rotation.
   - Do not rely on one daily cron processing only a few global rows.
   - Make every job idempotent, bounded, retryable, and observable without logging health data.

6. **Observability boundary**
   - **Source milestone:** split Workers emit only fixed profile/route/status/outcome/latency/size buckets to isolated Analytics Engine bindings; production validation requires each binding, provider failures cannot affect requests, and regression tests reject identifiers, credentials, URLs and request data. Provisional SLOs, alerts, staging qualification and incident handling are defined in `production-observability-and-slo.md`. No dataset or alert is deployed.
   - Emit aggregate request counts, status classes, latency/size buckets, queue depth, storage totals, deletion age, and reconciliation failures.
   - Never log bodies, health dates, metric values, emails, authorization headers, cookies, object keys, account IDs, export IDs, or stable pseudonyms.
   - Use random operational correlation IDs that are not persisted with account data.

The production path should use Cloudflare's Worker route directly rather than the current VM Tunnel. The existing VM services remain separate during rollout.

## Ingest concurrency and consistency design

**Source milestone:** migration `0010_multi_user_ingest.sql`, `src/upload-intents.ts`, and the ingest integration implement the account reservation ledger, two-active-upload limit, committed/reserved byte triggers, bounded exact-retry wait, exact reserved→object-written state/timestamp verification after lost D1 responses, ambiguous final D1 commit-response reconciliation, and expired-intent reconciliation. A lost batch response is accepted only after the export+committed-intent postcondition is read back; an unavailable post-commit read returns retryable backpressure without deleting possibly committed ciphertext. Synthetic VM and local-D1 migration tests cover this source state. It has not been applied to the live pilot or any production resource.

Do not replace the four-slot VM gate with a larger process-global number. The production Worker should horizontally serve different accounts and enforce fairness with durable account-scoped state.

Add these concepts to the production data model:

- `account_storage`: committed bytes, reserved bytes, quota, and version;
- `upload_intents`: account, token, idempotency key or digest, expected bytes, state, lease expiry, and timestamps;
- explicit states such as `reserved`, `object_written`, `committed`, `aborted`, and `reconciling`;
- a unique account-scoped payload digest and, when mobile clients support it, an account-scoped idempotency key;
- bounded active-intent count per account.

An upload should follow this state machine:

1. Validate host, method, token shape, token activity, content type, and declared size.
2. Read and validate a bounded body; compute its exact digest. Abort promptly on client disconnect.
3. In one D1 transaction, claim an idempotent intent, enforce at most two active uploads for that account, and reserve quota.
4. Encrypt and write the object under a random staging key.
5. In one D1 transaction, re-check account/token activity, insert metadata, update daily pointers, convert reserved bytes to committed bytes, and mark the intent committed.
6. Return 2xx only after step 5. Exact retries return the original receipt.
7. On failure, release the reservation and delete the staged object. A durable reconciler handles crashes between steps.

There should be no long in-memory queue. Return `429` with `Retry-After` for an account concurrency or token rate limit, and `503` with `Retry-After` for global dependency/load shedding. Mobile clients must use bounded exponential backoff and retain exact pending bytes for retry.

### D1 scale exit gate

Before beta, benchmark the full transaction shape at twice the private-beta target. Before GA, benchmark at twice the GA target, including concurrent different-account writes, same-account retries, R2 latency, deletion jobs, and dashboard reads.

If D1 cannot meet the target with headroom, stop rollout and adopt one of these in a new ADR:

1. account-sharded metadata databases with a small control-plane directory; or
2. account-scoped Durable Objects with SQLite for quota, idempotency, daily pointers, and metadata.

Do not discover or implement an unreviewed shard migration during a live incident.

## Identity and account lifecycle

**Source milestone:** forward-only migration `0016_magic_link_session_claims.sql` adds a random server-only claim nonce so one winning email-link claim, its hashed session and its reviewed audit event commit in one transaction; concurrent consumers cannot reuse it, a lost response is reconciled, and an unreadable outcome withholds the cookie. General session issuance and its reviewed audit event also commit atomically, and the one-time cookie is returned only after their exact durable postcondition survives an ordinary or lost D1 response; an unreadable outcome withholds the credential and returns a retryable error. Logout, one-session revocation and revoke-other-sessions also commit operation-specific audit markers atomically, recover lost D1 responses without adapter change counts, and never claim or clear the current cookie while verification is unreadable; the revoke-others response count comes from its durable transaction marker. Account-owned session inventory/revocation, a bounded reviewed security-activity history with no target IDs, fresh-email-session deletion step-up, immediate account disablement, optional lifecycle Queue dispatch/consumption, bounded ciphertext-first erasure, scheduled recovery fallback, opaque post-session deletion-status receipts, bounded account-data portability archives, and explicit email-provider/token/account hourly budgets are implemented with synthetic tests. Migration `0017_rate_limit_attempts.sql` records each opaque accepted/rejected decision and applies accepted shared counters in the same trigger transaction; concurrent attempts honor the exact cap, lost responses reconcile without adapter change metadata, unreadable decisions fail closed, and scheduled maintenance removes expired attempt rows before expired counters. Split profiles fail closed without abuse-budget configuration; exhausted eligible-email budget keeps the generic anti-enumeration response and emits only a fixed health-free event. Portability TAR pages stream no more than five owner-scoped, hash-verified exact envelopes plus a manifest and never stage plaintext in R2. Receipt tokens are generated by the browser before the destructive mutation, stored server-side only as hashes, expire after a bounded period, never enter URLs/storage, reveal only pending/completed, and cannot block deletion retries. Forward-only migration `0015_deletion_receipt_authorities.sql` lets independently pre-authorized concurrent requests and exact retries attach their own receipt hashes to the account's one internal deletion job without exposing that job ID or invalidating an earlier caller. The durable job/receipt postcondition is reconciled after ambiguous D1 outcomes without requiring a user row that concurrent maintenance may already have erased, so neither a lost response, concurrent request nor fast completion can leave an accepted caller without its already-known status authority. Maintenance's terminal disabled-user erasure and job-completion marker also share one transaction; the exact marker plus user absence is read back after normal or lost responses, and an unreadable outcome retries idempotently rather than trusting adapter change counts. `production-authorization-matrix.md` maps every current authority-bearing surface to positive and cross-tenant source evidence, including two-account session/token/deletion survival. The in-account activity history is not an out-of-band security notification. Public signup, passkeys/recovery codes, an approved notification/email provider and policy, Queue resources, deployed-revision assessment, and production deployment remain blocked.

The VM password implementation explicitly remains single-user. For production:

1. Start with invitation-only email-link accounts on the Worker profile.
2. Before open signup, choose and threat-model the long-term identity design. The recommended default is passkeys with verified-email bootstrap and separately stored recovery codes; email-link-only access requires an explicit account-takeover and recovery decision.
3. Add edge abuse controls, per-IP and per-identity limits, email-send budgets, generic anti-enumeration responses, session inventory, revoke-all-sessions, and security notifications.
4. Review the transactional email provider's data processing, region, retention, bounce, and suppression behavior.
5. Keep one individual per account for v1. Teams, family sharing, clinicians, delegated access, and minors require separate authorization models.
6. Make account deletion immediately disable sessions and every write/read token, then drive durable object and metadata erasure to verified completion.
7. Provide account data export, token revocation, session revocation, and deletion status without support staff needing to view health data.

Open signup must remain fail-closed in configuration until identity, abuse, privacy, recovery, deletion, and operational gates pass.

## Retention, recovery, and key management

**Source milestone:** `test/restore-drill.test.ts` exercises a closed, encrypted, isolated synthetic snapshot/restore with migration/integrity checks, exact-byte recovery, tenant denial, and wrong-key failure. `production-recovery-runbook.md` defines the provider-backed staging drill and accurate activation/deletion/key evidence. This local drill is explicitly not D1/R2/PITR, RPO/RTO, escrow, region, or production restore proof; all remain launch blockers.

The disposable pilot's no-backup decision does not carry into a general product.

Before beta with real user data:

- approve retention separately for current daily snapshots, superseded revisions, audit metadata, sessions, deleted accounts, and backups;
- configure D1 recovery/PITR and R2 durability/versioning capabilities appropriate to the approved design;
- back up or escrow production key material independently of the application deployment;
- document key rotation, compromise response, and crypto-erasure behavior;
- run a synthetic restore drill into an isolated environment and verify object/metadata hashes and tenant isolation;
- define RPO/RTO, on-call ownership, incident severity, provider outage behavior, and status communication;
- ensure account deletion propagates to primary storage promptly and to backups by the disclosed expiry.

A restore is not proven by a successful backup job. It is proven only by a bounded restore exercise with synthetic data and documented evidence.

## Privacy, legal, and security gates

Assign named product, security, privacy/legal, and operations owners before accepting public users. They must approve:

- the data-flow diagram and threat model;
- Cloudflare, email, monitoring, support, and any other subprocessors;
- processing regions and user residency commitments;
- privacy policy, terms, explicit cloud opt-in copy, retention, deletion, breach response, and support access policy;
- Apple Health and Health Connect policy implications and App Store/Play disclosures;
- whether any regulated-health obligations apply; do not claim HIPAA, regulated compliance, certification, or zero knowledge without the required contracts and evidence;
- an external application/infrastructure security assessment and remediation of launch-blocking findings;
- a vulnerability intake and incident-response process.

Support tools must default to metadata-free operational state. No operator dashboard should expose export contents merely for convenience.

## Mobile and public-contract work

The first beta may use the existing manually configured API Endpoint and write-only token. A general release should provide a deliberate Health.md Cloud destination on both Apple and Android with equivalent semantics where platform APIs permit:

- explicit sign-in or one-time device enrollment;
- clear disclosure of what is selected, where it is retained, quota/retention, and how to stop/delete it;
- write credentials stored in Keychain/Keystore and never placed in URLs, logs, shared setup exports, or browser storage;
- per-device naming and revocation;
- durable client operation IDs, exact-byte retries, bounded backoff, and visible pending/failure state;
- no automatic migration of an existing API Endpoint, no hidden upload, and no fabricated Apple/Android metric parity;
- physical-device tests for Apple compatibility v1/v2 and Android compatibility mode;
- Android Raw API Snapshot remains rejected unless a separately versioned contract is designed.

If the mobile envelope or API behavior changes, follow the repository's cross-platform contract/versioning process and update every affected producer, consumer, fixture, capability entry, and external integration.

## MCP and third-party agents

Do not include general-user MCP access in the initial multi-user launch. The existing VM MCP tokens and user consent are specific to the owner pilot and must not migrate.

A later production MCP release requires OAuth 2.1 authorization code with PKCE or another reviewed hosted-client flow, per-client consent, least-privilege scopes, expiry/revocation, bounded tools, provider-specific retention disclosure, and a separate security/privacy launch gate. A write token must never become a read credential.

## Delivery phases and exit gates

### Phase 0 — product and architecture approval

**Draft milestone:** proposed `docs/architecture/adr-0008-multi-user-healthmd-cloud-production.md` and `apps/cloud/docs/production-data-flow-threat-model.md` now define the target, provisional defaults, trust/data flows, threat-control-residual ledger, subprocessor decisions, cost formulas, owner matrix, and hard blockers. Every owner remains unassigned and every external/provider decision remains blocked; the drafts are not approval. `production-readiness-audit.md` maps every end-to-end criterion to evidence/gaps, while `npm run verify:production-safety` makes CI assert that the checked-in profiles remain closed, placeholder-bound and unapproved—not ready.

Artifacts:

- new production ADR superseding only the general-production portion of ADR-0007;
- approved capacity, quota, retention, regions, RPO/RTO, support, and pricing assumptions;
- data-flow diagram, threat model, subprocessor inventory, cost model, and rollout owner matrix.

Exit gate: named owners approve the target and the live pilot is explicitly excluded from production resources.

### Phase 1 — isolated production foundation

**Source milestone:** every split profile carries an intentionally invalid provenance placeholder; production runtime requires an exact lowercase 40-character Git commit SHA and `/health` publishes only the short revision. Controlled deployment must inject it consistently and rollback checks must confirm the served revision. No deployment workflow or production revision exists.

- Provision separate development, staging, and production Worker/D1/R2/Queue/KMS resources through reviewable infrastructure as code.
- Add the upload-intent/quota ledger and crash reconciliation.
- Split ingest, account, and maintenance deployment identities and route allowlists.
- Add health-free metrics, alerts, deployment provenance, migration checks, and rollback controls.
- Keep staging synthetic-only.

Exit gate: CI, synthetic end-to-end tests, dependency audit, migration rehearsal, restore drill, and twice-beta load test pass.

### Phase 2 — identity and lifecycle

- Implement invite identity, session/device inventory, recovery decision, account export, immediate revocation, deletion queue, and deletion status.
- Complete privacy/terms/consent and support workflows.
- Exercise cross-account, CSRF, token-confusion, enumeration, abuse, key-rotation, and deletion tests.

Exit gate: security/privacy owners approve an invite-only real-data beta.

### Phase 3 — cross-platform cloud destination

- Implement the same user outcome on Apple and Android.
- Add secure enrollment, durable retry/idempotency, pending-state UX, explicit consent, revocation, and deletion links.
- Keep the existing export schemas unless a separately reviewed contract change is necessary.

Exit gate: physical-device matrix, store disclosures, and cross-platform capability/fixture gates pass.

### Phase 4 — production qualification

- Run worst-case payload, concurrency, dependency-failure, client-abort, duplicate, stale-token, quota-race, orphan, restore, and deletion drills.
- Complete independent security assessment and remediate launch blockers.
- Validate alerts, on-call runbooks, status communication, cost ceilings, and emergency access controls.

Exit gate: twice-GA load target passes with capacity headroom and no unresolved critical/high launch finding.

### Phase 5 — controlled rollout

1. Staff/synthetic production validation.
2. Up to 10 explicitly consented real-data accounts.
3. 100-account invite beta.
4. 1,000-account staged beta after a stability and cost review.
5. Open signup only after all GA gates and a separate owner approval.

At each cohort, review availability, latency, failure classes, queue age, orphan count, deletion age, storage growth, email abuse, security events, and support burden. Stop expansion if any gate regresses.

## Cutover and rollback

- Do not point production resources at the pilot SQLite database, object directory, keys, credentials, or Tunnel.
- Validate production first on separate staging and production hostnames/resources.
- Before moving `api.healthmd.app`, freeze new pilot token issuance, communicate the change, and require deliberate production account/device enrollment. Existing phone settings must not be silently repointed with an incompatible token.
- Offer the owner an explicit, hash-verified migration or owner-controlled download/re-upload; never silently copy pilot health data.
- During rollback, disable signup and token issuance first, preserve account reads/deletion, and make ingest fail closed with no-store `503` responses. Never acknowledge data that was not durably committed.
- Retain keys and stored objects through incident resolution. DNS rollback must go to a reviewed maintenance/fail-closed service, not to the single-user pilot.

## Release acceptance checklist

A production rollout is blocked until all are true:

- [ ] Fresh production resources, secrets, keys, domains, and deployment identities exist.
- [ ] No production binding or credential is shared with website, Practice, wake, preview, or the VM pilot.
- [ ] Cross-tenant authorization tests cover every read, write, download, token, repair, lifecycle, and maintenance path.
- [ ] Per-account quota reservations and idempotent receipts survive concurrent requests and process failure.
- [ ] Client disconnects cannot leak capacity or reservations.
- [ ] Synthetic restore and key-rotation drills pass.
- [ ] Deletion disables access immediately and completes within the disclosed SLA.
- [ ] Load and cost tests pass the approved envelope with at least 2× headroom.
- [ ] Health-free observability and incident alerts are operational.
- [ ] Privacy, terms, consent, retention, subprocessor, store-disclosure, and support materials are approved.
- [ ] Independent security findings have no unresolved launch blockers.
- [ ] Apple and Android physical-device tests pass without schema/parity misrepresentation.
- [ ] Signup remains closed until the final explicit rollout approval.

## Product decisions still required

Recommended defaults are shown in parentheses:

1. Launch regions and residency commitment (single documented region/provider boundary initially).
2. Identity and recovery model (passkeys plus verified email and recovery codes).
3. Retention for superseded revisions (30 days) and current snapshots (until user deletion or quota action).
4. Per-account quota and paid/free policy (1 GiB beta; cost review before GA).
5. RPO/RTO (15 minutes / 4 hours for GA).
6. Minimum user age and support/account-recovery policy.
7. Whether users can opt into production MCP after launch (no for v1).
8. Whether open signup is needed at GA or an invite rollout can continue (invite until operational evidence supports open signup).
