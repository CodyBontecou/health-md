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

## API references

- [Accessible sites and permission levels](https://developers.google.com/webmaster-tools/v1/sites/list)
- [Search Analytics requests, dimensions and pagination](https://developers.google.com/webmaster-tools/v1/searchanalytics/query)
- [Data limitations and daily extraction guidance](https://developers.google.com/webmaster-tools/v1/how-tos/all-your-data)
