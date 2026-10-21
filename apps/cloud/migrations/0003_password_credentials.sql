-- Opt-in single-user password profile. No HTTP signup or password reset route.
-- Credentials are created and rotated by an offline, operator-authenticated
-- bootstrap workflow; only a keyed username lookup and salted verifier live in D1.
CREATE TABLE password_credentials (
  user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  username_lookup TEXT NOT NULL UNIQUE,
  salt TEXT NOT NULL,
  verifier TEXT NOT NULL,
  iterations INTEGER NOT NULL CHECK (iterations >= 600000),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
) STRICT;
