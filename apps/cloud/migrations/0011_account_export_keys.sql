-- Per-account export data-encryption keys. Each random DEK is wrapped by a
-- versioned production key-encryption key kept outside D1. Existing exports
-- retain their legacy encryption_key_id and remain readable during migration.
CREATE TABLE account_export_keys (
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  key_id TEXT NOT NULL,
  wrapping_key_id TEXT NOT NULL,
  wrapped_key TEXT NOT NULL,
  wrap_iv TEXT NOT NULL,
  created_at TEXT NOT NULL,
  retired_at TEXT,
  PRIMARY KEY (user_id, key_id)
) STRICT;
CREATE UNIQUE INDEX account_export_keys_one_active
  ON account_export_keys(user_id) WHERE retired_at IS NULL;
CREATE INDEX account_export_keys_wrapping_key
  ON account_export_keys(wrapping_key_id, retired_at);
