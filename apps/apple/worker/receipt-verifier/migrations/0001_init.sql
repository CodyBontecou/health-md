-- Schema only, captured through Wrangler D1 export --no-data on 2026-10-07.
-- No user data. Original deployed devices and schedules definitions.

CREATE TABLE devices (
  user_id     TEXT NOT NULL,
  platform    TEXT NOT NULL CHECK (platform IN ('ios', 'macos')),
  apns_token  TEXT NOT NULL,
  bundle_id   TEXT NOT NULL,
  last_seen   INTEGER NOT NULL,
  PRIMARY KEY (user_id, platform)
);

CREATE TABLE schedules (
  user_id       TEXT PRIMARY KEY,
  is_enabled    INTEGER NOT NULL,
  frequency     TEXT NOT NULL CHECK (frequency IN ('daily', 'weekly')),
  hour          INTEGER NOT NULL CHECK (hour BETWEEN 0 AND 23),
  minute        INTEGER NOT NULL CHECK (minute BETWEEN 0 AND 59),
  weekday       INTEGER CHECK (weekday IS NULL OR weekday BETWEEN 1 AND 7),
  timezone      TEXT NOT NULL,
  next_fire_at  INTEGER NOT NULL,
  updated_at    INTEGER NOT NULL
);

CREATE INDEX idx_schedules_due
  ON schedules(is_enabled, next_fire_at);
