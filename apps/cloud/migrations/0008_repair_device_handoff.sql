-- Staged request-only mobile authority. Not an ingest, account, or MCP token.
-- Never expose pending scope to an unapproved device or put a token in an app link.
CREATE TABLE repair_devices (
  id TEXT PRIMARY KEY,
  user_id TEXT REFERENCES users(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL UNIQUE,
  code_hash TEXT UNIQUE,
  source TEXT NOT NULL CHECK (source IN ('ios', 'android')),
  created_at TEXT NOT NULL,
  pairing_expires_at TEXT NOT NULL,
  grant_expires_at TEXT,
  approved_at TEXT,
  revoked_at TEXT,
  last_used_at TEXT
) STRICT;
CREATE INDEX repair_devices_owner ON repair_devices(user_id, approved_at DESC);
CREATE INDEX repair_devices_pending ON repair_devices(code_hash, pairing_expires_at);

CREATE TABLE repair_dispatches (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  draft_id TEXT NOT NULL UNIQUE REFERENCES repair_drafts(id) ON DELETE CASCADE,
  device_id TEXT NOT NULL REFERENCES repair_devices(id) ON DELETE CASCADE,
  state TEXT NOT NULL CHECK (state IN ('queued', 'claimed', 'confirmed', 'cancelled')),
  created_at TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  claimed_at TEXT,
  confirmed_at TEXT
) STRICT;
CREATE INDEX repair_dispatches_device_state ON repair_dispatches(device_id, state, expires_at);
