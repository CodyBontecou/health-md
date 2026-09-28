-- Deletion jobs survive removal of the user row and can be inspected after
-- credentials/sessions are irreversibly removed. No email or health data here.
CREATE TABLE account_deletions (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL UNIQUE,
  requested_at TEXT NOT NULL,
  completed_at TEXT
) STRICT;
CREATE INDEX account_deletions_pending ON account_deletions(completed_at, requested_at);
