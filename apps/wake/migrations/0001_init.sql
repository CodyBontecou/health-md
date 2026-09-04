-- RFC-0005 P2 wake registrations, delivery counters, and replay nonces.
-- One row per pairing (keyed by opaque wake_id, never by install or IP).

CREATE TABLE IF NOT EXISTS wake_registrations (
  wake_id            TEXT PRIMARY KEY,
  user_id            TEXT NOT NULL,
  verification_hash  TEXT NOT NULL,      -- hex SHA-256 of the raw 32-byte wake key
  device_token       TEXT NOT NULL,      -- APNs token for this install
  peer_label         TEXT,               -- optional paired-computer display name
  created_at         INTEGER NOT NULL,   -- unix seconds
  rotated_at         INTEGER NOT NULL    -- unix seconds
);

CREATE TABLE IF NOT EXISTS wake_counters (
  wake_id              TEXT PRIMARY KEY,
  hour_bucket          INTEGER NOT NULL, -- floor(unix_seconds / 3600); scoping per wake_id, never per IP
  delivered_this_hour  INTEGER NOT NULL,
  last_delivered_at    INTEGER NOT NULL  -- unix seconds; 0 when never delivered
);

CREATE TABLE IF NOT EXISTS wake_nonces (
  nonce     TEXT PRIMARY KEY,
  wake_id   TEXT NOT NULL,
  seen_at   INTEGER NOT NULL             -- unix seconds; rows are pruned after the timestamp window
);

CREATE INDEX IF NOT EXISTS idx_wake_nonces_seen ON wake_nonces(seen_at);
