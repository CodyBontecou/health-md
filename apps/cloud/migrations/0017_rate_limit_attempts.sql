-- Persist one opaque decision per rate-limit attempt. This makes admission
-- independent of adapter `meta.changes` and lets a caller reconcile a lost D1
-- response without incrementing the shared counter twice.
CREATE TABLE auth_rate_limit_attempts (
  id TEXT PRIMARY KEY,
  bucket_key TEXT NOT NULL,
  window_start TEXT NOT NULL,
  accepted INTEGER NOT NULL CHECK (accepted IN (0, 1)),
  expires_at TEXT NOT NULL
);

CREATE INDEX auth_rate_limit_attempts_expiry
  ON auth_rate_limit_attempts(expires_at);

-- D1 executes this trigger in the same transaction as the attempt INSERT.
-- A committed accepted decision therefore proves its counter increment also
-- committed; INSERT OR IGNORE makes an exact retry idempotent.
CREATE TRIGGER auth_rate_limit_attempt_applied
AFTER INSERT ON auth_rate_limit_attempts
WHEN NEW.accepted = 1
BEGIN
  INSERT INTO auth_rate_limits (bucket_key, window_start, request_count, expires_at)
  VALUES (NEW.bucket_key, NEW.window_start, 1, NEW.expires_at)
  ON CONFLICT (bucket_key, window_start) DO UPDATE SET
    request_count = request_count + 1,
    expires_at = excluded.expires_at;
END;
