# Health.md SEO execution plan: build on the live content cluster

Audited October 26, 2026. This supersedes the execution priorities in the [October 25 plan](2026-10-25-healthmd-seo-plan.md). Scope: live HTML and sitemaps, representative guides, local website source, existing analytics code, and Vaultaire's reported process. Planning only; no production or website source changes.

## Recommendation

Improve and measure the content now live before publishing another broad batch. Prioritize the CSV and Obsidian conversion paths, add concrete spreadsheet assets, then publish a fair competitor comparison and a genuinely distinct Android workflow. Use search-query evidence to choose subsequent articles and translations.

The rankings below are editorial priorities based on product fit, existing assets, reader intent and implementation effort. They are not measured keyword opportunities: authenticated Search Console, conversion and keyword-volume data were not available in this audit.

## What is actually live

Fresh curl responses were used because search extraction returned outdated CSV and blog copy. These observations describe the deployment at inspection time, independently of this checkout.

| Surface | Current observation | Implication |
| --- | --- | --- |
| [Homepage](https://healthmd.app/) | Title/H1 still lead with “Move your health forward”; contextual export/CSV/Obsidian/Android links exist | Improve clarity and navigation; do not report all acquisition links as footer-only |
| [Apple export hub](https://healthmd.app/apple-health-export/) | Native archive procedure, selected-data alternative, format choices and links to metric/destination guides | Keep this URL as owner of broad export intent |
| [CSV landing page](https://healthmd.app/apple-health-to-csv/) | Direct export title/H1, sample, import instructions, row semantics and five free actions already present | Next work is visual proof and conversion verification, not recreating those sections |
| [Guides/blog](https://healthmd.app/blog/) | Workflow directory plus 21 articles | Improve discoverability and individual usefulness; retain `/blog/` URLs |
| [Android export](https://healthmd.app/health-connect-export/) | General export walkthrough and Android sample already published | Expand distinct downstream Android tasks only where justified |
| [AI hub](https://healthmd.app/health-data-for-ai/) | Files, bundled Mac context and direct-phone preview choices already present | Preserve boundaries; do not recreate the topology table |
| [Obsidian walkthrough](https://healthmd.app/blog/export-apple-health-data-to-obsidian/) | Screenshots and free starter ZIP with 28 fictional notes, Bases log and templates | Promote and measure the existing resource before building another tool |
| [Scheduling](https://healthmd.app/docs/scheduling/) | Search-readable title and run verification/recovery guidance | Existing owner URL; no separate generic scheduling post needed |

Newly live guides already cover sleep, steps, heart rate, HRV, workouts, PDF, Excel, Sheets, Claude, ChatGPT and exporting without the cloud. Do not commission these again.

The [main sitemap](https://healthmd.app/sitemap.xml) has **98 entries**, including 59 visualization URLs and 22 blog routes (hub plus 21 articles). The [docs sitemap](https://healthmd.app/sitemap-0.xml) has **414 entries**: 81 English docs and 37 in each of nine other locales. Combined: **512 listed entries**, not an indexed-page count.

Earlier visualization duplication is already being consolidated in production: the sampled ocean HRV variant canonicalizes to its theme-colors representative, and the main sitemap has 58 chart pages plus the hub. Preserve this improvement. Do not revive the previous 812-variant sitemap.

`http://healthmd.app/` redirects to HTTPS. `https://www.healthmd.app/` returns 200 with a canonical to the apex. A host redirect is an optional consistency improvement, not an urgent diagnosed indexing failure. The legacy isolated.tech hostname did not resolve from this execution environment; independently verify its ownership/DNS and any historical links before planning a migration fix.

## First dependency: reconcile production with source

This primary checkout contains only 11 blog source files, lacks the live Android acquisition directory, and still has old visualization generation and AI copy. Other website changes are also uncommitted. Identify the source revision/worktree used for the current deployment, preserve unrelated changes, and reconcile from that source before any publishing work. A build from this checkout could omit live pages or reintroduce old canonical behavior.

Acceptance: a reproducible build from the intended source contains the live route inventory, revised canonicals, starter download and current product copy. Record its revision/deployment identity. Do not overwrite the working tree or rebuild production as a shortcut.

## Ranked backlog

Effort estimates are rough focused working days after source reconciliation; assets or device verification may extend them.

| Order | Improve/create | URL | Deliverable | Effort |
| --- | --- | --- | --- | --- |
| 0 | Reconcile + baseline | Source/deployment and reporting | Reproducible live inventory; previous 90-day query/page export; funnel audit | 1–2 days plus access |
| 1 | Improve CSV | `/apple-health-to-csv/` | Current configuration, preview and saved-file screenshots; obvious sample and first-export actions | 1 day |
| 2 | Improve Obsidian | `/blog/export-apple-health-data-to-obsidian/` | Starter ZIP preview and discovery links; tested sample-to-own-data path | 1 day |
| 3 | Improve homepage/navigation | `/`, `/blog/` | Explicit export positioning; Guides/Exports entry; paths to CSV, Obsidian, Android and AI | 0.5–1 day |
| 4 | Improve Excel | `/blog/apple-health-to-excel/` | Verified synthetic workbook, multi-day CSV input pack, result screenshot | 1–2 days |
| 5 | Improve Sheets | `/blog/apple-health-to-google-sheets/` | Copyable recipe, downloadable sample inputs and result screenshot; no forced sign-in to inspect | 1–2 days |
| 6 | Improve sleep | `/blog/export-apple-health-sleep-data/` | Enabled sleep selection, real preview and saved-file screenshots; seconds/hours example | 1 day |
| 7 | Create comparison | `/blog/healthmd-vs-health-auto-export/` | Dated, sourced workflow comparison with actual test evidence | 2–3 days |
| 8 | Improve troubleshooting | `/docs/troubleshooting/` | Short decision path for missing/empty exports, linked from task guides | 1 day |
| 9 | Create Android downstream guide | `/blog/health-connect-to-google-sheets/` | Verified Android-to-Sheets walkthrough with Android sample and screenshots | 1–2 days |
| 10 | Pilot a useful browser tool | `/tools/combine-healthmd-csv/` | Local processing of Health.md daily CSVs, preview and explicit download | 3–5 days, separate feature slice |
| 11 | Create second comparison if justified | `/blog/healthmd-vs-qs-access/` | Fair comparison for a simple spreadsheet-export user | 1–2 days |
| 12 | Localize validated acquisition pages | Existing locale conventions | Translate strongest task pages into 1–2 evidence-selected locales | Depends on review |

Orders 7–12 are proposed routes, not existing capabilities or confirmed search demand. Reorder them using Search Console and observed conversion friction. Tool work is contingent on a demonstrated need to combine files; the starter vault and workbook are the first free-resource experiments.

## Concrete page briefs

### CSV: the first conversion improvement

Keep the current title and H1: **Export Apple Health to CSV for Excel and Google Sheets | Health.md** / **Export Apple Health to CSV**. They already match intent.

Place a compact proof block close to the first workflow: current app selection → preview → saved CSV. Show the existing synthetic sample next to a plain explanation of daily files, columns and mixed row types. Keep the detailed contract in the reference rather than expanding the sales page indefinitely. Primary action: **Try a CSV export**. Secondary proof action: **Download sample CSV**.

Link Excel/Sheets tutorials after the sample, sleep/steps after metric selection, and the export hub for readers seeking native XML. Preserve the explicit distinction that Health.md reads authorized records, not an existing XML archive.

Acceptance: a beginner can inspect a sample without installing, identify the output location, follow one-day export steps and open the actual file. Use current screenshots and verified trial terms.

### Obsidian: turn an existing download into an acquisition asset

Keep the article URL. Proposed title: **Apple Health to Obsidian: Daily Notes and Free Starter Vault | Health.md**. Keep the introduction focused on exporting to Obsidian, with a visible starter preview below it.

The ZIP already returns HTTP 200; do not invent a separate `/starter-vault/` landing page. Show one daily note, the Bases log and the completed weekly review. Add a short demonstration of opening the downloaded folder and keeping fictional notes separate from personal exports. Link to this resource from homepage export copy, the export hub, the guides directory and relevant chart pages.

Primary proof action: **Download the free starter vault**. After the sample is understood: **Export your own health data**. Measure each action separately. Update the existing Android Obsidian guide with an equivalent sample path where supported.

### Excel and Sheets: provide the finished result

Both existing tutorials contain useful import/filter/aggregation instructions. Sampled live HTML has no substantive instructional images for either. Add screenshots of the actual imported table and result, rather than more explanatory paragraphs.

For Excel, produce a verified `.xlsx` with fictional daily inputs, an untouched raw-data sheet, a filtered steps table, weekly aggregation and a chart. State which refresh steps are manual and which desktop Excel versions were tested. Verify formulas, date handling, missing values and duplicate days. For Sheets, provide the exact import/transformation recipe, a preview and downloadable inputs; a copyable cloud template is optional and must be tested before advertising it. Keep each existing URL and link to CSV for app setup rather than duplicating it.

### Sleep: improve the proof already present

The current article has a detailed sample and correct distinctions, but its setup screenshot shows Sleep disabled. It labels this honestly; improve it with an enabled selection and one successful preview/file example. Add a simple annotated illustration of a night crossing midnight and its export date. Preserve the start-date rule, stage/summary distinctions and missing-data caveats. Do not promise a diagnosis or infer sleep quality.

### Health Auto Export comparison: the first new commercial page

Title: **Health.md vs Health Auto Export: Files, Automation and Obsidian**. H1: **Health.md vs Health Auto Export**.

Start with who should choose each product. Compare a defined one-day export, recurring export and Obsidian workflow, with dated versions and screenshots. Cover formats, destinations, native archive distinction, field semantics, price/trial, supported platforms, privacy boundaries and scheduling limits. Use competitors' official documentation plus retained tests, marking untested items clearly. [HealthyApps](https://www.healthyapps.dev/) already advertises automation, CSV/JSON/GPX, no-account privacy and direct integrations: these cannot be claimed as uniquely Health.md features.

Include cases where the competitor fits better. Keep native Apple export versus Health.md in the existing export hub. Link the new comparison from the export hub, CSV and About pages. Do not launch a thin comparison directory with many untested competitors.

### Android to Sheets: the first new practical guide

Title/H1: **Export Health Connect data to Google Sheets**. Distinct task: Android source app → Health Connect → authorized Health.md export → Sheets table.

Use current Android screenshots and Android-generated synthetic CSV, not Apple fixtures with renamed headings. Demonstrate one available daily metric, dates/units, source synchronization/history access and a spreadsheet result. Link the Android export hub and the existing Sheets guide only for genuinely shared steps. Keep OS/data/channel differences explicit. If query evidence instead points strongly to Android sleep export, substitute that task after verifying the actual supported record path.

### CSV combiner: a later tool with a close product connection

Proposed title: **Combine Health.md Daily CSV Files in Your Browser**. Accept Health.md CSV exports only in the initial release; do not imply arbitrary Apple XML or competitor-format compatibility.

Specify strict CSV parsing, mixed Value types, missing Timestamp fields, quoted JSON/newlines, repeated headers, overlapping dates, units, metadata and canonical rows. Preview warnings before download. Never silently deduplicate legitimate source records or sum raw samples into totals. Distinguish combining rows from calculating daily aggregates. Files remain in the browser; verify no file content enters analytics or network requests. Provide synthetic inputs so the tool is useful without installation.

Link from CSV, Excel, Sheets and the export hub. Measure completed tool use and subsequent app actions separately; tool traffic alone does not establish acquisition value. An XML converter would be separate, larger product work and is not first priority.

## Six-week rollout

- **Week 1:** reconcile live/source, capture reporting baseline, improve CSV and Obsidian, clarify home/navigation.
- **Week 2:** ship verified Excel/Sheets assets and the improved sleep proof. Check first-export completion with a beginner; correct observed friction.
- **Week 3:** publish the Health Auto Export comparison after evidence collection; improve the existing troubleshooting owner page.
- **Week 4:** publish one distinct Android guide and assess demand for the CSV combiner. If justified, begin its separate feature slice; otherwise improve the strongest existing page.
- **Weeks 5–6:** review query/page evidence, run the most justified tool/second-comparison experiment, and translate only if country/language demand supports it.

This is an execution cadence, not a ranking or traffic guarantee. Newly published content may need longer evaluation. No recurring automation or outreach was created by this plan.

## The ongoing Vaultaire-style loop

Review queries and landing pages weekly, with light issue checks between reviews. [Search Console](https://support.google.com/webmasters/answer/7576553?hl=en) provides query/page impressions, clicks, CTR and average position. Export 90 days for context and compare recent 28-day windows, noting the publication dates of this new content wave. Separate brand/non-brand, country, device and intent clusters.

Decision rules:

1. Existing page matches the query: improve that page before creating another URL.
2. Impressions with few clicks: assess actual result position, title/intent fit and country/device differences before rewriting. Low CTR at a low position alone is not a title diagnosis.
3. Clicks but few next actions: improve proof, sample usefulness and the match between the task and app.
4. Store clicks but few confirmed installs: investigate store-page and handoff friction; do not count the click as an install.
5. A repeated distinct task has no suitable owner page: create one original guide with output evidence and links from at least two relevant existing pages.
6. A resource gets use but no product interest: judge its strategic contribution separately before producing more tools.

Track aggregate `sample_download`, `starter_vault_download`, `store_click` and relevant tool completion actions with allowlisted page, CTA position, asset and destination-platform identifiers. Inspect existing deployed reporting first: local `assets/analytics.js` loads a gated beacon, while campaign token infrastructure exists elsewhere; neither establishes a working page-to-install funnel. Reuse the current system where capable. No exported health values, uploaded content or record filenames should enter analytics.

Dashboard by cluster: non-brand search clicks → landing visits → sample/tool actions → store clicks → confirmed store-attributed installs and purchases when available. Label attribution gaps. Use absolute counts and denominators; do not set a conversion target from Vaultaire's unaudited 10% claim.

Distribution is part of the plan: prepare the starter vault/workbook with stable URLs, screenshots, documentation and reproducible synthetic inputs for relevant Obsidian/quantified-self resources. Existing [backlink research](2026-10-26-healthmd-backlink-audit.md) and [prospects](2026-10-26-healthmd-outreach-prospects.md) cover separate discovery. No messages or submissions are authorized by this planning task.

## Publishing acceptance criteria

For each page: distinct intent, immediate answer, genuine result/sample, current screenshots where instructional, truthful released behavior, descriptive title/H1, one canonical owner, useful incoming/outgoing links, mobile readability and a relevant next action. Preserve preview labels, platform differences, metric identities and background-execution limits. Do not create near-duplicate metric/assistant pages merely to repeat keywords.

Implement in the reconciled website source with the existing static/Markdown pipeline. Run component content/link/locale tests and production build; inspect generated canonical/hreflang/sitemap output and representative desktop/mobile rendering. New top-level acquisition directories require build inclusion; new blog guides should retain the existing pipeline. Technical parity/schema changes are outside this editorial plan.

## Limits

No authenticated Search Console, live funnel dashboard, store attribution or representative ranking dataset was available. No fresh performance/CWV audit or broad image-quality review was conducted. Source/live divergence and stale search snapshots were explicitly accounted for. This audit does not establish which page currently earns the most traffic or revenue. The plan prioritizes concrete experiments that can resolve those unknowns.
