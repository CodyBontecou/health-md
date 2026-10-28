# Health.md backlink audit

Checked October 26, 2026. Target: `healthmd.app`, including subdomains. Read-only research; no outreach, site changes, removals or disavow submission.

## Finding

The available Ahrefs sample is dominated by repetitive, irrelevant link-selling content. Do not treat the reported referring-domain count as an audience or endorsement count. Prioritize genuine editorial coverage and useful workflow references rather than more bulk links.

This is a **sample audit**, not an exhaustive audit of all referring domains. No Search Console Links export, manual-action report or authenticated full Ahrefs export was available. The sample cannot establish the profile-wide spam percentage, why the DR is 5, who created these links, or whether Google has penalized the site.

## Live Ahrefs baseline

Source: [Ahrefs Backlink Checker](https://ahrefs.com/backlink-checker/?input=healthmd.app&mode=subdomains), submitted in the browser on the inspection date. The report explicitly said “Domain including subdomains. One link per domain.”

| Metric | Reported value |
| --- | ---: |
| Domain Rating | 5 / 100 |
| Backlinks | 645 |
| Backlinks marked dofollow | 11% |
| Linking websites | 619 |
| Linking websites marked dofollow | 9% |
| Individually visible backlink rows inspected | 20 |

Percentages are rounded vendor figures; they do not provide exact followed-link counts. DR is Ahrefs' proprietary metric, not a Google score. The checker displayed 20 rows in this session despite being promoted elsewhere as a top-100 checker. There was no complete downloadable export available in the inspected view.

## Sample assessment

All 20 visible referring-page rows contained link-selling or unrelated templated SEO copy. Classification is my editorial assessment of the referring titles and anchor/context text **as displayed by Ahrefs**, not an independent successful fetch of every page. Two attempted direct web fetches (Quick Rank Lab and seogrow.agency) were inaccessible, so their current live content and link attributes remain unverified. Per-row follow status, first-seen dates and traffic were not exposed in this view.

| Referring domain | Ahrefs DR displayed | Visible pattern |
| --- | ---: | --- |
| quickranklab.shop | 0 | A |
| steadyboosthub.shop | 0 | A |
| seozira.shop | 0 | A |
| header-link-portal-link-baron.store | 49 | B |
| advanced-traffic-surge-and-keyword-rank-bureau.store | 49 | B |
| siterankprovider.shop | 0 | C |
| seogrow.agency | 61 | D |
| rapidseolink.shop | 0 | A |
| 11763873.xyz | 44 | B |
| seoqano.shop | 0 | A |
| advanced-saas-seo-directory-outrank-hq.store | 49 | B |
| definitive-team-link-baron-wiki.store | 49 | B |
| epic-syndicate-link-baron-keyword.store | 49 | B |
| linkviro.shop | 0 | A |
| bold-contextual-rank-forge-consultants.store | 49 | B |
| 11763750.xyz | 44 | B |
| trueranklab.shop | 0 | A |
| 37486312.xyz | 47 | B |
| webrankresults.shop | 38 | C |
| fastranking.shop | 2 | E |

- **A — 7 rows:** repeated regulated/YMYL/real-estate/iGaming article and identical slug `trj43rh-why-igaming-struggle-broken-link-building-adjustments-make-campaigns/`. The anchor falsely describes healthmd.app as offering SEO/automation work for crypto projects. [Example reported source](https://quickranklab.shop/trj43rh-why-igaming-struggle-broken-link-building-adjustments-make-campaigns/).
- **B — 9 rows:** near-identical “50 Visitors a Month” / SEOExpress testimonial title and casino/crypto backlink-selling anchor. [Example reported source](https://header-link-portal-link-baron.store/i-remember-when-my-business-had-only-50-visitors-a-month-and-i-was-ready-to-give-up-before-discovering-seoexpress-for-cheap-high-quality-backlinks-in-45-days-my-organic-traffic-skyrockete).
- **C — 2 rows:** generic guest-post, backlink and authority-growth sales copy describing services supposedly for healthmd.app. [Example reported source](https://siterankprovider.shop/83ccc50cd-60-day-dofollow-backlinks-journey-travel-zero-rankings-to-page1-proven-optimization-process-research-execution-and-analysis-for-stronger-domain-authority/).
- **D — 1 row:** generic growth-service testimonial; anchor still contains the unexpanded `{site_name}` placeholder. [Reported source](https://seogrow.agency/feeling-frustrated-by-slow-growth-upgraded-partnershipwith-seogrow-agencys-strategies-reveals-tremendous-benefits/).
- **E — 1 row:** referring title explicitly advertises buying dofollow SEO backlinks, with a healthmd.app anchor. [Reported source](https://fastranking.shop/arta-get-ranking-on-1st-page-with-us).

Every sampled target was `https://healthmd.app/`. There were no useful editorial references in these 20 rows. This is 20 observed domains out of 619 reported, with unknown selection bias; do not extrapolate 100% spam to the whole profile. Some suspicious rows had DR 38–61, illustrating why source DR alone is not a quality filter. Nothing here proves that Health.md commissioned these links.

## Genuine references and adjacent mentions

These were found outside the Ahrefs sample. Their presence does not prove Ahrefs indexes or credits them.

| Source | Verified observation | Interpretation / action |
| --- | --- | --- |
| [Domain Arrivals, June 25 issue](https://domainarrivals.com/issues/2026-06-25/top) | Health.md entry links directly to healthmd.app and describes Apple Health → Obsidian/Markdown/CSV/JSON | Existing discovery-directory link; retain, not a new outreach prospect. Follow attribute unverified. |
| [Health.md Android GitHub repository](https://github.com/CodyBontecou/health-md-android) | Public repository points to healthmd.app | Owner-controlled project reference, not independent editorial endorsement. Retain accurate canonical destination. |
| [Obsidian Stats plugin page](https://www.obsidianstats.com/plugins/health-md) | Existing Health.md Visualizations page; inspected content links to the App Store and GitHub | Existing brand distribution. No direct healthmd.app link was found in the extracted page text/links; do not count it as a confirmed domain backlink. A relevant documentation link could be useful if the maintainer supports it. |

## Actions in order

1. **Pursue relevant editorial links.** Use the companion outreach report. Pitch a working, documented workflow and allow editors to decide whether/how to link; do not ask for guaranteed followed placements.
2. **Use existing useful destinations.** [Apple Health export](https://healthmd.app/apple-health-export/), [CSV](https://healthmd.app/apple-health-to-csv/) and [Obsidian walkthrough](https://healthmd.app/blog/export-apple-health-data-to-obsidian/) already exist. Prepare a short demo and synthetic sample specific to each pitch rather than inventing another generic landing page.
3. **Complete the profile audit when authenticated data is available.** Export Search Console external links plus an Ahrefs all-referring-domains/backlinks report. Deduplicate by registrable domain; record source/target, follow status, first/last seen, live status and relevance. Check target redirects and broken URLs. Inspect Search Console Manual Actions separately. None of those checks is represented as completed here.
4. **Do not submit a blanket disavow based on this sample.** Google's guidance requires both substantial spam links and a manual action or likely manual-action risk. Most sites do not need the tool. The present sample establishes neither a penalty nor that threshold. [Google guidance](https://support.google.com/webmasters/answer/2648487?hl=en).
5. **Measure useful outcomes.** Track editorial referring domains, visits to the linked resource, store clicks/install attribution where available, and search clicks. DR is a secondary indicator. Recheck at a regular interval without promising a particular score gain.

## Data access and cost

An independent SE Ranking lookup through Treg was attempted with target healthmd.app, domain mode, limit 100. Catalog price was $0.000179 per row (approximately $0.0179 at the cap), disclosed before execution. The call returned an invalid/expired authentication error, no provider dataset, no call ID and no reported charge. It is not evidence for any backlink conclusion. No sign-in or credentials were changed. Public web search is supplementary discovery, not a replacement backlink index.

## Interpretation sources

- [Ahrefs: Domain Rating calculation](https://ahrefs.com/blog/domain-rating/) — followed referring domains and relative link strength; raw link totals alone do not determine DR.
- [Google: disavow criteria](https://support.google.com/webmasters/answer/2648487?hl=en) — no automatic disavow recommendation from a suspicious sample.
- [Google: link-spam policies](https://developers.google.com/search/docs/essentials/spam-policies#link-spam) — paid ranking links, automated schemes and excessive exchanges are not the outreach strategy.

Related research: [10 outreach prospects](2026-10-26-healthmd-outreach-prospects.md).
