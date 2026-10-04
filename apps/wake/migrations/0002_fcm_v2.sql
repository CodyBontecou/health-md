-- Additive Worker-only notification transport extension. Existing rows and
-- legacy INSERTs retain APNs/v1 defaults; no token is reinterpreted as FCM.
ALTER TABLE wake_registrations
  ADD COLUMN transport TEXT NOT NULL DEFAULT 'apns' CHECK (transport IN ('apns', 'fcm'));
ALTER TABLE wake_registrations
  ADD COLUMN registration_version INTEGER NOT NULL DEFAULT 1 CHECK (registration_version IN (1, 2));
ALTER TABLE wake_registrations ADD COLUMN management_hash TEXT;

-- V1 nonce semantics remain untouched. V2 replay protection is per wake ID,
-- across management and request domains, with a bounded retention window.
CREATE TABLE wake_v2_nonces (
  wake_id TEXT NOT NULL REFERENCES wake_registrations(wake_id) ON DELETE CASCADE,
  nonce TEXT NOT NULL,
  seen_at INTEGER NOT NULL,
  PRIMARY KEY (wake_id, nonce)
);
CREATE INDEX idx_wake_v2_nonces_seen ON wake_v2_nonces(seen_at);

-- A revoked v2 ID is never reused: replay of its original enrollment cannot
-- resurrect the old wake credential. Tombstones retain only opaque ID/time.
CREATE TABLE wake_v2_revocations (
  wake_id TEXT PRIMARY KEY,
  revoked_at INTEGER NOT NULL
);

-- A bounded, database-atomic delivery lease prevents concurrent v2 requests
-- from bypassing per-ID dedupe/budget. No provider credentials are persisted.
ALTER TABLE wake_counters ADD COLUMN in_flight_nonce TEXT;
ALTER TABLE wake_counters ADD COLUMN in_flight_until INTEGER NOT NULL DEFAULT 0;
