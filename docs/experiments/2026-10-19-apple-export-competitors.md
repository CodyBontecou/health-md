# Apple Health export competitor review brief

**Date:** 2026-10-19 · **Method:** public Apple US storefront APIs through local Treg · **External spend:** **$0** of the approved $5 maximum.

## Decision

Prioritize **a verifiable first export, understandable automation/recovery, and clear free-versus-paid scope**. Those are stronger findings from this sample than demand for another export format.

Do not position CLI/MCP support or Markdown export as unique. Health Auto Export advertises MCP and Markdown; Health Export CSV advertises an open-source CLI and LLM workflows. Health.md's useful distinction to explain is its particular local-file/Obsidian workflow and direct-device architecture, including their availability constraints—not generic “AI support.” These are listing claims, not independently tested competitor capabilities. [L1] [L2] [L3] [L4]

## Sample and limitations

The cohort is Health.md plus three relevant export utilities found through Apple's US software search: Health Auto Export, Health Export CSV, and Simple Health Export CSV. Selection was based on discoverable listings and export relevance, before reading review sentiment. One latest-review feed page was requested per app; there was no star-rating filter or additional paging.

| App | Current listing version | Listing rating / rating count | Upfront download price, USD | Written reviews fetched → retained | Fetched review date range |
| --- | --- | --- | --- | --- | --- |
| [Health.md][L1] | 3.4.3 | 4.82 / 22 | $0 | 2 → 1 | 2026-08-22–2026-09-05 |
| [Health Auto Export — JSON+CSV][L2] | 10.0.4 | 4.32 / 419 | $0 | 50 → 44 | 2023-07-14–2026-10-16 |
| [Health Export CSV][L3] | 3.12.0 | 4.52 / 153 | $2.99 | 31 → 24 | 2020-01-07–2026-09-30 |
| [Simple Health Export CSV][L4] | 2022.2 | 4.13 / 31 | $0 | 14 → 9 | 2020-12-20–2026-01-05 |

Metadata comes from the [US lookup response][M1]; review samples come from [R1] [R2] [R3] [R4]. Download price does **not** describe in-app purchases, subscriptions, or what remains usable for free. Rating counts include ratings without written reviews and are not this study's denominators.

- **97 written review entries fetched; 78 retained; 19 excluded** through conservative health/contact filters and a manual privacy pass. Author objects, Apple review IDs, and profile links were not copied into the research dataset. Excluded text is absent from the retained dataset and this brief. Only generalized product observations appear here.
- **Health.md has one retained review.** That cannot establish its recurring complaints, failure rate, or superiority. Its retained reviewer valued computer/agent access and wanted clearer coverage boundaries. [R1]
- These are volunteered reviews, not a representative customer survey. The 50-review cap, different app ages, privacy exclusions, and different time ranges bias the sample. Simple Health Export CSV's listing was last updated in 2022. [M1]
- Review versions vary, including companion-app contexts; many comments predate current releases. A complaint is not a reproduced current defect. Do not infer operating-system support or reproduce a reviewer's API-availability assertion as fact.
- Counts below are **manually coded mentions among 78 retained entries**, not affected-user percentages. Reviews can support multiple themes. Dates use Apple's feed `updated.label`, not necessarily original publication. “2026” means that feed date falls in 2026, not a rolling twelve-month window. Coding follows the text, not the stars: one five-star entry reports a startup crash.
- This is **Apple-only research**. It provides no Android review evidence, Google Play ranking, keyword volume, backlink data, or measured SEO opportunity size.

## Five recurring themes

| Theme | Coded entries / 78 | Feed-dated in 2026 | Distribution | Evidence and implication |
| --- | --- | --- | --- | --- |
| **Export/app reliability** | **18** | 9 | Auto Export 16; Export CSV 2 | Crashes/freezes, empty exports, failed sync, and failed delivery. Examples: Auto Export, 2026-10-03 (v10.0.4), cannot open; Export CSV, 2026-08-19 (v3.9.9), crashes across date ranges. Make completion, partial results, and recovery observable. [R2] [R3] |
| **Automation/sync expectations** | **9** | 7 | Auto Export 6; Export CSV 3 | Auto Export, 2026-05-20 (v9.0.9), describes manual export working but automation failing. Export CSV has a 2026-09-30 “No Automation” complaint although its current listing advertises Shortcuts and a separate remote service. Explain workflow, device state, and entitlement; the complaint is not proof that automation is absent. [R2] [R3] [L3] |
| **Trial/purchase/billing friction** | **11** | 7 | Auto Export 7; Export CSV 4 | Free-tier expectations, trying the intended workflow, restore, and cancellation/refund guidance. Examples: Auto Export, 2026-05-06, post-trial friction; Export CSV, 2026-01-21, app/Shortcuts versus remote subscription. State paid boundaries before commitment. Billing allegations were not verified. [R2] [R3] |
| **Output fit: format, granularity, units, coverage** | **9** | 4 | Auto Export 4; Export CSV 3; Simple CSV 1; Health.md 1 | Opposing needs: Export CSV, 2024-02-29, wants event-level records instead of buckets; Simple CSV, 2023-09-01, wants daily totals instead of extensive rows and post-processing. Other entries describe confusing formats, units, or scope. Explain the choice instead of promising one universal export. [R1] [R2] [R3] [R4] |
| **Setup explanations, preview, support** | **8** | 5 | Auto Export 7; Export CSV 1 | Auto Export, 2026-09-20, asks for UI descriptions; other comments describe opaque instructions or difficulty finding help. Export CSV, 2023-05-28, wants a pre-purchase workflow preview. Make the first successful workflow and support path easy to find. [R2] [R3] |

**Counterevidence matters.** The same sample praises reliable automation (Auto Export, 2026-06-28 and 2025-12-27), clear trial/lifetime pricing (Auto Export, 2025-02-21), successful support (Auto Export, 2025-07-17; Export CSV, 2022-01-05), and easy CSV output (Simple CSV, 2026-01-05). These findings support investigating friction, not declaring competitors broken or unsupported. [R2] [R3] [R4]

## Five product/positioning opportunities

These are recommendations for a subsequent scoped audit, **not newly discovered missing features or implementation commitments**. Health.md already documents previews, export history/retry, schedules, configurable detail, and a ten-action free allowance. [H1] [H2] [H3] [H4] [H5]

1. **Make the first useful file the acceptance test.** Audit whether a new user can choose one day, preview the actual format, find the saved artifact, and tell “completed,” “empty/unavailable,” and “partial” apart. Reuse existing preview/history/recovery surfaces rather than building another export engine. Test with synthetic inputs; do not collect health payloads in analytics. [H1] [H2]
2. **Explain automation as a device-state contract.** Show the configured target, last completed occurrence, pending/blocked reason, and recovery action where appropriate. Health.md already documents pending recovery, data-lock constraints, and OS-controlled timing. Avoid a guaranteed background-sync promise; live direct CLI queries also have their own foreground-source requirements. [H3] [H6]
3. **Put the real free/purchase boundary near the first decision.** Explain the documented ten export actions, one action versus many files/dates, one-time unlock, and restore path. Test that users can actually evaluate their intended workflow before paying. Let StoreKit supply the live localized price; do not borrow a reviewer's price or infer entitlement from a free download. Health.md's fetched description explains formats/privacy but does not explicitly state the ten-action allowance or one-time-unlock model. [L1] [H4]
4. **Lead with the consumer's output goal.** Make “daily spreadsheet summary” versus “timestamped/source records” understandable before exposing advanced settings. Demonstrate the existing detail modes with real generated synthetic examples and explicit units/coverage. Health.md CSV can contain nested canonical JSON rows; calling every mode a flat, immediately analysis-ready spreadsheet would mislead. Preserve shipped schemas and honest platform differences. [H5] [H7]
5. **Correct the comparison, then differentiate the workflow.** The current CSV landing page says “Most CSV tools ask you to build them first.” This study does not substantiate that market-wide claim: all three selected competitors are finished App Store apps. Keep comparisons to XML/scripts specific, and explain native daily-note/Bases integration, destination control, and the direct live phone-to-computer route. The retained Health.md review still sounds uncertain about which apps must remain open; a concise architecture/setup choice would help. Link to the existing CLI/MCP preview documentation and qualification limits rather than promoting the preview as fully qualified. [H8] [R1] [L1] [L2] [L3] [L4] [H6]

## Five content opportunities

These are **review-led content hypotheses**, not keyword-volume or ranking findings. Existing guides should be improved or linked, not duplicated just to add pages.

| Proposed content | Reader outcome | Evidence / existing surface |
| --- | --- | --- |
| **“Why didn't my scheduled Apple Health export run?”** | Understand lock/background/target/quota limits; find the pending recovery action and verify the resulting file | Automation/reliability themes; expand the [scheduled-export guide][H3] |
| **“Your first Apple Health CSV in Excel or Numbers”** | Export one day and open the exact artifact, with a synthetic downloadable example and visible units | Output/setup themes; improve the existing [CSV landing page][H8] and [CSV guide][H5] |
| **“Daily totals or raw records: which export do you need?”** | Compare small summary and event-record examples, including when CSV contains JSON and when JSON is easier | Opposing granularity requests; connect [CSV][H5] and [time-series][H7] documentation |
| **“Moving from another Apple Health exporter: a checklist”** | Check source direction, supported scope, formats, destination, scheduling, trial/purchase expectations, and recovery before switching | Pricing/output/automation themes; a comparison must cite current listings and distinguish migration advice from unsupported file-import/conversion promises |
| **“CLI or MCP? A local Apple Health agent setup without the Mac app”** | Choose a file export or a live bounded query, understand foreground/network/model-provider requirements, and verify exact preview compatibility | Retained Health.md feedback plus competitor agent messaging; clarify/link the existing [direct CLI/MCP article][H6], not a new “unique AI integration” claim |

## Suggested next implementation slice

First make a small, factual **CSV landing-page comparison correction**: distinguish scripts/XML converters from other finished App Store exporters rather than using an unsupported “most tools” contrast. Then do a **first-export clarity audit** and the **scheduling troubleshooting update**. Their acceptance criteria should be: a new user can produce one useful file, understand its completeness and location, and recover a blocked scheduled run without guessing.

Before proposing new controls, inspect the existing preview/history/schedule screens and both Apple/Android outcomes. Any implementation must follow the [cross-platform policy][H9], preserve export contracts, and qualify its release separately. This research changed no mobile behavior, schema, pricing, store listing, or published website.

## Execution and retained evidence

- Local Treg added two credential-free own tools: Apple software search and the US customer-review feed, alongside the existing app lookup tool.
- **Eight public Apple requests:** three discovery searches, one four-app lookup, and four single-page review fetches. Every call used `X-Treg-Route-Max-Cost: 0`; no paid-provider fallback, subscription, login, cookie import, health-device query, or top-up was used.
- External spend was **$0**. The original **$5 total ceiling remains unspent**; it is not a new $5 budget for a later session.
- Ignored task evidence is in `.pi/research/treg-apple-2026-10-19/`: `research.py`, sanitized per-app review datasets, public listing snapshots, health-free request receipts, `coding.json`, and `analysis.json`. Coding references are synthetic content hashes, not reviewer IDs. Raw feed responses were processed in memory rather than archived; final per-app files omit excluded entries. Filtering is not a guarantee about upstream or ordinary agent-transcript retention.
- Local Treg source remains unmodified. The service and public-source tools are retained for the requested trial; nothing was scheduled or published automatically.

## Sources

Apple listing and feed URLs are primary sources but are mutable. Metadata/review snapshots and retrieval times are retained in the ignored evidence above. Health.md documentation was read from checkout revision `1ed9447cf159d8f1e824b867985cd0809b7dea43`; draft/source documentation is not release qualification.

[L1]: https://apps.apple.com/us/app/health-md/id6757763969
[L2]: https://apps.apple.com/us/app/health-auto-export-json-csv/id1115567069
[L3]: https://apps.apple.com/us/app/health-export-csv/id1477944755
[L4]: https://apps.apple.com/us/app/simple-health-export-csv/id1535380115
[M1]: https://itunes.apple.com/lookup?id=6757763969,1115567069,1477944755,1535380115&country=us
[R1]: https://itunes.apple.com/us/rss/customerreviews/id=6757763969/sortBy=mostRecent/json
[R2]: https://itunes.apple.com/us/rss/customerreviews/id=1115567069/sortBy=mostRecent/json
[R3]: https://itunes.apple.com/us/rss/customerreviews/id=1477944755/sortBy=mostRecent/json
[R4]: https://itunes.apple.com/us/rss/customerreviews/id=1535380115/sortBy=mostRecent/json
[H1]: ../../apps/apple/docs/features/export-preview.md
[H2]: ../../apps/apple/docs/features/export-history-retry.md
[H3]: ../../apps/apple/docs/features/scheduled-exports.md
[H4]: ../../apps/apple/docs/features/full-access-unlock.md
[H5]: ../../apps/apple/docs/features/csv-export.md
[H6]: ../../apps/website/content/blog/healthmd-cli-direct-iphone-mcp.md
[H7]: ../../apps/apple/docs/features/time-series-data.md
[H8]: ../../apps/website/apple-health-to-csv/index.html
[H9]: ../architecture/cross-platform-unification-policy.md
