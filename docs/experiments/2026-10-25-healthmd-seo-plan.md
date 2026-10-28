# Health.md SEO audit and execution plan

Checked October 25, 2026. Scope: public `healthmd.app`, fresh HTML from representative routes, both public sitemap surfaces, and current `apps/website` sources. This is an implementation plan; no website, analytics, product or deployment changes were made.

## Decision

Apply Vaultaire's query-to-workflow-to-download loop, starting with existing acquisition pages and practical export tutorials. Health.md already has technical documentation, generated examples, an Obsidian walkthrough and ten locale versions. Its main opportunity is to connect those assets to clear beginner tasks and measurable next actions.

Priorities below are editorial judgments based on product fit, existing coverage, effort and distinct reader outcomes. No authenticated Search Console, keyword volume, backlink or conversion dataset was available, so these are not demonstrated high-volume or low-competition opportunities. Reorder after reviewing actual query/page performance.

## Current state and evidence

### Strong assets to reuse

- Three existing acquisition pages own broad Apple export, CSV and AI intent: [export](https://healthmd.app/apple-health-export/), [CSV](https://healthmd.app/apple-health-to-csv/), [AI](https://healthmd.app/health-data-for-ai/). Improve these rather than creating parallel generic pages.
- The [Obsidian workflow](https://healthmd.app/blog/export-apple-health-data-to-obsidian/) and [Android Obsidian workflow](https://healthmd.app/blog/export-health-connect-to-obsidian/) already cover specific destinations.
- First-export docs, format contracts, downloadable synthetic fixtures, sleep-date documentation and platform availability tables provide unusually useful evidence for original guides. [First export](https://healthmd.app/docs/iphone-first-export/), [formats](https://healthmd.app/docs/reference/export-formats/), [platform features](https://healthmd.app/docs/guides/platform-features/).
- Metadata, canonical tags, crawl permissions, generated docs sitemaps and localization machinery already exist. This is not a project to add another schema library or rebuild the site.

### Measured footprint

The fresh main sitemap lists **840 URLs**, including **813 visualization URLs**, ten home locale routes, three acquisition pages, About, two legal pages and eleven blog routes (hub plus ten posts). Its separate docs sitemap lists **414 URLs**, including 81 English docs and 37 in each of nine other locales. Together these two retrieved lists contain 1,254 entries; this is not an indexed-page count. [Main sitemap](https://healthmd.app/sitemap.xml), [docs index](https://healthmd.app/sitemap-index.xml), [docs child](https://healthmd.app/sitemap-0.xml).

The chart generator emits 58 charts × two category paths × seven palettes = 812 chart pages, plus the visualization hub. A sampled [HRV palette variant](https://healthmd.app/visualizations/heart-health/hrv-trend/ocean-colors/) is indexable and self-canonical. The generator sets the same chart title across palettes. This is a concrete duplication/consolidation opportunity; it is not proof of a Google penalty or crawl-budget problem.

### Main gaps

1. The [homepage](https://healthmd.app/) title/H1 lead with “Move your health forward.” Supporting copy explains the product, but the headline could identify data export and supported sources more directly. The top navigation has Docs; the three acquisition pages are mainly footer destinations.
2. The [blog](https://healthmd.app/blog/) presents release notes and workflow ideas in date order. Many posts explain architecture or development. Beginner sleep export, spreadsheet analysis and general Android export have no dedicated acquisition walkthroughs in the audited set.
3. The AI page presents file upload and bundled Mac MCP but omits a clear standalone CLI preview choice. The bundled helper's Mac requirement is legitimate; treating it as the only MCP topology leaves the page incomplete. [Release status](https://healthmd.app/docs/release-status/) must govern preview claims.
4. Public landing pages mostly use direct store links. The repository contains campaign attribution infrastructure, but its presence does not prove the SEO funnel is measured end to end. `assets/analytics.js` loads a gated Cloudflare beacon and does not itself implement a page-to-store custom-event funnel. Inspect operational reporting before adding instrumentation.

### Fresh fetch versus cached search output

Fresh raw HTML confirms the live CSV page already has a synthetic sample, comparison corrections and five free actions. Fresh home/export/CSV/AI HTML also describes the optional single-owner cloud pilot. Older search-tool snapshots showed ten actions or unconditional no-cloud copy. Do not report those cached facts as current production defects or repeat that work. Preserve existing uncommitted CSV, Obsidian and styling changes in the primary checkout. No pending publication is inferred from Git status alone.

## Ranked execution backlog

| Order | Action and URL | Intent and required outcome | Why this order |
| --- | --- | --- | --- |
| 1 | Improve `/apple-health-to-csv/` | A beginner exports one day, opens the exact CSV, understands rows and units | Closest existing page to a clear install task; build on live improvements |
| 2 | Improve `/apple-health-export/` | Choose Apple's native archive or Health.md's selected-date/file workflow | Existing broad acquisition hub; should route all supporting articles |
| 3 | Improve `/` and `/blog/` navigation | Choose spreadsheets, Obsidian, Android or agents without searching docs | Makes the cluster reachable and useful immediately |
| 4 | Improve existing `/blog/export-apple-health-data-to-obsidian/` | Verify one note, then configure daily-note or Bases behavior | Strong product fit and existing material; no duplicate landing URL |
| 5 | Create `/health-connect-export/` | Export Health Connect data to CSV, JSON or Markdown on Android | Real platform-level acquisition gap; reusable existing Android docs |
| 6 | Create `/blog/export-apple-health-sleep-data/` | Select sleep, export, distinguish summaries/stages and find the right date | Narrow task with a close product connection and existing sleep evidence |
| 7 | Create `/blog/apple-health-to-excel/` | Import daily CSVs into a useful workbook and repeat the workflow | Distinct downstream task, provided the article includes an original workbook recipe |
| 8 | Improve `/docs/scheduling/` | Configure and verify a schedule, then recover a blocked run | Addresses known setup friction without making a duplicate schedule article |
| 9 | Improve `/health-data-for-ai/` plus existing query/CLI articles | Choose file upload, bundled Mac helper or standalone preview accurately | Existing content needs consolidation before assistant-specific expansion |
| 10 | Create `/blog/export-apple-health-steps-data/` | Export daily steps and identify summary versus source-record differences | Reuses the metric guide pattern after sleep establishes it |
| 11 | Create `/blog/export-apple-health-data-pdf/` | Preview a descriptive PDF and explicitly save/share it | Documented iPhone/Android capability with a concrete output |
| 12 | Create `/blog/healthmd-vs-health-auto-export/` after testing | Decide between products using dated, evidence-backed workflow differences | Valuable commercial intent, but higher research and maintenance cost |

Orders 1–9 are the first month backlog; 10–12 are conditional follow-ups. Search Console evidence can move a later task forward. Technical consolidation and measurement run alongside the content work.

## First page briefs

### 1. CSV: improve the current page

Keep the URL. Proposed title: **Export Apple Health to CSV for Excel and Google Sheets | Health.md**. Proposed H1: **Export Apple Health to CSV**. “Without Xcode” can remain a supporting clarification; it need not define the primary audience.

Primary action: download Health.md for the first CSV export. Secondary proof: inspect/download the synthetic sample.

Required changes:

- Preserve the existing sample, five-action explanation and fair native/XML/app comparison; do not recreate them.
- Add an authentic, current screenshot showing CSV enabled and a one-day range.
- Give a short import recipe for Excel, Numbers and Sheets, with links to a complete Excel tutorial when published.
- Make summary rows, timestamped rows, canonical JSON-in-CSV rows, units and missing values understandable; do not promise every export is a single flat analysis table.
- Add troubleshooting for an empty range, wrong date, wrong folder, permissions and source synchronization.
- Link the sleep guide, Obsidian walkthrough, export hub and exact format reference.

Acceptance: a new reader can download the sample without installing, identify its fields, follow the first-export steps and locate the saved file. Page title, visible claims and JSON-LD agree.

### 2. Export: make the broad page a useful decision hub

Keep the URL and broad export intent. Proposed H1: **How to export Apple Health data**.

Add a short native Export All Health Data procedure with a current screenshot and official Apple source checked during implementation. Then compare that archive with Health.md's metric/date/format selection. Explain that Health.md reads authorized device data; do not imply it imports or converts Apple's XML unless a tested released feature does that.

Provide a destination table linking CSV/Excel, Obsidian, JSON/scripts, sleep, PDF and AI pages. Include output previews from generated synthetic fixtures. Keep advanced API/Mac details below the beginner workflow. Primary action: try an authorized one-day export. Link Android readers to the new Android hub.

Acceptance: a reader can choose the native archive or a selected-file workflow and reach the correct next guide in one click. This page owns generic export intent; do not publish another generic export article to compete with it.

### 3. Homepage and blog: improve entry paths

Suggested homepage title: **Health.md — Export Apple Health and Health Connect Data**. Suggested hero direction: **Your health data, in files you control**, immediately followed by supported sources and CSV/JSON/Markdown/Obsidian destinations. Preserve honest core/private-pilot boundaries and current platform purchase terms.

Add contextual links inside the existing export, scheduling and agent sections. Add a compact workflow directory: spreadsheets, Obsidian, Android export and agents. Keep platform store actions appropriate to the reader; the page should not force Android visitors toward Apple.

Change the blog's discovery framing to practical health-data guides and product updates. Keep current URLs and chronological posts, but add task groups and a “start here” selection. Link promising articles from relevant body text, not only from a footer. No blog-to-guides route migration or new CMS is needed.

### 4. Obsidian: strengthen the established walkthrough

Keep the current article URL and preserve existing local improvements. Verify the shipped app sequence against the screenshots. Show one output note, a single existing-daily-note update and a working Bases view example. Clearly distinguish enabling Bases export from creating the user's view.

Offer a labeled synthetic note/template with exact supported keys. Place the app action after the first successful note example and at the end. Link from the homepage export section, CSV page, export hub and relevant docs. Link Android readers to the existing Android Obsidian guide.

Acceptance: a reader understands which folder to choose, what file is created, how to find it in Obsidian, and what happens to existing writing on repeat exports.

### 5. Android: create the missing general export page

URL: `/health-connect-export/`. Title/H1: **Export Health Connect data to CSV, JSON and Markdown**.

Cover source app → Health Connect → Health.md → chosen folder; current Android screenshots; one-day preview/export; a genuine synthetic output; permissions/history limitations and empty results. Explain that a wearable must write the relevant data into Health Connect; do not promise every vendor record is present.

Give Google Play and F-Droid their actual distribution/purchase boundaries, and document source/format differences rather than implying Apple-shaped lossless parity. Primary action: install the appropriate Android channel. Link Android docs, Android Obsidian guide, shared format documentation and Apple export alternative.

Acceptance: successful manual export on the qualified Android release, accurate source and channel limitations, body links from home/export/Android docs. Register the new static route in the build and sitemap pipeline.

### 6. Sleep: first new metric guide

URL: `/blog/export-apple-health-sleep-data/`. Title/H1: **How to export Apple Health sleep data**.

Answer the task immediately, then show metric selection, date selection, preview and export. Use actual generated synthetic sleep output. Explain nightly summary versus stages versus source sessions, the start-day attribution rule, late device synchronization and absent data. Link existing sleep-date docs and the existing “yesterday's note” article instead of repeating their entire contents. No diagnosis or stage-quality interpretation.

Primary action: export a small sleep range. Inbound links: CSV page, export hub and sleep-date article. Outbound links: CSV, sleep reference, scheduling and Obsidian. Give Android users a clearly labeled equivalent path and platform caveats where supported.

### 7. Excel: a different task, not another CSV sales page

URL: `/blog/apple-health-to-excel/`. Title/H1: **How to open Apple Health data in Excel**.

Show the exact CSV import, data types, units, missing values and a useful steps/sleep table or chart. Demonstrate multi-day handling from daily files; check Excel platform differences before promising folder refresh. Publish a synthetic workbook only if it is actually generated and verified. Label raw record counts separately from day totals to avoid double-counting.

Primary action: try the sample, then export the reader's own selected data with Health.md. Link to the CSV page for app setup rather than repeating it. If an original workbook workflow cannot be demonstrated, expand the CSV page's import section first and defer this URL.

## Supporting improvements

- **Schedules:** retain `/docs/scheduling/`; add a search-readable title such as “Schedule Apple Health exports and troubleshoot missed runs,” a complete recipe and a last-run/recovery checklist. Keep iOS timing opportunistic, protected-data limitations explicit and Android behavior separately described. Existing docs should remain the authoritative support URL.
- **AI:** turn the current page into a three-choice decision table: file export, bundled Mac MCP, standalone CLI/MCP preview. Reference the exact qualification/release page, source device and foreground/network requirements. Keep cloud-pilot access separate and unavailable to public signup. Explain model-provider handling without implying local transport makes a remote model local. Prefer updating existing query/CLI articles over creating near-identical Claude/Codex/ChatGPT keyword pages.
- **PDF:** use the existing Clinician Report capability and a synthetic preview; explain explicit share, ranges and coverage. Keep the consumer report separate from `apps/practice` and make no diagnostic claim. [Current report docs](https://healthmd.app/docs/clinician-report/).
- **Comparison:** start with native export versus Health.md inside the existing export hub. A later Health Auto Export comparison must use current official sources and actual retained test evidence for tested claims. Competitors already offer substantial automation and AI support; do not claim those categories are unique to Health.md.

## Technical consolidation and measurement

### Visualization URLs

Before changing indexing, inspect Search Console page performance and sampled Google-selected canonicals. Proposed default: one existing category/theme chart URL per chart as the search-facing representative, with useful unique explanation, supported sample inputs, output examples and integration instructions. Preserve all palette/category variant links for sharing, but canonicalize equivalent variants to that representative and list representatives in the sitemap. Avoid combining a cross-page canonical with `noindex` as competing consolidation instructions. Do not block variants in robots; crawlers need to see canonical signals.

Review the generator, not 812 generated HTML files individually. Update `scripts/generate-visualization-pages.mjs` and its tests, preserve embed/customizer behavior, and use honest modification dates. The current hard-coded visualization `lastmod` is July 16; do not replace it with today's date on every build. Recheck sampled rendered pages and structured data. No traffic improvement is presumed from this cleanup alone.

### Measurement baseline

Before the first deployment, export the previous 90 days and most recent 28 days of Search Console query/page/country/device data, including the same-period comparison and indexed-page observations. Use the already verified canonical property rather than assuming the www/non-www property. Track branded versus non-brand queries and intent clusters separately.

Inspect the existing analytics gate and campaign reporting. If missing, add minimal aggregate events for `sample_download`, `store_click` and `setup_guide_click`, with allowlisted page identifiers, CTA position and destination platform. Do not collect exported records, entered measurements or file contents. Reuse the campaign infrastructure rather than adding a second attribution vendor. Verify actual configured provider tokens/reporting before claiming install attribution.

Keep Search Console clicks, website visits, store-link clicks, attributed installs and paid outcomes as separate measures. Define store CTR = store clicks / relevant landing visits, not clicks / search impressions. Use App Store/Play attribution only where its supported signals and reporting thresholds permit; unknown stays unknown. Inbound UTMs should not be added to internal editorial links.

### Weekly editorial loop

Review Search Console once weekly initially. Select relevant queries with observed impressions and a clear product outcome. First inspect the URL already receiving those impressions: improve it when intent matches; write a new guide only for a distinct task. Prioritize high fit and actionable content over raw impressions. Low CTR at a poor position does not by itself prove a title defect.

For every change: record query cluster, existing landing page, change date, source evidence, links added and intended conversion. Review at 14 days for discovery and at 28/56 days for search and conversion trends. Annotate release, price and campaign changes. Drafting can be assisted by agents; verify every screenshot, output and feature claim before publishing. No unattended publishing automation is part of this plan.

## Four-week implementation sequence

| Week | Deliverables | Done means |
| --- | --- | --- |
| 1 | Baseline; CSV and export-hub improvements; contextual home/blog links; scoped AI factual update | Two existing landing pages help a beginner finish a task; acquisition routes are reachable; measured actions verified |
| 2 | Existing Obsidian guide improvement; Android hub; visualization canonical change after performance review | One new acquisition page, preserved platform semantics and existing sharing links |
| 3 | Sleep guide; conditional Excel tutorial; scheduling docs expansion | Authentic steps, generated synthetic examples and recovery advice; useful inbound/outbound links |
| 4 | Review early indexing/query signals; improve weak pages; choose steps/PDF/comparison follow-up | Next article chosen from observed evidence; no artificial traffic or revenue target claimed |

Start at roughly two substantial guides a week while improving existing pages. Vaultaire's reported one-guide-per-day cadence is a workflow example, not a required publishing quota. Preserve the existing ten-locale infrastructure; synchronize material changes to existing localized surfaces. The repository requires translated authored top-level docs, so budget localization for scheduling updates. New English acquisition/blog pages can launch first where supported, but must not emit hreflang to nonexistent translations. Expand their translations according to measured demand and maintainable review capacity.

## Implementation map and verification

Existing sources: `apps/website/{index.html,apple-health-to-csv/index.html,apple-health-export/index.html,health-data-for-ai/index.html}`, `content/blog/`, `docs-src/src/content/docs/scheduling.md`, `scripts/build-blog.mjs`, `scripts/build-site.mjs`, `scripts/generate-visualization-pages.mjs`, `sitemap.xml`, `campaign-links.mjs`, `assets/analytics.js`, and component tests. Inspect the nearest instructions again before implementation; primary checkout changes belong to other ongoing work and must be preserved.

Use the existing Markdown blog pipeline for new articles. New static acquisition directories require build inclusion, sitemap/navigation links and metadata. Keep platform-neutral outcomes consistent with `docs/architecture/cross-platform-unification-policy.md`; website copy must not change export schemas or imply unqualified product capabilities.

For each implementation slice, run appropriate existing content/link/locale tests and a production build from `apps/website`, inspect built HTML, verify canonical/hreflang/sitemap behavior and visually check desktop/mobile. Consolidation tests should verify representative URLs and retained variant functionality. Update old exact-headline test expectations when copy intentionally changes; do not treat a 150–160-character description requirement or FAQ-schema presence as proof of ranking quality.

## Evidence limits

This audit does not establish actual rankings, organic revenue, Core Web Vitals, Google-selected canonicals or which current page performs best. No Search Console credentials, private analytics, health-device data or clinical records were accessed. Fresh fetches were used to resolve cached-copy disagreement; the live deployment and local branch can continue changing independently. Saved audit facts describe the inspection date, not a release qualification.
