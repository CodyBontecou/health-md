-- Privacy-safe 30-day onboarding funnel by platform, app version, and experiment variant.
-- Cohorts are at least 24 hours old so in-progress sessions do not look abandoned.
-- Every stage is a distinct pseudonymous app installation, never a raw event-row count.
-- The 24-hour activation and seven-day purchase windows use Worker receipt times;
-- delayed offline delivery can blur either boundary.
WITH starts AS (
  SELECT
    install_id,
    COALESCE(platform, '(missing)') AS platform,
    COALESCE(app_version, '(missing)') AS app_version,
    COALESCE(variant_id, '(missing)') AS variant_id,
    MIN(received_at) AS started_at
  FROM pricing_events
  WHERE event_name = 'pricing_onboarding_started'
    AND julianday(received_at) >= julianday('now', '-30 days')
    AND julianday(received_at) <= julianday('now', '-1 day')
  GROUP BY install_id, platform, app_version, variant_id
), flags AS (
  SELECT
    s.install_id,
    s.platform,
    s.app_version,
    s.variant_id,
    s.started_at,
    CASE WHEN julianday(s.started_at) <= julianday('now', '-7 days') THEN 1 ELSE 0 END AS seven_day_mature,
    MAX(CASE WHEN e.event_name = 'pricing_onboarding_step_viewed' AND e.onboarding_step = 'health_access' THEN 1 ELSE 0 END) AS health_access,
    MAX(CASE WHEN e.event_name = 'pricing_onboarding_health_skipped' THEN 1 ELSE 0 END) AS health_skipped,
    MAX(CASE WHEN e.event_name = 'pricing_onboarding_step_viewed' AND e.onboarding_step = 'sample_export' THEN 1 ELSE 0 END) AS sample_export,
    MAX(CASE WHEN e.event_name = 'pricing_onboarding_step_viewed' AND e.onboarding_step = 'obsidian_plugin' THEN 1 ELSE 0 END) AS obsidian_plugin,
    MAX(CASE WHEN e.event_name = 'pricing_onboarding_step_viewed' AND e.onboarding_step = 'mac_how_it_works' THEN 1 ELSE 0 END) AS mac_how_it_works,
    MAX(CASE WHEN e.event_name = 'pricing_onboarding_step_viewed' AND e.onboarding_step = 'mac_iphone_app' THEN 1 ELSE 0 END) AS mac_iphone_app,
    MAX(CASE WHEN e.event_name = 'pricing_onboarding_step_viewed' AND e.onboarding_step = 'mac_connect' THEN 1 ELSE 0 END) AS mac_connect,
    MAX(CASE WHEN e.event_name = 'pricing_onboarding_step_viewed' AND e.onboarding_step = 'folder_setup' THEN 1 ELSE 0 END) AS folder_setup,
    MAX(CASE WHEN e.event_name = 'pricing_onboarding_folder_selected' THEN 1 ELSE 0 END) AS folder_selected,
    MAX(CASE WHEN e.event_name = 'pricing_onboarding_folder_skipped' THEN 1 ELSE 0 END) AS folder_skipped,
    MAX(CASE WHEN e.event_name = 'pricing_onboarding_step_viewed' AND e.onboarding_step = 'unlock' THEN 1 ELSE 0 END) AS unlock_viewed,
    MAX(CASE WHEN e.event_name = 'pricing_onboarding_continue_free_tapped' THEN 1 ELSE 0 END) AS continued_free,
    MAX(CASE WHEN e.event_name = 'pricing_onboarding_purchase_tapped' THEN 1 ELSE 0 END) AS purchase_tapped,
    MAX(CASE WHEN e.event_name = 'pricing_onboarding_step_viewed' AND e.onboarding_step = 'ready' THEN 1 ELSE 0 END) AS ready_viewed,
    MAX(CASE WHEN e.event_name = 'pricing_onboarding_completed' THEN 1 ELSE 0 END) AS completed,
    MAX(CASE WHEN e.event_name = 'pricing_export_succeeded' AND julianday(e.received_at) - julianday(s.started_at) <= 1 THEN 1 ELSE 0 END) AS exported_within_24h,
    MAX(CASE WHEN julianday(s.started_at) <= julianday('now', '-7 days')
                  AND e.event_name = 'pricing_purchase_finished'
                  AND e.purchase_outcome = 'succeeded'
                  AND julianday(e.received_at) - julianday(s.started_at) <= 7
             THEN 1 ELSE 0 END) AS purchased_within_7d
  FROM starts s
  LEFT JOIN pricing_events e
    ON e.install_id = s.install_id
   AND COALESCE(e.platform, '(missing)') = s.platform
   AND COALESCE(e.app_version, '(missing)') = s.app_version
   AND COALESCE(e.variant_id, '(missing)') = s.variant_id
   AND e.received_at >= s.started_at
  GROUP BY s.install_id, s.platform, s.app_version, s.variant_id, s.started_at
)
SELECT
  platform,
  app_version,
  variant_id,
  COUNT(*) AS starters,
  SUM(health_access) AS health_access,
  SUM(health_skipped) AS health_skipped,
  SUM(sample_export) AS sample_export,
  SUM(obsidian_plugin) AS obsidian_plugin,
  SUM(mac_how_it_works) AS mac_how_it_works,
  SUM(mac_iphone_app) AS mac_iphone_app,
  SUM(mac_connect) AS mac_connect,
  SUM(folder_setup) AS folder_setup,
  SUM(folder_selected) AS folder_selected,
  SUM(folder_skipped) AS folder_skipped,
  SUM(unlock_viewed) AS unlock_viewed,
  SUM(continued_free) AS continued_free,
  SUM(purchase_tapped) AS purchase_tapped,
  SUM(ready_viewed) AS ready_viewed,
  SUM(completed) AS completed,
  SUM(exported_within_24h) AS exported_within_24h,
  SUM(seven_day_mature) AS seven_day_mature_starters,
  SUM(purchased_within_7d) AS purchased_within_7d,
  SUM(CASE WHEN seven_day_mature = 1 AND continued_free = 1 THEN 1 ELSE 0 END) AS mature_free_starters,
  SUM(CASE WHEN seven_day_mature = 1 AND continued_free = 1 AND exported_within_24h = 1 THEN 1 ELSE 0 END) AS mature_free_activated,
  SUM(CASE WHEN seven_day_mature = 1 AND continued_free = 1 AND exported_within_24h = 1 AND purchased_within_7d = 1 THEN 1 ELSE 0 END) AS mature_free_activated_purchasers,
  SUM(CASE WHEN seven_day_mature = 1 AND continued_free = 1 AND exported_within_24h = 0 THEN 1 ELSE 0 END) AS mature_free_not_activated,
  SUM(CASE WHEN seven_day_mature = 1 AND continued_free = 1 AND exported_within_24h = 0 AND purchased_within_7d = 1 THEN 1 ELSE 0 END) AS mature_free_not_activated_purchasers
FROM flags
GROUP BY platform, app_version, variant_id
ORDER BY platform, app_version, variant_id;
