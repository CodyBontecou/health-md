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

- random pseudonymous app-install UUID
- event name
- experiment/variant IDs
- app/build/platform
- paywall context
- coarse onboarding step and explicit Health/folder skip milestones
- free-export counts
- export target type, including API endpoint exports
- coarse metric/date buckets
- product ID
- purchase/restore outcome
- authorization/error category

Onboarding step values are platform-coarse: seven iPhone steps, the macOS intro steps (`mac_how_it_works`, `mac_iphone_app`, and `mac_connect`), and Android’s welcome/Health/folder/unlock/ready flow. Use the `platform` column when comparing funnels.

Do not add HealthKit values, metric names, health dates, file/vault paths, peer
names, credentials/tokens, user text, exported content, raw IPs, request URLs,
request headers, or User-Agent storage. Analytics is collected automatically and
is not used for advertising or cross-app tracking. Apple builds expose **Settings → Privacy & Analytics** for opt-out and identifier reset; Android discloses its bounded, non-disableable collection during onboarding and in its Health Connect rationale. The full privacy policy covers both.

Validated D1 rows are retained for no more than 13 months. A daily Worker cron
deletes older rows. Cloudflare still
processes ordinary connection information under its own terms, so production
Worker Logs and Logpush settings must be checked separately to ensure request
bodies, raw IPs, and headers are not retained beyond the provider-level minimum.

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

Cross-platform onboarding cohorts by platform, app version, and variant:

```bash
npm run query:onboarding
```

The report uses distinct installs, excludes starts less than 24 hours old, provides a seven-day-mature purchase denominator, and splits free-choice users by 24-hour activation. Android currently emits onboarding and purchase-tap milestones but not export or purchase lifecycle outcomes. Receipt-time windows can be blurred by delayed offline delivery, and activation/purchase differences are descriptive rather than causal.

Baseline/test funnel counts:

```bash
wrangler d1 execute health-md-pricing-analytics --remote --command \
"SELECT
   variant_id,
   COUNT(DISTINCT CASE WHEN event_name IN ('pricing_export_preview_generated','pricing_export_succeeded') THEN install_id END) AS activated_users,
   COUNT(DISTINCT CASE WHEN event_name='pricing_paywall_shown' THEN install_id END) AS paywall_users,
   SUM(CASE WHEN event_name='pricing_paywall_shown' THEN 1 ELSE 0 END) AS paywall_views,
   COUNT(DISTINCT CASE WHEN event_name='pricing_purchase_finished' AND purchase_outcome='succeeded' THEN install_id END) AS successful_purchasers
 FROM pricing_events
 WHERE received_at >= '2026-05-18T00:00:00Z'
   AND received_at <  '2026-06-01T00:00:00Z'
 GROUP BY variant_id;"
```

Use distinct-install columns for conversion. Raw paywall or purchase event counts measure repeat frequency and must not be treated as people.

Use App Store Connect proceeds/refunds separately for `net revenue per activated
user`; D1 provides activation/paywall/purchase event counts only.
