-- Opaque provider cursors for bounded global maintenance. Values contain no
-- account, object, health or identity metadata and grant no authority.
CREATE TABLE maintenance_cursors (
  name TEXT PRIMARY KEY,
  cursor_value TEXT NOT NULL,
  updated_at TEXT NOT NULL
) STRICT;
