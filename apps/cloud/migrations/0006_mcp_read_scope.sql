-- Existing credentials remain limited to the original aggregate tools. A full
-- retained-export credential must be issued explicitly after owner consent.
ALTER TABLE mcp_read_tokens ADD COLUMN read_scope TEXT NOT NULL DEFAULT 'aggregates'
  CHECK (read_scope IN ('aggregates', 'full_export'));
