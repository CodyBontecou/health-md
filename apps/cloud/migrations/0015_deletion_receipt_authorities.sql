-- Multiple browser requests can already hold independently generated deletion
-- status credentials before one account-disable transaction wins. Preserve each
-- opaque authority without exposing or duplicating the internal deletion job.
CREATE TABLE account_deletion_receipts (
  deletion_id TEXT NOT NULL REFERENCES account_deletions(id) ON DELETE CASCADE,
  status_token_hash TEXT PRIMARY KEY,
  status_expires_at TEXT NOT NULL
) STRICT;

CREATE INDEX account_deletion_receipts_expiry
  ON account_deletion_receipts(status_expires_at);
CREATE INDEX account_deletion_receipts_job
  ON account_deletion_receipts(deletion_id);

-- Forward-only compatibility for receipts issued by migration 0012.
INSERT INTO account_deletion_receipts (deletion_id, status_token_hash, status_expires_at)
SELECT id, status_token_hash, status_expires_at
FROM account_deletions
WHERE status_token_hash IS NOT NULL AND status_expires_at IS NOT NULL;

-- The child row is now the only status authority. Do not retain duplicate
-- hashes in the legacy columns after a successful transactional backfill.
UPDATE account_deletions
SET status_token_hash = NULL, status_expires_at = NULL
WHERE status_token_hash IS NOT NULL OR status_expires_at IS NOT NULL;
