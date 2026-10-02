-- Operational evidence for bounded KEK rotation. This timestamp contains no
-- account identity beyond the existing owner-bound key row and no health data.
ALTER TABLE account_export_keys ADD COLUMN rewrapped_at TEXT;
