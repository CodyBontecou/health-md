# SEO measurement

The acquisition guides need a Search Console baseline before further content or
visualization canonical changes. This repository contains the reporting tool,
not a live traffic baseline. No Search Console property or traffic result has
been verified by adding this tool.

## Capture a baseline

Run from `apps/website` with Node.js 22 or later. Obtain an OAuth access token
for the Google account with access to the existing Search Console property,
using the `https://www.googleapis.com/auth/webmasters.readonly` scope. Supply it
as `GSC_ACCESS_TOKEN` through your local secret environment. Do not commit the
token or place it in command arguments, reports, screenshots or chat.

```bash
npm run seo:baseline -- --list-properties
```

Select the exact `siteUrl` from the returned list. Do not infer whether the
existing verified property is a Domain property, www URL or non-www URL.
This command reads accessible properties; it does not create or verify one.

Choose an explicit end date with finalized data in Search Console, usually at
least several days behind today. Dates are inclusive Pacific Time dates. The
tool requests finalized web-search data, but does not prove that every date
has data. Check the selected date in Search Console before interpreting results.

Create the private parent directory first. Use a fresh output directory for
each capture; the tool refuses to overwrite an existing snapshot or write into
`apps/website`, including through a parent-directory symlink.

```bash
mkdir -p ../../.pi/seo-baselines
npm run seo:baseline -- \
  --property 'EXACT_SITE_URL_FROM_LIST' \
  --end-date 2026-10-20 \
  --output ../../.pi/seo-baselines/2026-10-20
```

The date above is an example, not a claim of available production data. The
command saves `snapshot.json` and `summary.md` after all API calls succeed. Use
a private, ignored directory; search queries can be sensitive. Neither output
belongs in public assets, a PR, or the deployed website. No new tracking service,
browser event, health-data collection or scheduled job is installed.

## Read the snapshot

Four windows cover the latest selected 28 and 90 days and each immediately
preceding equal-length period. Each retains separate property totals, page,
query, country, device and page/query tables. Use page/query rows to identify
which existing guide receives a query before proposing another URL. Classify
returned queries as branded/non-brand and group relevant intents during review;
hidden or omitted queries remain unknown.

The summary shows comparable property totals and current 28-day landing pages.
Search CTR is clicks divided by impressions. Property totals are requested
independently; they are not a sum of page/query rows. Keep the API's returned
aggregation type when comparing position or impressions. Missing rows and
zero-denominator CTR are unavailable, not inferred zeroes.

Pagination retains up to 50,000 returned rows per table per window, then probes
for additional rows and records `truncated`. Even an untruncated table is not an
exhaustive export: Google can omit queries and pages, and API limits still apply.
This is a grouped baseline, not Google's recommended daily bulk extraction.
If detail exceeds the cap or longitudinal analysis needs greater coverage,
use a separate daily export rather than interpreting the top rows as all traffic.

For each website deployment, record the changed URLs, query intent, date and
intended action in private measurement notes. Review discovery after 14 days and
search/conversion trends after 28 and 56 days. Annotate campaigns, releases and
pricing changes. Low CTR at a low position alone does not establish a title defect.

Search clicks, visits, store clicks, attributed installs and paid outcomes are
different measures. Store CTR needs store clicks divided by relevant landing
visits; Search Console cannot supply that calculation. See [ATTRIBUTION.md](ATTRIBUTION.md)
for the separate campaign infrastructure. This tool does not verify its production
tokens or install reporting. Index coverage and Google-selected canonicals also
require a separate Search Console inspection before visualization consolidation.

## Website action counters

The existing analytics gate loads `assets/seo-funnel.js` only when it explicitly
returns `track: true`. A failed/denied gate, preview host, Do Not Track, or Global
Privacy Control disables collection. Downloads and store navigation always use
their original links; analytics never waits, retries, or prevents navigation.

`assets/funnel-contract.js` owns the fixed page, locale, action, target, placement,
and source vocabulary shared by the browser and campaign Worker. It currently
covers the homepage (all ten locales), export/CSV/Android/AI hubs, the guides hub,
Obsidian workflows, the Health Auto Export comparison, the XML archive explainer,
the Mac destination walkthrough, and the named spreadsheet, metric, PDF, and AI acquisition
guides. Other pages, including account and health-data routes, are excluded.
Add genuine acquisition pages to that owner rather than sending arbitrary URLs.

The events are:

- `page_view`: one per tracked document after the gate permits analytics.
- `csv_sample_download`: activation of an allowlisted CSV sample link.
- `starter_vault_download`: activation of the public starter ZIP link.
- `store_click`: activation of a Health.md App Store, Google Play, or F-Droid link.

Each event contains only version, page ID, locale, action, target ID, placement
(`hero`, `body`, `header`, `footer`, or `final`), and an immediate-referrer category.
`search_referral` means a recognized search hostname, not verified organic traffic;
tagged campaigns use `campaign`. Internal navigation uses `internal` and does not
inherit a prior acquisition source. No cookies, browser storage, visitor/session
IDs, health data, link text, file contents, raw referrers, query strings, or URL paths
are transmitted. Fetch omits credentials and the Referer header. Normal network
delivery still exposes ordinary connection metadata to the infrastructure.

`POST /v1/web-events` is served by the existing attribution Worker. It requires a
same-origin production request, rejects extra fields and bodies over 1 KiB, and
honors DNT/GPC headers. It increments daily UTC counters in `web_funnel_daily`,
without per-event rows, client timestamps, or request metadata. The existing daily
cron removes counters at the 13-month cutoff and rate windows after 24 hours.
A separate aggregate limit permits 600 valid attempts per minute; each document
sends at most 100 events. Invalid/failed requests never affect download behavior.

This is a public, best-effort measurement endpoint, not authenticated evidence.
Same-origin headers and throttling reduce accidental/drive-by abuse but can be
spoofed by non-browser clients. Blocking, a slow gate, navigation, offline operation,
and rate limits can cause undercounts. Repeated clicks count repeatedly. Counts
are not unique users, completed downloads, installs, purchases, or a linked journey
from sample to store. Do not use these counters for billing or security decisions.

### Read the funnel

From `apps/website`, with Wrangler signed in to the owning Cloudflare account:

```bash
npm run seo:funnel -- --remote --days 28
```

The JSON report groups by page, locale, and source and includes views, both
download actions, clicks by store, and actions per 100 page views. A missing
denominator produces `null`, not zero. Repeated actions can produce a rate above
100. Dates include today and the preceding 27 UTC calendar days; use `--days 1`
for today or up to 90 days. `--local` explicitly selects a local D1 database.
Search Console supplies the separate query/impression/click side of the funnel;
these anonymous counters cannot join individual search clicks or store installs.

For CTA placement detail, use the existing owner's authenticated D1 tooling:

```bash
cd cloudflare/attribution-worker
wrangler d1 execute healthmd-campaigns --remote --command "SELECT page, action, target, placement, SUM(count) AS actions FROM web_funnel_daily WHERE day >= date('now', '-27 days') GROUP BY page, action, target, placement ORDER BY actions DESC"
```

### Rollout order

Deploy only reviewed, committed source. The collector and migration must precede
the website so that the browser can reach the endpoint:

```bash
cd apps/website/cloudflare/attribution-worker
wrangler d1 migrations apply healthmd-campaigns --remote
wrangler deploy
```

Then publish the website through its normal main-branch deployment. Migration
`0003_web_funnel.sql` is additive and preserves existing campaign/install data.
It must be present before the new cron handler runs. Check the authenticated report
and actual HTTP responses before calling collection operational; adding source
alone does not establish a live collector or baseline. Avoid synthetic production
events: verify valid collection locally, and use rejected payloads/privacy-signal
requests for production smoke checks without incrementing counters.

## Visualization canonical URLs

Each chart uses its existing category plus `theme-colors` route as the search
representative. Palette and all-data preview routes retain their exact share URLs,
rendering and copyable blocks. Their HTML canonical and structured-data URL point
to the representative; the customizer keeps that canonical when the palette or
data filter changes. Only representatives appear in the visualization sitemap block.
No variant is redirected, blocked in robots.txt or given a `noindex` directive.

Visualization `lastmod` is omitted until a reliable per-page source modification
date is available. Do not substitute the build date. Before changing representative
paths, inspect actual Search Console page performance and sampled Google-selected
canonicals; preserve relevant existing paths. Canonical declarations are preferences,
and neither index selection nor improved traffic is guaranteed.

After generator changes, run `npm run visualizations:seo:source` to synchronize
the checked-in previews and sitemap, then `npm test` and `npm run build:ci`.
The regression test checks every generated variant, sitemap membership, source
artifact parity and the customizer's canonical versus share URL behavior.

## API references

- [Accessible sites and permission levels](https://developers.google.com/webmaster-tools/v1/sites/list)
- [Search Analytics requests, dimensions and pagination](https://developers.google.com/webmaster-tools/v1/searchanalytics/query)
- [Data limitations and daily extraction guidance](https://developers.google.com/webmaster-tools/v1/how-tos/all-your-data)

- [Google canonical consolidation guidance](https://developers.google.com/search/docs/crawling-indexing/consolidate-duplicate-urls)

## Local CSV combiner

The existing CSV acquisition page embeds a free combiner at
`/apple-health-to-csv/#combine-csv-files`. Its engine and limits are owned by
`assets/csv-combiner-core.js`; the controller is `assets/csv-combiner.js`.
It reads explicitly selected files in the tab and creates a Blob download.
No endpoint, browser storage, file upload, or third-party parser is involved.

This is an append utility for the existing Health.md CSV header, including
five-field rows with omitted Timestamp. It preserves cell strings, row shape,
metadata and duplicates. It does not normalize schemas/units, reconcile sources,
sort dates, deduplicate records or calculate health statistics. Formula-like
fields and malformed/oversized inputs fail without creating a partial download.
The page explains the supported scope and directs users to retain their originals.

Selected filenames, contents and row/file counts must remain outside analytics.
Generated Blob links are deliberately excluded by the existing HTTPS destination
allowlist; do not treat user-file downloads as synthetic sample downloads.
The existing page view, public sample, and store counters remain the acquisition
measurements. Clear releases the controller's object URL and selection; it does
not delete files saved by the user. The demo is explicitly fictional.

`test/csv-combiner.test.mjs` round-trips the existing Apple daily fixtures and
Android excerpt and covers resource limits, quoted/multiline fields, cancellation,
errors, URL cleanup, formula prefixes and the absence of network/storage sinks.

## IndexNow change notifications

`npm run seo:indexnow -- https://healthmd.app/path/` performs a live preflight
without sending a notification. After deploying a meaningful page update, add
`--submit` to notify participating engines through the global IndexNow endpoint.
Supply only the exact canonical URLs that recently changed, up to 100 per run.
Do not submit the entire sitemap, unchanged pages, query variants, Markdown
alternatives, samples or private content. This command intentionally supports
live indexable HTML updates only; removals and redirects require separate review.

The committed `indexnow-key.txt` is a publicly served domain-verification token,
not a private credential. The static build copies it to the site root. Each run
requires the live key to match, HTTP 200 HTML, exactly one matching canonical,
no noindex directive, and the current allow-all robots policy. Redirects fail.
The command rejects foreign hosts, credentials, query strings and fragments;
it sends nothing unless every preflight passes and `--submit` is explicit.

Save the command output with deployment evidence in ignored `.pi/` state.
HTTP 200 means received; 202 means received with key validation pending.
Neither proves crawling, indexing or ranking. Errors are not automatically
retried; investigate before resubmitting. Keep the existing Google sitemap
workflow and use Search Console or engine webmaster tools to assess indexing.
This notification is a server-side operator action, with no browser script,
visitor data or health data. See the [protocol](https://www.indexnow.org/documentation)
and [submission guidance](https://www.indexnow.org/faq).
