PRAGMA foreign_keys = ON;

CREATE TABLE users (
  id TEXT PRIMARY KEY,
  email_lookup TEXT NOT NULL UNIQUE,
  email_ciphertext TEXT NOT NULL,
  email_iv TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'disabled')),
  created_at TEXT NOT NULL
) STRICT;

CREATE TABLE magic_links (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL UNIQUE,
  expires_at TEXT NOT NULL,
  consumed_at TEXT,
  created_at TEXT NOT NULL
) STRICT;
CREATE INDEX magic_links_user_created ON magic_links(user_id, created_at DESC);

CREATE TABLE sessions (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL UNIQUE,
  expires_at TEXT NOT NULL,
  created_at TEXT NOT NULL,
  last_seen_at TEXT NOT NULL
) STRICT;
CREATE INDEX sessions_user_expires ON sessions(user_id, expires_at);

CREATE TABLE ingest_tokens (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  token_hash TEXT NOT NULL UNIQUE,
  last_four TEXT NOT NULL,
  created_at TEXT NOT NULL,
  last_used_at TEXT,
  revoked_at TEXT
) STRICT;
CREATE INDEX ingest_tokens_user_created ON ingest_tokens(user_id, created_at DESC);

CREATE TABLE exports (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  object_key TEXT NOT NULL UNIQUE,
  encryption_key_id TEXT NOT NULL,
  plaintext_sha256 TEXT NOT NULL,
  byte_count INTEGER NOT NULL CHECK (byte_count > 0),
  envelope_schema_version INTEGER NOT NULL,
  daily_record_schema_version INTEGER NOT NULL,
  source TEXT NOT NULL CHECK (source IN ('ios', 'android')),
  exported_at TEXT NOT NULL,
  received_at TEXT NOT NULL,
  date_start TEXT NOT NULL,
  date_end TEXT NOT NULL,
  record_count INTEGER NOT NULL CHECK (record_count >= 0),
  failure_count INTEGER NOT NULL CHECK (failure_count >= 0),
  external_record_count INTEGER NOT NULL DEFAULT 0 CHECK (external_record_count >= 0)
) STRICT;
CREATE INDEX exports_user_received ON exports(user_id, received_at DESC);
CREATE INDEX exports_user_plaintext_hash ON exports(user_id, plaintext_sha256);

CREATE TABLE daily_records (
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  owner_date TEXT NOT NULL,
  export_id TEXT NOT NULL REFERENCES exports(id) ON DELETE CASCADE,
  record_index INTEGER NOT NULL CHECK (record_index >= 0),
  schema_version INTEGER NOT NULL,
  capture_status TEXT,
  exported_at TEXT NOT NULL,
  received_at TEXT NOT NULL,
  PRIMARY KEY (user_id, owner_date)
) STRICT;
CREATE INDEX daily_records_user_date ON daily_records(user_id, owner_date DESC);
CREATE INDEX daily_records_export ON daily_records(export_id);

CREATE TABLE audit_events (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  event_type TEXT NOT NULL,
  target_id TEXT,
  occurred_at TEXT NOT NULL
) STRICT;
CREATE INDEX audit_events_user_occurred ON audit_events(user_id, occurred_at DESC);

CREATE TABLE auth_rate_limits (
  bucket_key TEXT NOT NULL,
  window_start TEXT NOT NULL,
  request_count INTEGER NOT NULL CHECK (request_count >= 0),
  expires_at TEXT NOT NULL,
  PRIMARY KEY (bucket_key, window_start)
) STRICT;
CREATE INDEX auth_rate_limits_expires ON auth_rate_limits(expires_at);
