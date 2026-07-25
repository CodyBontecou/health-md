# Pricing Analytics Worker

Health.md now has a Cloudflare Worker/D1 ingestion path for privacy-safe pricing
analytics. Source lives at `worker/pricing-analytics/`.

- Ingest endpoint: `POST /v1/events`
- Storage: D1 table `pricing_events`
- Query surface: Wrangler CLI (`wrangler d1 execute`)
- UI: none

## App configuration

Deployed endpoint:

```text
https://health-md-pricing-analytics.costream.workers.dev
```

Health.md uses that deployed endpoint as the release fallback. You can override
it per build with:

```bash
PRICING_ANALYTICS_ENDPOINT_URL=https://health-md-pricing-analytics.costream.workers.dev
PRICING_ANALYTICS_INGEST_TOKEN=<optional bearer token matching worker INGEST_TOKEN>
```

`INGEST_TOKEN` is currently unset on the Worker, so the app does not need to
embed a token. If an ingest token is configured later, treat the app-side value
as abuse-throttling, not as a true secret. Analytics failures remain
offline-safe: events are queued in UserDefaults and app flows continue.

## Privacy boundaries

The Worker rejects unknown fields and stores only:

- anonymous install UUID
- event name
- experiment/variant IDs
- app/build/platform
- paywall context
- free-export counts
- export target type
- coarse metric/date buckets
- product ID
- purchase/restore outcome
- authorization/error category

Do not add HealthKit values, metric names, health dates, file/vault paths, peer
names, exported content, raw IPs, or user-agent storage.

## Query examples

Recent events:

```bash
cd worker/pricing-analytics
wrangler d1 execute health-md-pricing-analytics --remote --command \
"SELECT received_at,event_name,variant_id,platform,paywall_context,purchase_outcome
 FROM pricing_events
 ORDER BY received_at DESC
 LIMIT 20;"
```

Baseline/test funnel counts:

```bash
wrangler d1 execute health-md-pricing-analytics --remote --command \
"SELECT
   variant_id,
   COUNT(DISTINCT CASE WHEN event_name IN ('pricing_export_preview_generated','pricing_export_succeeded') THEN install_id END) AS activated_users,
   SUM(CASE WHEN event_name='pricing_paywall_shown' THEN 1 ELSE 0 END) AS paywall_views,
   SUM(CASE WHEN event_name='pricing_purchase_finished' AND purchase_outcome='succeeded' THEN 1 ELSE 0 END) AS successful_purchases
 FROM pricing_events
 WHERE received_at >= '2026-05-18T00:00:00Z'
   AND received_at <  '2026-06-01T00:00:00Z'
 GROUP BY variant_id;"
```

Use App Store Connect proceeds/refunds separately for `net revenue per activated
user`; D1 provides activation/paywall/purchase event counts only.
