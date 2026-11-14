-- Independently retained repair envelopes. No current-day pointer is changed by
-- inserts here. Scope is purpose-encrypted; hash supports idempotent retries.
-- This table is not an ingest grant, device receipt, or public schema change.
CREATE TABLE supplemental_exports (
  export_id TEXT PRIMARY KEY REFERENCES exports(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  spec_ciphertext TEXT NOT NULL,
  spec_iv TEXT NOT NULL,
  scope_digest TEXT NOT NULL,
  created_at TEXT NOT NULL
) STRICT;
CREATE INDEX supplemental_exports_owner_created ON supplemental_exports(user_id, created_at DESC);

CREATE TABLE supplemental_records (
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  owner_date TEXT NOT NULL,
  export_id TEXT NOT NULL REFERENCES supplemental_exports(export_id) ON DELETE CASCADE,
  record_index INTEGER NOT NULL CHECK (record_index >= 0),
  schema_version INTEGER NOT NULL,
  capture_status TEXT,
  PRIMARY KEY (user_id, owner_date, export_id)
) STRICT;
CREATE INDEX supplemental_records_owner_day ON supplemental_records(user_id, owner_date, export_id);
