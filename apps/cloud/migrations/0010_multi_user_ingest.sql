-- Durable per-account quota and concurrency state for horizontally scaled ingest.
-- The VM pilot may still impose its separate process-local gate, but production
-- correctness must not depend on one process or an in-memory queue.
CREATE TABLE account_storage (
  user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  committed_bytes INTEGER NOT NULL DEFAULT 0 CHECK (committed_bytes >= 0),
  reserved_bytes INTEGER NOT NULL DEFAULT 0 CHECK (reserved_bytes >= 0),
  quota_bytes INTEGER NOT NULL DEFAULT 1073741824 CHECK (quota_bytes > 0),
  version INTEGER NOT NULL DEFAULT 0 CHECK (version >= 0),
  updated_at TEXT NOT NULL
) STRICT;

INSERT INTO account_storage (user_id, committed_bytes, reserved_bytes, quota_bytes, version, updated_at)
SELECT u.id, COALESCE(SUM(e.byte_count), 0), 0, 1073741824, 0, u.created_at
FROM users u LEFT JOIN exports e ON e.user_id = u.id
GROUP BY u.id;

CREATE TRIGGER users_create_account_storage
AFTER INSERT ON users
BEGIN
  INSERT INTO account_storage
    (user_id, committed_bytes, reserved_bytes, quota_bytes, version, updated_at)
  VALUES (NEW.id, 0, 0, 1073741824, 0, NEW.created_at);
END;

-- Acquire one of two account-local read/parse positions before materializing a
-- request body. A crash leaves only a short lease; no process-local gate is an
-- authority for horizontally scaled admission.
CREATE TABLE upload_admissions (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_id TEXT NOT NULL REFERENCES ingest_tokens(id) ON DELETE CASCADE,
  created_at TEXT NOT NULL,
  expires_at TEXT NOT NULL CHECK (expires_at > created_at)
) STRICT;
CREATE INDEX upload_admissions_account_active
  ON upload_admissions(user_id, expires_at);
CREATE INDEX upload_admissions_expiry
  ON upload_admissions(expires_at, id);

CREATE TABLE upload_intents (
  id TEXT PRIMARY KEY,
  admission_id TEXT NOT NULL UNIQUE,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_id TEXT NOT NULL REFERENCES ingest_tokens(id) ON DELETE CASCADE,
  export_id TEXT NOT NULL UNIQUE,
  object_key TEXT NOT NULL UNIQUE,
  plaintext_sha256 TEXT NOT NULL,
  scope_digest TEXT,
  byte_count INTEGER NOT NULL CHECK (byte_count > 0),
  state TEXT NOT NULL CHECK (state IN ('reserved', 'object_written', 'committed')),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  UNIQUE (user_id, plaintext_sha256)
) STRICT;
CREATE INDEX upload_intents_account_active
  ON upload_intents(user_id, state, expires_at);
CREATE INDEX upload_intents_expiry
  ON upload_intents(state, expires_at);

CREATE TRIGGER upload_admissions_reserve
BEFORE INSERT ON upload_admissions
BEGIN
  SELECT CASE WHEN NOT EXISTS (
    SELECT 1 FROM ingest_tokens t JOIN users u ON u.id = t.user_id
    WHERE t.id = NEW.token_id AND t.user_id = NEW.user_id
      AND t.revoked_at IS NULL AND u.status = 'active'
  ) OR (
    (SELECT COUNT(*) FROM upload_admissions
      WHERE user_id = NEW.user_id AND expires_at > NEW.created_at) +
    (SELECT COUNT(*) FROM upload_intents
      WHERE user_id = NEW.user_id AND state IN ('reserved', 'object_written')
        AND expires_at > NEW.created_at)
  ) >= 2 THEN RAISE(ABORT, 'upload_admission_rejected') END;
END;

-- Reserve account quota and convert an already-held read/parse admission into
-- one of two durable write positions in the same transaction as the intent.
-- RAISE aborts and rolls back the reservation when any condition fails.
CREATE TRIGGER upload_intents_reserve
BEFORE INSERT ON upload_intents
BEGIN
  UPDATE account_storage
  SET reserved_bytes = reserved_bytes + NEW.byte_count,
      version = version + 1,
      updated_at = NEW.created_at
  WHERE user_id = NEW.user_id
    AND committed_bytes + reserved_bytes + NEW.byte_count <= quota_bytes
    AND EXISTS (
      SELECT 1 FROM upload_admissions a
      WHERE a.id = NEW.admission_id AND a.user_id = NEW.user_id
        AND a.token_id = NEW.token_id AND a.expires_at > NEW.created_at
    )
    AND (
      (SELECT COUNT(*) FROM upload_admissions
        WHERE user_id = NEW.user_id AND expires_at > NEW.created_at) +
      (SELECT COUNT(*) FROM upload_intents
        WHERE user_id = NEW.user_id AND state IN ('reserved', 'object_written')
          AND expires_at > NEW.created_at)
    ) <= 2
    AND EXISTS (
      SELECT 1 FROM ingest_tokens t JOIN users u ON u.id = t.user_id
      WHERE t.id = NEW.token_id AND t.user_id = NEW.user_id
        AND t.revoked_at IS NULL AND u.status = 'active'
    );
  SELECT CASE WHEN changes() != 1
    THEN RAISE(ABORT, 'upload_reservation_rejected') END;
END;

CREATE TRIGGER upload_intents_consume_admission
AFTER INSERT ON upload_intents
BEGIN
  DELETE FROM upload_admissions
  WHERE id = NEW.admission_id AND user_id = NEW.user_id AND token_id = NEW.token_id;
  SELECT CASE WHEN changes() != 1
    THEN RAISE(ABORT, 'upload_admission_consume_failed') END;
END;

-- Every export path is also bounded by the durable account quota. SQLite
-- serializes these trigger updates, so different Worker isolates cannot race
-- the committed-byte counter over quota.
CREATE TRIGGER exports_enforce_account_quota
BEFORE INSERT ON exports
BEGIN
  SELECT CASE WHEN NOT EXISTS (
    SELECT 1 FROM account_storage
    WHERE user_id = NEW.user_id
      AND committed_bytes + NEW.byte_count <= quota_bytes
  ) THEN RAISE(ABORT, 'account_quota_exceeded') END;
END;

CREATE TRIGGER exports_add_committed_bytes
AFTER INSERT ON exports
BEGIN
  UPDATE account_storage
  SET committed_bytes = committed_bytes + NEW.byte_count,
      version = version + 1,
      updated_at = NEW.received_at
  WHERE user_id = NEW.user_id;
END;

CREATE TRIGGER exports_remove_committed_bytes
AFTER DELETE ON exports
BEGIN
  UPDATE account_storage
  SET committed_bytes = MAX(committed_bytes - OLD.byte_count, 0),
      version = version + 1,
      updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
  WHERE user_id = OLD.user_id;
END;

CREATE TRIGGER upload_intents_release_on_commit
AFTER UPDATE OF state ON upload_intents
WHEN OLD.state IN ('reserved', 'object_written') AND NEW.state = 'committed'
BEGIN
  UPDATE account_storage
  SET reserved_bytes = MAX(reserved_bytes - NEW.byte_count, 0),
      version = version + 1,
      updated_at = NEW.updated_at
  WHERE user_id = NEW.user_id;
END;

CREATE TRIGGER upload_intents_release_on_delete
AFTER DELETE ON upload_intents
WHEN OLD.state IN ('reserved', 'object_written')
BEGIN
  UPDATE account_storage
  SET reserved_bytes = MAX(reserved_bytes - OLD.byte_count, 0),
      version = version + 1,
      updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
  WHERE user_id = OLD.user_id;
END;
