# Health.md short-form attribution on Cloudflare

This repo is set up for first-party campaign shortlinks on Cloudflare:

```text
https://healthmd.app/v/<platform>-<angle>-<sequence>
```

Example:

```text
https://healthmd.app/v/tt-obsidian-001
```

The Cloudflare Worker in `cloudflare/attribution-worker` logs a privacy-light click event, optionally stores it in D1, and picks a destination from the visitor's operating system:

- iOS, iPadOS, and macOS → Apple App Store with `pt`, `ct`, and angle-specific `ppid` parameters
- Android → Google Play with a campaign-bearing Install Referrer
- Other desktop/unknown clients → the Health.md download page with UTM parameters

## What gets redirected

```text
/v/tt-obsidian-001 -> campaign token tt_obsidian_001
/v/ig-privacy-001  -> campaign token ig_privacy_001
/v/yt-csv-001      -> campaign token yt_csv_001
```

The shortlink stays the same across operating systems; only its destination changes.

Slug convention:

```text
<platform>-<angle>-<sequence>
```

Platforms:

- `tt` = TikTok
- `ig` = Instagram Reels
- `yt` = YouTube Shorts
- `x` = X/Twitter
- `th` = Threads

Angles:

- `obsidian` = Obsidian Daily Notes / Markdown output
- `privacy` = private, no cloud, no account
- `csv` = CSV + JSON + Apple Health export pain

## Generate the starter link sheet

```bash
npm run campaigns:list
```

With production tokens locally:

```bash
APPLE_PROVIDER_TOKEN="123456" \
CPP_OBSIDIAN_PPID="<obsidian-custom-product-page-id>" \
CPP_PRIVACY_PPID="<privacy-custom-product-page-id>" \
CPP_CSV_PPID="<csv-custom-product-page-id>" \
npm run campaigns:list
```

The output is CSV with:

```text
shortlink,campaign_token,platform,angle,app_store_url,play_store_url,desktop_url
```

## Cloudflare deployment

Worker project:

```text
cloudflare/attribution-worker
```

It is already deployed to workers.dev for staging:

```text
https://healthmd-campaign-redirects.costream.workers.dev
```

Redeploy with:

```bash
cd cloudflare/attribution-worker
npx wrangler deploy
```

Production routes are active in `wrangler.toml`:

```toml
routes = [
  { pattern = "healthmd.app/v/*", zone_name = "healthmd.app" },
  { pattern = "www.healthmd.app/v/*", zone_name = "healthmd.app" }
]
```

Redeploy route/config changes with:

```bash
npx wrangler deploy
```

## D1 click storage

Persistent click storage is already created and bound:

```text
D1 database: healthmd-campaigns
Database ID: 48311da9-95d1-4343-9c21-5617bd08ca62
Binding: DB
```

Schema migrations `0001_campaign_clicks.sql` and `0002_campaign_installs.sql` are applied. The Worker only inserts click rows for real `GET` redirects, not `HEAD`/link-preview checks. Android install events are stored separately in `campaign_installs`; the schema deliberately has no raw referrer, IP, User-Agent, request ID, device model, account, health-data, export, or path columns.

Query click counts:

```bash
npx wrangler d1 execute healthmd-campaigns --remote --command '
  SELECT campaign_token, COUNT(*) AS clicks
  FROM campaign_clicks
  GROUP BY campaign_token
  ORDER BY clicks DESC;
'
```

## Android install ingestion

The same Worker exposes the production first-party endpoint:

```text
POST https://healthmd.app/v1/installs
```

The Android Gradle base URL is therefore:

```text
CAMPAIGN_ATTRIBUTION_ENDPOINT_URL=https://healthmd.app
```

The Android client appends `/v1/installs`. The endpoint validates an exact allowlisted schema, rejects unknown/sensitive fields and bodies over 4 KiB, enforces the campaign token/source/content relationship, and accepts only Android UUIDv4 install/event IDs. `event_id` and `install_id` are unique. Exact event retries return HTTP 200, new events return 202, conflicting ID reuse returns 409, and transient service/rate failures return 503/429.

A D1 aggregate fixed-window limit allows 300 authorized ingestion attempts per minute without storing IP addresses or other request metadata. Ingestion fails closed if no token secret is configured. A daily cron deletes rate windows after 24 hours and campaign click/install rows after 13 months; retention failures fail the cron invocation and emit only a generic error, never event data.

Aggregate clicks and attributed installs:

```bash
npx wrangler d1 execute healthmd-campaigns --remote --command '
  SELECT campaign_token, redirect_clicks, attributed_installs
  FROM campaign_attribution_summary
  ORDER BY attributed_installs DESC, redirect_clicks DESC;
'
```

## Cloudflare environment variables

Set these on the Worker. `APPLE_PROVIDER_TOKEN` is the most important Apple value; `CAMPAIGN_ATTRIBUTION_INGEST_TOKEN` is the optional Android abuse-throttling token.

```bash
cd cloudflare/attribution-worker
npx wrangler secret put APPLE_PROVIDER_TOKEN
npx wrangler secret put CPP_OBSIDIAN_PPID
npx wrangler secret put CPP_PRIVACY_PPID
npx wrangler secret put CPP_CSV_PPID
npx wrangler secret put CAMPAIGN_ATTRIBUTION_INGEST_TOKEN
# During rotation only: put the prior value here before replacing the current token.
npx wrangler secret put CAMPAIGN_ATTRIBUTION_INGEST_TOKEN_PREVIOUS
```

| Variable | Purpose |
|---|---|
| `APPLE_PROVIDER_TOKEN` | Apple `pt` value. Without this, App Store campaign attribution will be incomplete. |
| `CPP_OBSIDIAN_PPID` | App Store Custom Product Page ID for Obsidian/Markdown videos. Current: `bd4b8175-a84b-452b-b285-bc5f3bb1616e`. |
| `CPP_PRIVACY_PPID` | App Store Custom Product Page ID for privacy/no-cloud videos. Current: `30372d42-d91b-40e3-a1f5-729f709310f2`. |
| `CPP_CSV_PPID` | App Store Custom Product Page ID for CSV/data export videos. Current: `78f247b8-a30a-4665-a45f-e8c1199c77f2`. |
| `CAMPAIGN_ATTRIBUTION_INGEST_TOKEN` | Required-in-production, extractable Bearer token for coarse Android ingest abuse throttling. It is not a true secret or an authentication boundary. |
| `CAMPAIGN_ATTRIBUTION_INGEST_TOKEN_PREVIOUS` | Optional previous token accepted during a rotation overlap. Remove it only after released clients have moved to the new token. |
| `APP_STORE_BASE_URL` | Apple destination, already set in `wrangler.toml`. |
| `PLAY_STORE_BASE_URL` | Android destination, already set to package `com.healthmd.android` in `wrangler.toml`. |
| `DOWNLOAD_PAGE_URL` | Desktop/unknown fallback, already set to the Health.md homepage in `wrangler.toml`. |

## Domain bought on Vercel, DNS on Cloudflare

Vercel can remain the registrar. Cloudflare can run DNS/proxy/Workers.

Manual steps:

1. Cloudflare dashboard → **Add a site** → `healthmd.app`.
2. Choose the Free plan unless you need paid features.
3. Cloudflare will show two nameservers.
4. Vercel dashboard → Domains → `healthmd.app` → Nameservers/custom nameservers.
5. Replace Vercel's nameservers with the two Cloudflare nameservers.
6. Wait for Cloudflare to mark the zone active.
7. In Cloudflare DNS, keep your existing website records pointing wherever the main site is hosted.
8. Deploy the Worker route for `healthmd.app/v/*`.

If the main website stays hosted on Vercel, Cloudflare DNS can still point the apex/root to Vercel while the Worker intercepts `/v/*`.

## Manual App Store Connect steps

1. **Get the provider token**
   - App Store Connect → Apps → Health.md → Analytics → Acquisition → Campaigns.
   - Create/copy any campaign link.
   - Copy the `pt=` value into Cloudflare as `APPLE_PROVIDER_TOKEN`.

2. **Create the three Custom Product Pages**
   - Obsidian page: screenshots/video showing Markdown output, Daily Note Injection, Obsidian/Bases workflow.
   - Privacy page: no account, no Health.md cloud, local files.
   - CSV page: CSV/JSON/Markdown output and “Apple Health export is unusable XML” pain.
   - Copy each page’s `ppid=` value into the matching Cloudflare secret.

Created Custom Product Pages for this sprint:

```text
Health.md — Obsidian
ppid=bd4b8175-a84b-452b-b285-bc5f3bb1616e
version=178a235e-529d-44a1-8d1a-019bbcf45fc3
localization=ef47edb1-c30c-4f6b-9ad2-5bada30ed708
iphone_67_screenshot_set=12f4f4f5-e097-4f18-a3c9-006c94c8dba6
iphone_65_screenshot_set=868d9be2-aa3d-4151-82b5-7ff4eece4e66
screenshots=health-md-app-store-01-daily-notes.png, health-md-app-store-02-markdown-format.png, health-md-app-store-03-export-vault.png
assigned_search_keywords=obsidian, markdown, notes, log

Health.md — Privacy
ppid=30372d42-d91b-40e3-a1f5-729f709310f2
version=e8817adc-cdd8-4639-b3da-dfcbe772d41e
localization=3d80a8ba-5752-41aa-8113-de12861c9067
iphone_67_screenshot_set=372eb136-8a50-4a49-905e-1de815934c83
iphone_65_screenshot_set=748e4c1f-1109-4182-8263-48d2004d9ea6
screenshots=health-md-privacy-01.png, health-md-privacy-02.png, health-md-privacy-03.png
assigned_search_keywords=wellness, tracker, apple, metrics

Health.md — CSV Export
ppid=78f247b8-a30a-4665-a45f-e8c1199c77f2
version=40a0066b-d70e-4a67-b9ca-5bdc4d970096
localization=b53d819b-a344-4c66-abc9-997032a4db8b
iphone_67_screenshot_set=c8632716-3e9b-4aee-9e6f-7a63751daaf0
iphone_65_screenshot_set=7db46c85-efa2-4f22-8344-6fcf230b5263
screenshots=healthmd-csv-export-01.png, healthmd-csv-export-02.png, healthmd-csv-export-03.png
assigned_search_keywords=apple, metrics, tracker, log
```

These versions were created from the live iOS 2.4 product page template and are currently in `PREPARE_FOR_SUBMISSION` until submitted/approved in App Store Connect.

Pre-existing Custom Product Page:

```text
Ads Exploration
ppid=e9f90675-b5b1-4813-9e44-004cd1c84f90
```

## Test after deploy

Use explicit user agents so each operating-system branch is covered:

```bash
# iOS → App Store
curl -I -A 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X)' \
  https://healthmd.app/v/tt-obsidian-001

# Android → Google Play
curl -I -A 'Mozilla/5.0 (Linux; Android 14; Pixel 7)' \
  https://healthmd.app/v/tt-obsidian-001

# Other desktop → Health.md download page
curl -I -A 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)' \
  https://healthmd.app/v/tt-obsidian-001
```

Expected iOS result: `302` to `apps.apple.com` with `pt`, `ct=tt_obsidian_001`, `mt=8`, and the angle-specific `ppid`.

Expected Android result: `302` to `play.google.com` with package `com.healthmd.android` and a URL-encoded `referrer` containing `utm_campaign=tt_obsidian_001`.

Expected desktop result: `302` to `healthmd.app/` with `utm_campaign=tt_obsidian_001`.

Apple campaign data may not appear until at least 24 hours have passed and the campaign has enough first-time downloads to satisfy Apple's privacy threshold.
