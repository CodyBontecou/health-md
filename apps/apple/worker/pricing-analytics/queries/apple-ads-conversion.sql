-- All retained attribution resolutions, not install-date cohorts. Joining by
-- install handles purchases received before delayed attribution. Unknown/no
-- resolution is excluded, never inferred organic. Monetary ROAS needs verified
-- transaction revenue/refunds; this report counts client-reported buyers only.
WITH attribution AS (
  SELECT install_id,
    json_extract(payload_json, '$.properties.appleAdsStatus') AS status,
    json_extract(payload_json, '$.properties.appleAdsCampaignId') AS campaign_id,
    json_extract(payload_json, '$.properties.appleAdsAdGroupId') AS ad_group_id,
    json_extract(payload_json, '$.properties.appleAdsKeywordId') AS keyword_id,
    json_extract(payload_json, '$.properties.appleAdsClaimType') AS claim_type,
    json_extract(payload_json, '$.properties.appleAdsConversionType') AS conversion_type
  FROM pricing_events
  WHERE event_name = 'pricing_apple_ads_attribution_resolved' AND platform = 'ios'
), buyers AS (
  SELECT DISTINCT e.install_id FROM pricing_events e
  JOIN pricing_events started ON started.install_id = e.install_id
    AND started.event_name = 'pricing_apple_ads_attribution_started'
    AND started.platform = 'ios'
    AND e.received_at >= started.received_at
  WHERE e.platform = 'ios' AND e.event_name = 'pricing_purchase_finished'
    AND e.purchase_outcome = 'succeeded'
)
SELECT status, campaign_id, ad_group_id, keyword_id, claim_type, conversion_type,
  COUNT(DISTINCT a.install_id) AS resolved_installs,
  COUNT(DISTINCT b.install_id) AS purchasing_installs,
  ROUND(100.0 * COUNT(DISTINCT b.install_id) / COUNT(DISTINCT a.install_id), 2) AS purchase_conversion_percent
FROM attribution a LEFT JOIN buyers b USING (install_id)
GROUP BY status, campaign_id, ad_group_id, keyword_id, claim_type, conversion_type
ORDER BY purchasing_installs DESC, resolved_installs DESC;
