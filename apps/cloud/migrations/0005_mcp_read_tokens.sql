-- Read authority is intentionally disjoint from ingest_tokens and sessions.
-- MCP opens this database read-only; only the offline operator CLI writes here.
CREATE TABLE mcp_read_tokens (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  label TEXT NOT NULL,
  token_hash TEXT NOT NULL UNIQUE,
  last_four TEXT NOT NULL,
  created_at TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  revoked_at TEXT
) STRICT;
CREATE INDEX mcp_read_tokens_user_created ON mcp_read_tokens(user_id, created_at DESC);
