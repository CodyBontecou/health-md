-- Existing registrations remain unresolved and retain production routing until
-- a client explicitly registers its signed APNs environment.
ALTER TABLE devices ADD COLUMN apns_environment TEXT
  CHECK (apns_environment IS NULL OR apns_environment IN ('development', 'production'));
ALTER TABLE devices ADD COLUMN registration_revision TEXT NOT NULL DEFAULT '';
ALTER TABLE devices ADD COLUMN apns_blocked_reason TEXT;
ALTER TABLE schedules ADD COLUMN revision INTEGER NOT NULL DEFAULT 0;

-- A recipient accepted by APNs is not resent when another recipient retries.
-- Tokens and health data are never copied into delivery history.
CREATE TABLE delivery_attempts (
  user_id TEXT NOT NULL,
  platform TEXT NOT NULL,
  fire_at INTEGER NOT NULL,
  schedule_revision INTEGER NOT NULL,
  registration_revision TEXT NOT NULL,
  state TEXT NOT NULL CHECK (state IN ('sending', 'accepted', 'retry', 'blocked', 'expired')),
  attempts INTEGER NOT NULL DEFAULT 0,
  next_attempt_at INTEGER NOT NULL DEFAULT 0,
  lease_until INTEGER NOT NULL DEFAULT 0,
  claim_id TEXT,
  last_status INTEGER,
  last_reason TEXT,
  accepted_at INTEGER,
  PRIMARY KEY (user_id, platform, fire_at, schedule_revision, registration_revision)
);
CREATE INDEX idx_delivery_history ON delivery_attempts(fire_at);
