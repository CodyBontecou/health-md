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
| Required runtime key material | account/combined validate exact identity-key length; ingest/account/combined validate the legacy keyring/current key; split profiles validate current account KEKs; normalized material reuse across identity/legacy/KEK/pepper domains or version IDs fails closed before operation | source fail-closed tests pass; no approved production secret store or injected keys exist |
| Trust-boundary route split | `ingest-worker.ts`, `account-worker.ts`, `maintenance-worker.ts`; the account profile requires a distinct credential-free bare HTTPS ingest origin; non-identity profiles reject excess identity/decryption/browser/Queue authority; `service-profiles.test.ts`; three dry-runs | source verified; deployed production edge/DNS absent |
| Required runtime bindings | split validation requires D1/R2 everywhere, account assets + lifecycle producer, maintenance lifecycle producer/consumer binding, and AE telemetry; the complete validator runs before scheduled and Queue work; after validation, independent bounded scheduled phases (including dormant repair-state expiry) continue through peer failure and emit one aggregate failure; negative profile/failure-isolation tests | source fail-closed tests pass; no production resources are provisioned |
| Required runtime limits | ingest/account require a bounded envelope cap; account requires bounded session/magic-link TTLs; maintenance requires finite bounded revision and security-audit retention; negative profile tests reject missing/unlimited TTLs and excess account-profile retention authority | source fail-closed checks pass; retention still needs owner approval |
| Durable reservation/quota/idempotency | migration 0010, `upload-intents.ts`, trigger/concurrency/reconciliation tests, exact reserved→object-written lost-response/unreadable-read tests, export-batch lost-response and post-commit-read outage tests | source verified; D1 2x benchmark/provider fault drill absent |
| Disconnect/crash handling | upload-intent tests plus deployed VM disconnect probe | VM verified; provider isolate/dependency drills absent |
| R2 orphan/revision reconciliation | finite retention conditionally removes only unreferenced metadata, verifies durable absence before ciphertext deletion, and preserves unreadable outcomes for migration 0014's bounded exact-key/reference scanner; lost-response/unreadable/provider-failure tests | source verified; no production bucket scan/alert evidence |
| Account identity/invites | split account profile requires email-link auth, rejects password/pepper/open signup and raw invite-email configuration; migration 0018 uses expiring one-time D1 admission keyed only by purpose HMAC, transactionally rechecks/consumes it with first-account creation, and provides owner-only offline grant/revocation SQL; generic responses, concurrent/revoked/lost-response invite tests and IP/identity/provider budgets; migration 0016 atomically binds one-time links to sessions; session and token creation/revocation use exact postconditions | source verified; provider/edge/key-custody/recovery and cohort approval absent |
| Long-term identity/recovery | ADR recommends passkeys + recovery codes; invite beta discloses no support override | **not implemented/approved for open signup** |
| Sessions/tokens/revocation | account lifecycle and two-account isolation tests | source verified |
| Deletion Queue/status/SLA | lifecycle Queue source, migrations 0012/0015, multiple client-known hashed authorities per unique job, bounded oldest-first receipt/tombstone expiry, request and maintenance-completion ambiguous-commit/concurrent-request/concurrent-completion/exact-retry plus cross-account scheduled-failure-isolation tests | source verified; Queue/DLQ/backup-expiry/SLA deployment absent |
| Account data export | five-envelope verified TAR pages, exact pre-materialization ciphertext-size bounds and cross-account tests | source verified; production streaming qualification absent |
| Cross-tenant route matrix | `production-authorization-matrix.md` mapping current routes to tests; 2-account lifecycle/export/repair/MCP evidence | source verified; independent deployed-revision assessment absent |
| Per-account DEKs | migration 0011, account key resolver, legacy compatibility/tamper/isolation tests | source verified; approved production key provider absent |
| KEK rotation | migration 0013, bounded conditional rewrap with exact durable read-back after lost/zero-change responses, concurrent-winner and unreadable-verification tests, rotation runbook | source verified; provider key custody/restore drill absent |
| Backup/restore | local encrypted `test:restore-drill`; `production-recovery-runbook.md` | local invariant verified; **not D1/R2/PITR/RPO/RTO proof** |
| Health-free metrics/SLOs | `telemetry.ts`, prohibited-field tests, AE placeholders, observability/SLO runbook | source verified; no dataset/dashboard/alerts/on-call deployed |
| Abuse/load shedding | token/account/email budgets use migration 0017's expiring opaque attempt decisions and trigger-applied counters; ingest identifiers are purpose-separated hashes rather than raw token/account UUIDs; concurrent-limit, accepted/rejected lost-response, unreadable-verification and bounded multi-page expiry tests | source verified; WAF/bot controls and 2x load/cost evidence absent |
| Mobile Apple Cloud destination | existing manual compatibility API Endpoint only; split production rejects repair enrollment/dispatch flags | **deliberate production enrollment/retry UX and physical matrix absent** |
| Mobile Android Cloud destination | existing manual compatibility API Endpoint only; raw snapshot and split-production repair flags rejected | **deliberate production enrollment/retry UX and physical matrix absent** |
| Public contract parity | no mobile envelope/schema change; compatibility fixtures remain | preserved, but phase-3 product work absent |
| Production MCP | explicitly deferred; pilot credentials isolated | correctly excluded from v1 |
| Privacy/terms/consent/store/support | requirements recorded in ADR/plan/threat model | **not supplied or approved** |
| Independent security assessment | required by ADR/plan | **not performed** |
| Staging restore/key/deletion/failure drills | runbooks and local tests | **provider-backed drills absent** |
| Twice-beta/twice-GA load and cost gates | fail-closed `qualify:staging-load` harness/runbook covers revision-bound 500-concurrent, 50/s × 10-minute and exact-25-MiB probes with health-free aggregates | **provider run, native metrics and accepted cost model absent** |
| Controlled cohorts | sequence documented | **not started/authorized** |
| Cutover/rollback | plan and recovery runbook | documented, not exercised against production |
| Signup and deployment closed | all split configs `closed`, route-free, placeholder-bound and secret-free; the CI safety verifier checks profile entrypoint route/cookie boundaries, exact migrations 0001–0018 plus critical trigger/authority/invite semantics, required test/smoke/VM/split-dry-run/audit workflow commands, and forbids checked-in approval, secrets or any non-dry-run deploy | satisfied fail-closed state; this is not launch approval |

## Audited source artifact surface

Fresh audit snapshot, updated on 2026-09-30: draft PR #163 tracks `feat/cloud-multi-user-production-foundation`, is mergeable with a clean merge state, and contains 69 changed files. Every repository check triggered for the current audited source passed; there are no reviews or assigned reviewers. The PR remains draft. Commit-specific head and check evidence must be read from the PR rather than copied here, so this record cannot silently present an older revision as current. The changed files map to deliverables as follows:

- Trust-boundary/deployment: `.github/workflows/cloud-ci.yml`; `wrangler.{ingest,account,maintenance}.toml`; `src/{ingest-worker,account-worker,maintenance-worker,telemetry,http,index,types}.ts`; `package.json`.
- Ingest/storage/crypto/lifecycle: migrations `0010`–`0018`; `src/{upload-intents,exports,account-export-keys,account-export,crypto,lifecycle,object-reconciliation,auth,dashboard}.ts`.
- Account UI: `public/{dashboard.html,dashboard.js,deletion-status.html,deletion-status.js}` and `docs/public-account-dashboard.md`.
- VM compatibility and disconnect safety: `vm/{server,storage}.ts`, `test/vm.test.ts`, and ADR-0007 clarification. The deployed disconnect hotfix remains the separately scoped commit `4f748cc5338a7dc3b122a3d2503b91c9b55d3370`.
- Qualification/gates: `scripts/{qualify-staging-load,staging-load-lib,verify-production-safety}.mjs`, `scripts/staging-load-lib.d.mts`, and the Cloud workflow.
- Focused evidence: `test/{abuse-limits,account-export-keys,account-export,account-lifecycle,crypto,ingest-commit-ambiguity,object-reconciliation,repair-migration,repair-supplements,restore-drill,service-profiles,staging-load,telemetry,upload-intents,vm}.test.ts`.
- Governance/runbooks: `README.md`; the nine files under `docs/` named in this audit; and proposed ADR-0008.

No listed test substitutes for the unresolved deployed/provider/mobile/legal gates in the table above.

## Verification commands and coverage

- `npm run check`: on the audited head, 32 files and 154 tests pass, including Worker and VM TypeScript checks plus all synthetic unit/integration tests. It verifies source behavior; it does not exercise Cloudflare production bindings, physical devices or external providers.
- `npm run test:smoke`: passes in an isolated worktree against local Wrangler D1/R2 with synthetic Apple v1/v2 and Android v4 envelopes, replacement ordering, encrypted roundtrip, tenant denial and revocation. The repository worktree's pre-existing owner-only `.dev.vars` is not overwritten or read by the harness.
- `npm run dry-run:profiles`: all three profiles bundle and list only their intended bindings. It proves buildability, not resource correctness or deployment isolation.
- `npm run test:restore-drill`: local encrypted snapshot invariants pass only; this is explicitly not provider recovery proof.
- `npm audit --audit-level=moderate`: zero known vulnerabilities at audit time; this is a dependency advisory check, not an application/infrastructure security assessment.
- `git diff --check`: passes; this proves whitespace validity only.
- `npm run verify:production-safety`: passes after semantically checking 34 unique files, 13 unchecked gates, five unassigned owners, exact migrations `0001`–`0018`, split entrypoint boundaries, and every required CI source gate; it asserts production is still closed, placeholder-bound and unapproved. A passing result means **blocked safely**, not ready.
- Live boundary recheck: API/account health return 200, anonymous ingest and MCP return 401, account-host ingest returns 404, the ten actual writer/account/ingest/MCP proxy and Tunnel units are active, and `systemctl --failed` reports none after clearing a stale transient login helper. These checks prove current pilot availability only.

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
