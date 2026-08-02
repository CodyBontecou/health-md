-- Add coarse onboarding-step attribution for pricing funnel analytics.
-- Values are validated by the worker and include coarse iOS, macOS, and Android onboarding steps.
-- Do not store folder names, paths, health values, raw dates, or device names.

ALTER TABLE pricing_events ADD COLUMN onboarding_step TEXT;

CREATE INDEX IF NOT EXISTS idx_pricing_events_onboarding_step_received
  ON pricing_events(onboarding_step, received_at);
