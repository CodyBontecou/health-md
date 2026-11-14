-- Opaque post-session deletion status. Only a SHA-256 token hash is retained;
-- no account identity or health data is added beyond the existing deletion job.
ALTER TABLE account_deletions ADD COLUMN status_token_hash TEXT;
ALTER TABLE account_deletions ADD COLUMN status_expires_at TEXT;
CREATE UNIQUE INDEX account_deletions_status_token
  ON account_deletions(status_token_hash) WHERE status_token_hash IS NOT NULL;
CREATE INDEX account_deletions_status_expiry
  ON account_deletions(status_expires_at) WHERE status_expires_at IS NOT NULL;
