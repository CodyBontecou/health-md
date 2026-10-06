# Production backup and recovery runbook

Status: earlier recoverable-service proposal, **outside the selected unbacked public MVP**; no provider, region, retention, custody or operations approval for a backed service. No production backup exists. The disposable VM pilot remains intentionally unbacked and is not covered by this runbook.

**Interview scope update:** [Q18/Q21–Q22/Q26](production-design-interview.md) decline formal numeric recovery targets, select **no Health.md backups**, require exclusively US MVP compute/storage and permit D1 automatic history subject to reviewed copy terms. D1 is not selected/provisioned or US/deletion-qualified; history alone is not consistent object/account/historical-key recovery. Q35–Q56 select decimal monthly/annual 1 GB/50 GB/100 GB/1 TB tiers and a **10 GB lifetime-linked benefit/no general free tier**. Q48–Q53 settle verified paid-expiry clock, 30-day archive-grace reads/downloads, days 0/7/21/29 email plus persistent warnings, service-warning-failure holds and archive-only primary erasure with old grants revoked/minimal account state retained. This is not revision age expiry or instant provider-history purge. Included-capacity continuation, external store reductions and exact copy terms remain open; Q50 does not authorize automatic still-paid retirement. Renewal/account recovery cannot restore erased exports. [Checked billing/copy facts](native-subscription-and-large-export-research.md) inform the remaining policy. Q56 withdraws the $100 spending envelope, not loss warnings or no-resurrection safeguards; profitability is assumed, not proven. Permanent-loss disclosure stays. Earlier backup/escrow/restore and 15-minute/four-hour proposals below are not MVP gates, passed evidence or authority to back up either service. Any future provider recovery must reconcile deleted data/revoked grants and fail closed without suppression evidence. A later backed product needs a separately accepted recovery policy and real isolated restore evidence.

## Evidence currently available

`npm run test:restore-drill` (also included in `npm run check`) creates only reserved-domain synthetic data, closes its local SQLite database, copies encrypted metadata/object files into isolated temporary roots, opens the restored copy with the original key set, checks all migrations and database integrity, verifies an exact download, denies a second account, and proves a wrong wrapping key cannot disclose plaintext.

This proves application invariants against a consistent local synthetic snapshot. It does **not** prove Cloudflare D1 PITR/export, R2 inventory/versioning, Queue recovery, regional failure behavior, production scale, key escrow, 15-minute RPO, four-hour RTO, or deletion propagation. Only a provider-backed staging restore can supply that evidence.

## Proposed production recovery set

The approved design must capture, with mutually independent access controls:

1. D1 metadata/control state at a documented recovery point, including migration identity;
2. private R2 application ciphertext and provider object metadata;
3. every referenced identity/legacy/wrapping key version in an approved independent escrow or recoverable key system;
4. deployable source/configuration revision and binding inventory with no secret values;
5. Queue/DLQ operational state or an explicit reconstruction procedure from durable D1 jobs; and
6. aggregate health-free evidence: snapshot time, counts, ciphertext bytes, key-version counts, provider revision and checksums where supported.

Do not copy plaintext exports, email ciphertext decryptions, account IDs, object keys, owner dates, credentials, or key bytes into backup reports, logs, tickets or chat. Backup storage is inside the sensitive boundary even when objects remain application-encrypted.

## Scheduled synthetic staging drill

Run at the approved interval and after storage/migration/key/region changes:

1. Create new isolated restore D1/R2/Worker resources with synthetic-only hostnames and deployment identity. Never restore over source or production resources.
2. Record source provider recovery point, migration list, aggregate row/object/byte counts and wrapping-key-version counts.
3. Restore D1 to the chosen point and copy/recover R2 ciphertext according to the approved provider mechanism. Do not expose public bucket access.
4. Provide the restore Worker only the separately recovered key versions. Leave email sends, invitations, public routes, mobile credentials and MCP disabled.
5. Run database integrity/foreign-key/migration checks and compare aggregate inventory. Reconcile D1 references against R2 without logging keys.
6. Against reserved-domain synthetic tenants only, verify:
   - exact object hash/download across legacy and current account-key versions;
   - current daily pointers and duplicate receipts;
   - tenant isolation for inventory, download, portability and lifecycle routes;
   - wrong/missing key and tampered ciphertext fail closed;
   - deletion requested before the recovery point resumes safely;
   - deletion completed before the recovery point is absent or is re-erased according to disclosed backup expiry;
   - Queue jobs can be reconstructed/retried without duplicate acknowledgement; and
   - expired or `aborting` upload intents resume ciphertext-first cleanup, release quota exactly once, and cannot produce metadata that points to deleted ciphertext.
7. Measure recovery-point lag and elapsed restore/service-validation time. Compare with the approved RPO/RTO; do not average away a miss.
8. Destroy the isolated restore resources and ephemeral credentials under two-person verification. Retain only the health-free signed evidence record for the approved period.

## Recovery activation

1. Incident lead declares recovery and freezes deployments, invitations and token issuance. Make ingest fail closed rather than acknowledge writes during an uncertain cutover.
2. Preserve forensic/provider evidence without enabling content logs. Confirm whether key compromise is in scope; do not restore compromised secrets as trusted.
3. Select a recovery point that satisfies integrity and deletion/legal constraints. Document any expected data-loss window accurately.
4. Restore into fresh private resources and execute the staging validation above before routing traffic.
5. Rotate affected credentials/keys using the approved runbooks. Existing write tokens may need deliberate device reenrollment; never silently point them at an incompatible service.
6. Restore owner reads, revocation and deletion first when safe; reopen ingest and invitations only after ledger reconciliation and approval.
7. Communicate status without account/health details. If RPO/RTO is missed or data is lost, say so; do not claim durability not evidenced.

## Deletion and retention

Primary account deletion is ciphertext-first and immediate authority revocation. Source paths verify exact-key absence through metadata-only R2 reads before erasing account/intent metadata; unreadable or false-success outcomes remain retryable rather than claiming deletion. Recovery media/PITR may retain deleted ciphertext until the disclosed expiry. The product/privacy owners must set and publish that maximum, and restore automation must replay deletion tombstones/jobs so a restore does not make deleted data active. A key must not be destroyed until references are zero in primary and restored evidence and the recovery window has expired; conversely, key retention must not exceed the approved legal/security policy without escalation.

## Blocked decisions for a future backed service

- Cloudflare recovery mechanism and contractual retention for each service;
- independent key escrow/provider and two-person access;
- processing/storage region and cross-region recovery;
- approved RPO/RTO per launch stage;
- backup and deletion expiry;
- drill frequency, evidence retention and named recovery/on-call owners;
- failover DNS/status communication; and
- cost ceiling for backup/restore storage and exercises.

Until a backed service is separately selected, these decisions approved and a provider-backed synthetic drill passes, its recovery claims remain blocked. This is not an archive-restore gate for the intentionally unbacked MVP, nor permission to open signup or remove permanent-loss disclosure.
