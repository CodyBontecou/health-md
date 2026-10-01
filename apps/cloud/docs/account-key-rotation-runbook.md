# Per-account export key rotation runbook

Status: source-only procedure for future split-profile production. Do not apply it to the legacy-key VM pilot. No production key provider, KEK, deployment or rotation is approved by this document.

## Model and limits

Each account has a random 256-bit export data-encryption key (DEK). D1 stores only an AES-256-GCM-wrapped DEK with the account ID, DEK ID and KEK version bound as authenticated data. Export objects retain the stable DEK ID. `0013_account_key_rewrap.sql` records the last rewrap time.

The bounded maintenance operation unwraps with the row's historical KEK and wraps the same DEK under `CURRENT_ACCOUNT_WRAPPING_KEY_ID`. It does **not** decrypt or rewrite health objects, does not change DEK IDs, and does not rotate a compromised account DEK. A DEK/ciphertext rotation requires a separate resumable object-migration design and approval.

The checked-in JSON keyring is only the Worker-secret interface. Before production, security/operations owners must approve the key custody system, independent escrow/recovery, access policy, rotation interval and incident procedure. Never put key bytes in D1, configuration files, command lines, CI output, telemetry, tickets or chat.

## Routine KEK rotation

1. Freeze unrelated deployments and record the reviewed source revision. Confirm all migrations through `0018` and a recent synthetic restore exercise.
2. Generate the new independent 32-byte KEK in the approved key system. Keep every still-referenced historical KEK.
3. Update the ingest, account and maintenance secret keyrings to include the new version while leaving the old version current. Verify all profiles pass their health/configuration checks.
4. Change `CURRENT_ACCOUNT_WRAPPING_KEY_ID` consistently in ingest, account and maintenance. New accounts/exports now use DEKs wrapped by the new KEK.
5. Let maintenance rewrap at most 25 rows per scheduled invocation. Concurrent invocations are safe: updates compare the old KEK ID, ciphertext and IV, so only one wins. Each invocation reads back the exact new KEK ID, randomized wrapped bytes, IV and timestamp before counting its update; a lost D1 response or zero change metadata cannot produce a false result.
6. Monitor only aggregate counts grouped by wrapping-key version. Do not export account/key rows to logs. Stop on any unwrap/authentication failure; this indicates missing/wrong/tampered historical material, not a row to skip.
7. Using synthetic accounts, verify pre-rotation and post-rotation objects download byte-for-byte, portability archives verify hashes, new uploads use the current KEK, deletion still completes, and a second account cannot resolve another account's DEK.
8. Confirm the count of every retired KEK is zero in the primary database and in an isolated restored copy. Retain old KEKs through the approved backup/PITR expiry plus safety margin. Only then schedule separately approved destruction with two-person evidence.

Example aggregate query (results contain key versions/counts only):

```sql
SELECT wrapping_key_id, COUNT(*) AS wrapped_keys
FROM account_export_keys
GROUP BY wrapping_key_id
ORDER BY wrapping_key_id;
```

## Failure and rollback

- **Missing historical KEK or GCM failure:** stop rotation, keep all rows/ciphertext, restore the correct historical key access, and investigate. Never overwrite or delete the failing row.
- **Maintenance interrupted or verification unreadable:** retain both KEKs and rerun. Already-current rows are skipped and conditional updates make the operation idempotent. Never infer completion from adapter change counts.
- **Bad new KEK deployment:** restore the prior current ID while retaining both key versions; exports already wrapped under the new version require the new KEK until rewrapped back in a separately reviewed operation.
- **Suspected KEK compromise:** disable invitations/token issuance and, if necessary, fail ingest closed. Preserve reads/deletion only if the incident lead determines key access is trustworthy. Rewrap alone does not repair exposure if the attacker obtained both KEK and wrapped rows; follow the approved breach and DEK/object-rotation process.
- **Suspected DEK compromise:** isolate the affected account without putting its ID in shared incident systems. This source milestone has no safe automatic ciphertext rotation; stop and use a reviewed migration.

A successful primary-database count is not permission to destroy a key. Restore evidence and the approved retention/backup window are mandatory for a general production service.
