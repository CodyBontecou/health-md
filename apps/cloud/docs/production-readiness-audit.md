# Multi-user Cloud completion audit

Audit state: **objective not achieved; production rollout remains blocked**. This maps the concrete “implement end to end” objective to actual evidence rather than treating green tests or source volume as completion.

## Concrete success criteria

End-to-end completion means all of the following, not merely source implementation:

1. The existing public writer is healthy and cannot leak upload capacity after client disconnects.
2. The proposed multi-user architecture and product/security/privacy/operations decisions are approved by named owners.
3. Fresh isolated dev/staging/production infrastructure, keys, identities, domains, edge controls, alerts and recovery are provisioned from reviewed configuration.
4. Ingest is horizontally safe, account-fair, quota-bound, idempotent and crash-reconciled at qualified load.
5. Identity, account lifecycle, portability, deletion, recovery and tenant isolation work against deployed resources.
6. Per-account encryption/key rotation, backup/restore and deletion-through-recovery are proven.
7. Equivalent deliberate Cloud enrollment/retry/consent/revocation is shipped and physically tested on Apple and Android.
8. Privacy/terms/store disclosures, subprocessors, support, incident response and independent security review are approved.
9. Controlled cohorts meet SLO, cost, support and security gates before signup expands.
10. Cutover/rollback never silently migrates the pilot or acknowledges uncommitted data.

## Prompt-to-artifact checklist

| Requirement/gate | Concrete evidence inspected | State |
|---|---|---|
| Diagnose and restore failing public exports | Live `api.healthmd.app/health` 200; anonymous ingest 401; active writer/ingest/account and Tunnel services | satisfied for current pilot health |
| Prevent disconnected-client slot leaks | Isolated commit `4f748cc53` based exactly on deployed `2ffbee88b`; clean 14-file/46-test validation; installed bundle hashes; live four-abort authenticated probe followed by 422, not 503; temporary token removed | satisfied and deployed to pilot |
| Preserve pilot isolation/data/secrets | Deployment changed only three bundles; live migrations remain 7; SQLite quick check `ok`; prior bundles retained; no current source migrations/assets/secrets/data copied | satisfied for hotfix |
| New production ADR | Proposed ADR-0008 exists and explicitly preserves ADR-0007 pilot | drafted, not approved |
| Capacity/quota/retention/region/RPO/RTO/support/pricing/signup decisions | ADR-0008 provisional table and rollout plan decision list | **blocked: no named approval** |
| Data flow and threat model | `production-data-flow-threat-model.md` | drafted, independent review absent |
| Subprocessor/region inventory | threat-model decision ledger | **all providers blocked/unapproved** |
| Cost model | threat-model formulas and cohort envelope | drafted, provider quotes/load evidence absent |
| Owner/RACI matrix | ADR-0008 has five roles | **all five unassigned** |
| Fresh isolated infrastructure/IaC | split Wrangler profiles with deliberate placeholder D1/R2/Queue/AE bindings and invalid deployment-revision placeholders | source shape exists; **no resources/identities/domains provisioned** |
| Deployment provenance/rollback identity | split runtime requires full 40-character commit SHA; `/health` exposes short revision; tests reject placeholder | source verified; no controlled production workflow/deployment exists |
| Trust-boundary route split | `ingest-worker.ts`, `account-worker.ts`, `maintenance-worker.ts`; `service-profiles.test.ts`; three dry-runs | source verified; deployed production edge absent |
| Durable reservation/quota/idempotency | migration 0010, `upload-intents.ts`, trigger/concurrency/reconciliation tests | source verified; D1 2x benchmark/fault drill absent |
| Disconnect/crash handling | upload-intent tests plus deployed VM disconnect probe | VM verified; provider isolate/dependency drills absent |
| R2 orphan reconciliation | migration 0014, bounded persisted cursor, exact-key/reference checks, provider-failure tests | source verified; no production bucket scan/alert evidence |
| Account identity/invites | email-link auth, generic responses, IP/identity/provider budgets | source verified; provider/edge review absent |
| Long-term identity/recovery | ADR recommends passkeys + recovery codes; invite beta discloses no support override | **not implemented/approved for open signup** |
| Sessions/tokens/revocation | account lifecycle and two-account isolation tests | source verified |
| Deletion Queue/status/SLA | lifecycle Queue source, migration 0012, opaque status receipt, retry tests | source verified; Queue/DLQ/backup-expiry/SLA deployment absent |
| Account data export | five-envelope verified TAR pages and cross-account tests | source verified; production streaming qualification absent |
| Cross-tenant route matrix | `production-authorization-matrix.md` mapping current routes to tests; 2-account lifecycle/export/repair/MCP evidence | source verified; independent deployed-revision assessment absent |
| Per-account DEKs | migration 0011, account key resolver, legacy compatibility/tamper/isolation tests | source verified; approved production key provider absent |
| KEK rotation | migration 0013, bounded conditional rewrap, rotation runbook/tests | source verified; provider key custody/restore drill absent |
| Backup/restore | local encrypted `test:restore-drill`; `production-recovery-runbook.md` | local invariant verified; **not D1/R2/PITR/RPO/RTO proof** |
| Health-free metrics/SLOs | `telemetry.ts`, prohibited-field tests, AE placeholders, observability/SLO runbook | source verified; no dataset/dashboard/alerts/on-call deployed |
| Abuse/load shedding | token/account/email budgets and tests | source verified; WAF/bot controls and 2x load/cost evidence absent |
| Mobile Apple Cloud destination | existing manual compatibility API Endpoint only | **deliberate production enrollment/retry UX and physical matrix absent** |
| Mobile Android Cloud destination | existing manual compatibility API Endpoint only; raw snapshot rejected | **deliberate production enrollment/retry UX and physical matrix absent** |
| Public contract parity | no mobile envelope/schema change; compatibility fixtures remain | preserved, but phase-3 product work absent |
| Production MCP | explicitly deferred; pilot credentials isolated | correctly excluded from v1 |
| Privacy/terms/consent/store/support | requirements recorded in ADR/plan/threat model | **not supplied or approved** |
| Independent security assessment | required by ADR/plan | **not performed** |
| Staging restore/key/deletion/failure drills | runbooks and local tests | **provider-backed drills absent** |
| Twice-beta/twice-GA load and cost gates | fail-closed `qualify:staging-load` harness/runbook covers revision-bound 500-concurrent, 50/s × 10-minute and exact-25-MiB probes with health-free aggregates | **provider run, native metrics and accepted cost model absent** |
| Controlled cohorts | sequence documented | **not started/authorized** |
| Cutover/rollback | plan and recovery runbook | documented, not exercised against production |
| Signup closed | all split configs `closed`; runtime approval marker secret absent; placeholder bindings; CI safety verifier | satisfied fail-closed state |

## Verification commands and coverage

- `npm run check`: TypeScript Worker/VM checks and all synthetic unit/integration tests. It verifies source behavior; it does not exercise Cloudflare production bindings, physical devices or external providers.
- `npm run dry-run:profiles`: bundles all three profiles and lists bindings. It proves buildability, not resource correctness or deployment isolation.
- `npm run test:restore-drill`: local encrypted snapshot invariants only, explicitly not provider recovery proof.
- `npm audit --audit-level=moderate`: dependency advisory check only, not an application/infrastructure security assessment.
- `git diff --check`: whitespace validity only.
- `npm run verify:production-safety`: asserts production is still closed, placeholder-bound and unapproved. A passing result means **blocked safely**, not ready.

## Current blockers and next required inputs

No defensible implementation path can complete external/deployed gates without:

1. named product, security, privacy/legal, operations and mobile owners;
2. explicit approval of identity/recovery, region, retention/backup expiry, RPO/RTO, quota/pricing, age/support and signup policy;
3. approved Cloudflare/email/monitoring/support/key-custody arrangements and credentials;
4. authorization to provision separate synthetic staging and production resources;
5. Apple/Android product scope and physical-device access;
6. independent assessor and remediation process; and
7. authorization for each real-data cohort.

Until those inputs exist, the correct completion status is blocked—not complete—and signup/resources must remain closed.
