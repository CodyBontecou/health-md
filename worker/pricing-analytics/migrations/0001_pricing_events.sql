-- Health.md privacy-safe pricing analytics event store.
-- Deliberately stores only validated, coarse pricing/activation fields.
-- Do not add health values, metric names, file/vault paths, exported content,
-- raw request IPs, user agents, or raw device identifiers to this schema.

CREATE TABLE IF NOT EXISTS pricing_events (
  id TEXT PRIMARY KEY,
  received_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  install_id TEXT NOT NULL,
  event_name TEXT NOT NULL,
  experiment_id TEXT,
  variant_id TEXT,
  app_version TEXT,
  build_number TEXT,
  platform TEXT,
  paywall_context TEXT,
  free_exports_used INTEGER,
  free_exports_remaining INTEGER,
  export_target_type TEXT,
  format_count INTEGER,
  metric_count_bucket TEXT,
  date_range_preset TEXT,
  date_span_bucket TEXT,
  product_id TEXT,
  purchase_outcome TEXT,
  authorization_status TEXT,
  error_category TEXT,
  payload_json TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_pricing_events_received_at
  ON pricing_events(received_at);

CREATE INDEX IF NOT EXISTS idx_pricing_events_event_received
  ON pricing_events(event_name, received_at);

CREATE INDEX IF NOT EXISTS idx_pricing_events_variant_received
  ON pricing_events(variant_id, received_at);

CREATE INDEX IF NOT EXISTS idx_pricing_events_install_event_received
  ON pricing_events(install_id, event_name, received_at);
