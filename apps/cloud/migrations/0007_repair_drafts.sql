-- Owner-session-only proposed export scopes. Never used as an ingest grant or
-- executable mobile instruction. Dates and metric IDs live in AEAD ciphertext.
CREATE TABLE repair_drafts (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  spec_ciphertext TEXT NOT NULL,
  spec_iv TEXT NOT NULL,
  source TEXT NOT NULL CHECK (source IN ('ios', 'android')),
  day_count INTEGER NOT NULL CHECK (day_count BETWEEN 1 AND 31),
  state TEXT NOT NULL DEFAULT 'draft' CHECK (state IN ('draft', 'cancelled')),
  created_at TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  cancelled_at TEXT
) STRICT;
CREATE INDEX repair_drafts_owner_created ON repair_drafts(user_id, created_at DESC);
