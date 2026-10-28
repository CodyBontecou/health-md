# Health.md SEO priorities after the October content releases

Audited October 27, 2026. Scope: current public site, repository source, existing authenticated Search Console exports, publication receipts, and prior backlink research. This supersedes unfinished recommendations in the October 25–26 plans where current production proves the work is already shipped. Audit and planning only; no production, analytics, product, or outreach changes.

## Recommendation

Health.md already has the foundation of Vaultaire's approach: task-oriented guides, commercial comparison, useful samples, a browser utility, internal links and product actions. The next step is to improve a few existing pages, make their outcomes tangible, distribute the existing resources, and choose subsequent topics from page/query evidence.

Start with **CLI search positioning and a working spreadsheet resource**, while collecting a clean postlaunch baseline. Correct conflicting sleep-date copy as a small trust/accuracy repair. Do not commission another general export, CSV, Excel, Sheets, Mac, AI, or competitor-comparison article that duplicates a live owner.

Priority estimates below reflect observed opportunity, product fit, effort and confidence. They are not traffic forecasts or measured conversion lifts.

## What the data actually says

Source: authenticated Search Console CSV exports retained at `.pi/seo-live-audit-oct26/`, summarized in its `baseline.md` and `.pi/research/healthmd-search-opportunities-2026-10-27.md`.

| Window | Clicks | Impressions | CTR | Average position |
| --- | ---: | ---: | ---: | ---: |
| September 26–October 23, 28 days | 88 | 2,214 | 3.97% | 7.2 |
| August 29–September 25, preceding 28 days | 80 | 1,668 | 4.80% | 7.2 |
| July 26–October 23, 90 days | 169 | 3,912 | 4.32% | 7.3 |

The 28-day query table exposes 40 clicks, 39 from clear brand spellings. Hidden/anonymized queries prevent calculating the full property's brand share. These data end before the October 25–27 content releases and cannot assess their success.

| Existing page | 28-day impressions | Clicks | Average position | Implication |
| --- | ---: | ---: | ---: | --- |
| `/apple-health-export/` | 232 | 3 | 9.92 | Strongest observed non-home acquisition-page exposure; inspect its actual queries before further edits. |
| `/docs/cli/` | 111 | 1 | 6.88 | Existing discoverable owner with a generic title; promising small optimization. |
| Obsidian workflow article | 52 | 2 | 8.15 | Existing intent and newly improved resource; promote and measure. |
| `/docs/android/` | 46 | 0 | 7.33 | Inspect query intent before deciding whether another Android guide is useful. |
| `/apple-health-to-csv/` | 45 | 0 | 9.8 | High product fit; substantial recent improvements need a postlaunch window. |
| `/docs/sleep-date-attribution/` | 44 | 2 | 6.68 | Existing troubleshooting intent; preserve this owner. |

The clearest relevant query is **apple health cli**: 19 impressions, zero clicks, position 5.84 in 28 days; 25 impressions, one click, position 5.88 in 90 days. These remain small counts. Query and page tables are separate aggregations; do not assert that this query lands on `/docs/cli/` until a page/query-filtered view confirms it.

Broad export and Excel query rows often have only two to five impressions. Conversely, zero-click `homehealthmd` impressions appear to have unrelated brand intent. A Vaultaire-style process should filter for relevance rather than blindly targeting the largest zero-click row.

## Current inventory and completed work

Fresh public curl fetches verified the [main sitemap](https://healthmd.app/sitemap.xml) lists **100 URLs**, including 23 articles plus the blog hub, 58 representative chart pages plus their hub, ten home locales, four acquisition hubs and legal/company routes. The [documentation sitemap](https://healthmd.app/sitemap-0.xml) lists **414 URLs**. These are listed URLs, not indexed-page counts. Saved crawl: `.pi/healthmd-seo-audit-oct27/live-audit.json`, `articles.json`, and `sitemap.xml`.

Already live:

- [Export hub](https://healthmd.app/apple-health-export/), [CSV page](https://healthmd.app/apple-health-to-csv/), [Android export](https://healthmd.app/health-connect-export/) and [AI hub](https://healthmd.app/health-data-for-ai/).
- Sleep, steps, workouts, heart rate, HRV, PDF, Excel, Sheets, Claude, ChatGPT and without-cloud workflows.
- [Obsidian starter vault](https://healthmd.app/blog/export-apple-health-data-to-obsidian/#starter-vault), with 28 fictional daily notes and a result preview.
- [Embedded CSV combiner](https://healthmd.app/apple-health-to-csv/#combine-csv-files), with contextual links from the guides hub and Excel/Sheets articles.
- [Health Auto Export comparison](https://healthmd.app/blog/health-md-vs-health-auto-export/), [XML archive guide](https://healthmd.app/blog/apple-health-xml-export/) and refreshed [Mac workflow](https://healthmd.app/blog/health-md-for-macos/).
- Descriptive homepage metadata across ten locales, article author/dates/breadcrumbs, visualization canonical consolidation, sitemap submissions and known legacy-URL repairs.
- Production aggregate page/action counters, verified by the rollout receipt under `.pi/seo-funnel-analytics/pr250-rollout/`.

Earlier comparison draft status and initial unactivated analytics receipt are stale. Current production and later rollout receipts take precedence. Search extraction also returned an old blog index and CSV body; fresh HTTP proved the current guides directory and CSV utility are deployed.

## Highest-impact backlog

### 0. Use the source that actually produced production

This checkout has 11 blog Markdown sources, while production has 23 articles. Its HEAD is `d185de4b53198fd91012b0c044656e2a7bd67421`; the inspected `origin/main` ref is `a8a260a21897108caaa434195d66990e67c281ac`. Neither reading this directory nor trusting old planning notes alone represents the live inventory. There are substantial unrelated local changes.

Before implementation, locate the published source revision/check-out from deployment evidence, compare it with the live inventory, and preserve unrelated work. Do not deploy a rebuild of the current checkout as a shortcut. Done: the selected implementation source reproduces all 23 articles, the combiner, comparison, samples and current canonical behavior. No reset, checkout replacement, fetch, merge or deployment was performed in this audit.

### 1. Improve the existing CLI owner for explicit search intent

**Confidence:** strongest measured query signal, low volume. **Effort:** roughly half a focused day after source reconciliation and claim verification.

The live [CLI page](https://healthmd.app/docs/cli/) has the generic title/H1 `Health.md CLI`, although it already contains installation, platform boundaries and commands. Suggested title: **Apple Health CLI and Health Connect CLI | Health.md**. Suggested H1: **Health.md CLI for Apple Health and Health Connect**.

First inspect query-to-page mappings. If another CLI guide receives the query, clarify ownership and useful links between the existing pages rather than adding a new generic CLI landing page. Keep the current preview qualification and iPhone/Android differences immediately visible. Put the verified install/first-result path near the top, with one useful output example and links to exact installation/command documentation. Do not imply stable physical-device qualification or Android typed-query parity.

Acceptance: correct current release requirements, accurate title/description/H1, useful first result, relevant contextual links from the AI hub and existing agent articles, and page/query evidence recorded. Success measures: relevant non-brand clicks and task actions over a sufficient window; no promise of a CTR lift.

Implementation surface: `apps/website/docs-src/src/content/docs/cli.md` and existing linking articles; inspect current source and localization requirements before edits.

### 2. Give Excel and Sheets readers a finished result they can inspect

**Confidence:** high product fit and directly observed resource gap; limited measured demand. **Effort:** roughly one to two focused days including workbook verification.

The live [Excel guide](https://healthmd.app/blog/apple-health-to-excel/) and [Sheets guide](https://healthmd.app/blog/apple-health-to-google-sheets/) contain detailed procedures and link the single-day sample and new combiner. Neither has a result screenshot or a downloadable `.xlsx` workbook. A single day can verify import but cannot demonstrate a useful multi-day trend.

Create one reusable pack: 28 explicitly fictional daily input files, a verified workbook with raw data and separate steps/sleep views, an explanation of missing days/units, and a screenshot of the finished result. Include a no-sign-in `.xlsx` download and copyable Sheets instructions; validate imports and formulas rather than assuming cross-tool compatibility. Keep the existing guides and CSV page as owners.

Place an inspectable result and the download near the first worked example. Link it to trying the combiner, then exporting one day of the reader's own data. Do not require uploads of personal health records to try the example. Acceptance: the downloadable inputs reproduce the workbook's numbers and chart, missing values remain missing, and refresh/import steps work in named supported spreadsheet versions.

This is Health.md's clearest next counterpart to Vaultaire's useful-resource strategy. Do not build a generic new image/QR/converter tool while this closely related workflow remains unfinished.

### 3. Repair sleep-date contradictions, then improve first-export proof

**Confidence:** directly observed accuracy defect and visual gap; no measured ranking impact. **Effort:** small copy repair, then roughly a day for authentic captures.

The sleep guide's procedure correctly gives a noon-to-noon example: Tuesday 01:00–07:30 belongs to Monday's daily journal. Its FAQ simultaneously says the session belongs to the day it started. The Android export hub and broad Apple export hub also use start-day wording. The [sleep-date explainer](https://healthmd.app/blog/why-sleep-is-in-yesterdays-note/) and [troubleshooting page](https://healthmd.app/docs/troubleshooting/) describe the noon-to-noon behavior.

Align all summary guidance with the verified current behavior and distinguish daily summaries from raw-record ownership. Preserve the existing sleep-date owner URL. Search and replace alone is insufficient because raw records may follow different rules. No export implementation or public schema change is requested.

The CSV page's only app screenshot explicitly shows CSV disabled. The sleep page's screenshot likewise depicts selection rather than the complete successful outcome. Replace or supplement these with authentic current captures: enabled selection → preview → written result → opened file. Acceptance: a beginner can recognize the correct switches and find the output, and all claims match the shipping version. Do not fabricate screenshots or use private health data.

### 4. Make the homepage's first message and navigation match its metadata

**Confidence:** observable clarity gap; conversion effect unmeasured. **Effort:** roughly half to one day, including ten locale updates.

The homepage title is now `Export Apple Health and Health Connect | Health.md`; the visible H1 remains `Move your health forward`. Its navigation contains Docs but no direct Guides entry. Contextual export/CSV/Obsidian/Android links already exist, so this is refinement rather than rebuilding navigation.

Proposed visible headline: **Export your health data to files you control.** Follow immediately with Apple Health and Health Connect, supported formats, and appropriate platform actions. Add a visible Guides/Exports entry to the existing workflow directory. Preserve store actions and existing social proof. Do not insert more product categories, competing hero buttons or schema solely for SEO.

Acceptance: a first-time visitor understands source, outcome and next step without scrolling; ten home catalogs stay synchronized. Do not claim the old H1 was preventing indexing.

### 5. Distribute the resources that are already useful

**Confidence:** clear unexecuted distribution opportunity; search impact unmeasured. **Effort:** roughly one to two days to prepare specific demonstrations.

The [October 26 backlink audit](2026-10-26-healthmd-backlink-audit.md) inspected 20 visible referring rows, all unrelated/link-selling patterns. This biased sample does not establish the whole profile's quality, a penalty, or who created the links. The number of referring domains is not evidence of relevant editorial trust.

Prepare three specific assets using the live resources: selected-data export demonstration, fictional Obsidian weekly review, and iPhone-to-Mac automation walkthrough. Revalidate the existing [editorial prospect research](2026-10-26-healthmd-outreach-prospects.md), including TidBITS, The Sweet Setup and MacStories. Link the useful task page rather than automatically linking the homepage.

Outreach sending requires explicit user authorization. No messages were sent. Measure relevant visits, resource actions and qualified product outcomes; do not buy ranking links or make a DR target the goal.

## Build the missing editorial feedback loop

The next measurement task is to export page-filtered queries for export, CLI, CSV, Obsidian and Android, split by useful country/device context. Keep exact date ranges, old/new page copies, publication dates, links added and intended action. Aggregate page and query tables do not supply this mapping.

Reuse the deployed counter system. Its six page views and five actions on October 27 are explicitly retained QA interactions; exclude them from organic interpretation. Counts are activations, not unique visitors, successful downloads, installs or paid customers. The combiner currently has no dedicated completion event. If that experiment needs measurement, consider one aggregate, allowlisted completion action using the existing privacy gate; collect no filenames, file content, metric values or row counts. Inspect deployed source before adding anything.

A zero-click query at a poor position is not automatically a bad title. First check intent, the receiving URL, actual result competitors, and whether improving an existing page answers the task. Create a new article only for a meaningfully different, supported outcome.

Suggested review windows for October 25–27 changes: discovery on **November 8–10**, 28-day search/action trends on **November 22–24**, and 56-day trends on **December 20–22**. These are review dates, not created automations or guaranteed indexing times. Current low totals make statistical conversion tests premature.

## Defer until evidence supports expansion

- Further metric articles, a second generic Mac/CLI/export page, or another competitor comparison. Measure the existing owners first.
- Translating the whole acquisition library into 32 languages. Health.md already supports ten home/docs locales; choose one valuable task and one evidence-supported locale when the English workflow works. Country totals alone do not identify language or non-brand intent.
- A new Android-to-Sheets page unless current Android queries reveal that distinct need. The Android hub and Obsidian guide already exist; preserve source/permission/export differences.
- Blanket removal of noindex/canonicals, more visualization variants in the sitemap, or requests to index every generated fixture. Existing excluded URLs include deliberate machine-readable and duplicate surfaces.
- Another schema/metadata cleanup pass without a diagnosed defect. Recent author/date/breadcrumb and homepage metadata changes are already live.

## Sequence and definition of success

1. Reconcile implementation source and capture page/query baselines; make the small sleep-copy repair.
2. Improve CLI positioning and useful first result against current release evidence.
3. Build and verify the spreadsheet resource; add genuine first-export proof on existing pages.
4. Clarify homepage body/navigation and prepare resource-specific editorial demonstrations.
5. Review postlaunch discovery and qualified actions before choosing the next article or locale.

The goal is more relevant non-brand discovery and more readers reaching a useful first export. Keep Search Console clicks, website views, resource activations, store clicks, supported install attribution and purchases distinct. This audit does not establish expected traffic gains, SEO-attributed revenue, Core Web Vitals performance or current Google-selected canonicals across the site.

## Verification and retained evidence

Fresh public HTTP inspected all 23 articles, the blog hub, four acquisition hubs, homepage, CLI, scheduling and troubleshooting, plus both sitemaps. Parsed titles, headings, links, images and sample/download destinations are retained in ignored `.pi/healthmd-seo-audit-oct27/`. Two guessed routes returned 404; they were not linked-site defects and are excluded from recommendations. The correct live comparison route is `/blog/health-md-vs-health-auto-export/`.

Private search evidence remains ignored under `.pi/seo-live-audit-oct26/`; raw queries were not copied wholesale into this report. Publication receipts and research notes were checked to avoid recommending completed work. No source/product edits, builds, deployments, device access, personal health-data access or outbound messages occurred. Only this report and compact ignored research evidence were added; no task worktree or temporary build artifacts were created.
