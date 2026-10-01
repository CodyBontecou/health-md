# ADR-0008: Multi-user Health.md Cloud production boundary

- Status: **Proposed — blocked pending named approvals and qualification evidence**
- Scope: future general multi-user Health.md Cloud only
- Related: ADR-0007, `apps/cloud/docs/multi-user-production-rollout-plan.md`

## Context

ADR-0007 authorizes only an isolated, disposable, unbacked single-owner pilot with explicitly accepted data-loss and review risks. Those exceptions cannot become general product defaults. Multi-user Cloud needs tenant isolation, durable admission/quota state, recoverability, lifecycle completion, accountable operations, and product/privacy decisions before real users are invited.

Source milestones now exist for split Worker profiles, durable upload reservations, per-account envelope keys and KEK rewrapping, account/session/token lifecycle, deletion status, bounded data portability, and health-data-free telemetry. They are test evidence, not approval, infrastructure, or a deployed service.

## Decision (proposed)

1. Build general production on fresh Cloudflare resources. Do not reuse the pilot VM, SQLite/files, keys, credentials, Tunnel, DNS target, or account.
2. Deploy separate ingest, account, and maintenance Workers with separate deployment identities, positive route allowlists, and least-privilege bindings. Maintenance has no public HTTP route.
3. Use a private production D1 database for initial cohorts, a private R2 bucket, a lifecycle Queue/DLQ, separate Analytics Engine datasets, and an approved independent key-custody/recovery system. D1 must pass the twice-target transaction benchmark or a new ADR chooses account-sharded D1 or account-scoped Durable Objects before rollout.
4. Keep ingestion credentials write-only. Authenticate before durable account-scoped admission; permit at most two active commits per account; reserve quota atomically; acknowledge only after encrypted object and metadata commit; reconcile crashes and exact retries.
5. Encrypt each account's export objects with a random account DEK wrapped by a versioned KEK. Preserve legacy reads only for controlled migration. Historical KEKs remain until primary and restored evidence has no references and the recovery-retention window expires.
6. Start invite-only with verified email-link sign-in. Split production stores only expiring one-time purpose-HMAC invite rows in D1, rechecks and consumes them with first-account creation, and rejects raw invite-address configuration; offline grant/revocation remains an approved operator action. There is no support bypass or manual email reassignment in v1. Loss of email access has no recovery path during the invite beta; this limitation must be disclosed. Passkeys plus recovery codes remain the recommended prerequisite for open signup and require a separate threat-model update.
7. Retain current daily snapshots until user deletion or documented quota action. Retain superseded revisions for 30 days. Use a 1 GiB/account beta quota. Deletion disables all authority immediately, drives ciphertext-first erasure, and exposes only an opaque bounded status receipt. Backup/PITR deletion follows the disclosed provider expiry.
8. Provide exact owner download and bounded account portability. Support personnel have no routine health-content access. Any future break-glass content access requires a separate approved, audited design.
9. Defer general-user MCP. A future release requires OAuth 2.1 authorization code with PKCE, scopes/consent, client retention qualification, and separate approval. Pilot MCP credentials never migrate.
10. Keep signup closed until explicit owner authorization after the gates below. No source merge, resource creation, successful test, or approval marker alone opens signup.

## Provisional product envelope

These values are design inputs, not approved promises:

| Item | Proposed value | Approval/evidence needed |
|---|---|---|
| Staff/private beta | 10 then 100 invited accounts | product, security, privacy, operations |
| GA planning capacity | 10,000 accounts; 250 concurrent uploads; 25 sustained uploads/s | 2x staging benchmark and cost review |
| Account upload concurrency | 2 active intents | synthetic fault/concurrency tests |
| Account quota | 1 GiB beta | pricing and storage-cost review |
| Current snapshot retention | until deletion/quota action | privacy/product approval and user copy |
| Superseded revision retention | 30 days | privacy/product approval |
| Deletion status receipt | 30 days, pending/completed only | privacy/security approval |
| Target RPO/RTO for GA | 15 minutes / 4 hours | provider design and successful restore drill |
| Production MCP | disabled | separate ADR/review |
| Signup | invitation only | separate open-signup approval |
| Beta pricing | no paid promise; cohort access only | product/finance decision |
| Region/residency | no commitment until provider placement is verified | privacy/legal/provider decision |

## Consequences

### Positive

- The pilot's accepted no-backup and single-owner risks remain contained.
- Write, account/read, and lifecycle surfaces have explicit trust boundaries.
- Horizontal upload scaling does not replace account fairness or quota correctness.
- Users can revoke authority, export exact retained data, request deletion, and verify completion without support viewing content.
- Telemetry and incident paths are designed not to copy health payloads or stable identities.

### Costs and limitations

- Cloudflare remains a transport/storage processor and service-side keys can decrypt data. This is not end-to-end encryption or zero knowledge.
- Whole-envelope validation/decryption still has a 25 MiB default per-envelope bound and requires load/memory qualification.
- D1/R2 are not one transaction; encrypted orphan reconciliation remains required.
- Invite email-link identity depends on email-provider/account security and has no beta recovery override.
- Managed key custody, backups, region, pricing, support, policy copy, mobile enrollment, physical-device evidence, and independent security review remain unresolved.

## Required approval record

The following roles must be named; a person may hold multiple roles only if the owner explicitly accepts the conflict. Approval must identify document revision and date.

| Role | Accountable decision | Name | Status |
|---|---|---|---|
| Product owner | audience, quota, retention, pricing, signup, consent copy | unassigned | blocked |
| Security owner | threat model, key custody, identity/recovery, assessment remediation | unassigned | blocked |
| Privacy/legal owner | data roles, subprocessors, region, policies, deletion/backup disclosures, stores | unassigned | blocked |
| Operations owner | SLOs, on-call, restore, migrations, rollback, status communication | unassigned | blocked |
| Mobile owner(s) | equivalent Apple/Android enrollment, retry, consent and device tests | unassigned | blocked |

Approval of this ADR would select an architecture; it would not by itself authorize a cohort. Each rollout stage requires its own recorded gate.

## Release gates

Before any real-data invite:

1. named roles approve this ADR, the threat model, data flow, subprocessors, region, policies, retention and recovery targets;
2. fresh dev/staging/production resources and deployment identities are reviewed; staging remains synthetic-only;
3. migration rehearsal, provider-backed synthetic restore under `apps/cloud/docs/production-recovery-runbook.md`, key-rotation, deletion, duplicate, disconnect, dependency-failure, quota-race and cross-tenant tests pass;
4. the twice-beta load test meets approved SLO/cost bounds;
5. alerts/on-call/status communication and fail-closed rollback are exercised;
6. independent security assessment has no unresolved critical/high launch blocker;
7. Apple and Android physical-device compatibility tests and store disclosures pass; and
8. the owner explicitly authorizes the next bounded cohort while signup configuration remains closed.

Open signup additionally requires the approved long-term identity/recovery design, abuse controls at public scale, GA 2x capacity evidence, and a separate owner authorization.

## Pilot non-migration invariant

No production hostname may silently repoint an enrolled pilot device to incompatible credentials. The owner may choose a deliberate hash-verified migration or exact download/re-upload. Production rollback goes to a reviewed fail-closed service, never to the pilot. The pilot's no-backup decision, password account, MCP consent, tokens and keys are not precedents for general users.
