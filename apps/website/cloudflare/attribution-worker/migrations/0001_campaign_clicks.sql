CREATE TABLE IF NOT EXISTS campaign_clicks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  slug TEXT NOT NULL,
  campaign_token TEXT NOT NULL,
  platform TEXT NOT NULL,
  angle TEXT NOT NULL,
  referrer_host TEXT,
  client_signal TEXT,
  country TEXT,
  has_provider_token INTEGER NOT NULL DEFAULT 0,
  has_custom_product_page INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_campaign_clicks_created_at ON campaign_clicks(created_at);
CREATE INDEX IF NOT EXISTS idx_campaign_clicks_campaign_token ON campaign_clicks(campaign_token);
CREATE INDEX IF NOT EXISTS idx_campaign_clicks_slug ON campaign_clicks(slug);
