CREATE TABLE IF NOT EXISTS campaign_installs (
  event_id TEXT PRIMARY KEY,
  install_id TEXT NOT NULL UNIQUE,
  event_name TEXT NOT NULL,
  occurred_at TEXT NOT NULL,
  platform TEXT NOT NULL,
  app_version TEXT NOT NULL,
  build_number TEXT NOT NULL,
  campaign_token TEXT NOT NULL,
  source TEXT NOT NULL,
  medium TEXT NOT NULL,
  content_angle TEXT NOT NULL,
  referrer_click_timestamp_seconds INTEGER,
  install_begin_timestamp_seconds INTEGER,
  received_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_campaign_installs_campaign_token
  ON campaign_installs(campaign_token);
CREATE INDEX IF NOT EXISTS idx_campaign_installs_received_at
  ON campaign_installs(received_at);

-- Global fixed-window throttling. This stores aggregate request counts only, never IPs,
-- User-Agents, request IDs, device details, or other request metadata.
CREATE TABLE IF NOT EXISTS campaign_ingest_windows (
  window_start TEXT PRIMARY KEY,
  request_count INTEGER NOT NULL
);

CREATE VIEW IF NOT EXISTS campaign_attribution_summary AS
WITH campaign_tokens AS (
  SELECT campaign_token FROM campaign_clicks
  UNION
  SELECT campaign_token FROM campaign_installs
),
click_totals AS (
  SELECT campaign_token, COUNT(*) AS redirect_clicks
  FROM campaign_clicks
  GROUP BY campaign_token
),
install_totals AS (
  SELECT campaign_token, COUNT(*) AS attributed_installs
  FROM campaign_installs
  GROUP BY campaign_token
)
SELECT
  campaign_tokens.campaign_token,
  COALESCE(click_totals.redirect_clicks, 0) AS redirect_clicks,
  COALESCE(install_totals.attributed_installs, 0) AS attributed_installs
FROM campaign_tokens
LEFT JOIN click_totals USING (campaign_token)
LEFT JOIN install_totals USING (campaign_token);
