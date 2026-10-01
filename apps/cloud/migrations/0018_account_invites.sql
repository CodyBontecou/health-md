-- One-time, privacy-minimized cohort admission for split production identity.
-- email_lookup is HMAC-SHA256(identity key, "email-lookup-v1\0" + normalized email).
-- Raw invite addresses never enter D1 or deployment configuration.

CREATE TABLE account_invites (
  email_lookup TEXT PRIMARY KEY,
  created_at TEXT NOT NULL,
  expires_at TEXT,
  CHECK (length(email_lookup) = 64),
  CHECK (expires_at IS NULL OR expires_at > created_at)
) STRICT;

CREATE INDEX account_invites_expiry
  ON account_invites(expires_at)
  WHERE expires_at IS NOT NULL;
