# Vaultaire SEO follow-up

Checked October 26, 2026. Supplements [the October 25 analysis](2026-10-25-vaultaire-seo-analysis.md). No website or product code changed.

## Assessment

The strongest explanation is a repeatable process connecting search demand to narrowly targeted content, contextual internal links, and relevant app conversion prompts. Localization and free utilities expand the acquisition surface. Public observations support this explanation but do not establish historical causality or independently verify traffic.

## Rechecked evidence

Fetched the [sitemap index](https://vaultaire.app/sitemap.xml) and both children with curl, parsed URL entries with Python ElementTree, deduplicated, and counted English paths:

| Section | Listed URLs | Breakdown |
| --- | ---: | --- |
| Guides | 122 | Hub and 121 articles |
| Scenarios | 44 | Hub and 43 articles |
| Compare | 33 | Hub and 16 comparison/review pairs |
| Tools | 31 | Hub, 12 utilities, 18 supporting pages |
| Features | 13 | Hub and 12 feature pages |

Total remains **7,550 unique sitemap URLs**. Listed URLs are not an indexed-page count. Sources: [first sitemap](https://vaultaire.app/sitemap-1.xml), [second sitemap](https://vaultaire.app/sitemap-2.xml).

The [hide-photos guide](https://vaultaire.app/guides/hide-photos-iphone/) targets a concrete task in its title and H1, supplies an immediate answer and instructions, then links related guides and product features. Its security and competitor claims were not audited here and should not be adopted without verification.

The [comparison hub](https://vaultaire.app/compare/) addresses named alternatives, while the [scenario hub](https://vaultaire.app/scenarios/) addresses circumstances such as phone handoffs, repairs and private records. These capture different search intents. The [tools hub](https://vaultaire.app/tools/) pairs useful browser utilities with supporting articles, creating further entry points. Their actual traffic and conversion contribution remains unknown.

Raw HTML for the homepage and hide-photos guide contains substantive text, links, descriptive titles, self-canonicals, language alternates and JSON-LD. The guide declares Article, HowTo, FAQPage, BreadcrumbList and ImageObject types. Schema presence does not demonstrate validity, ranking benefit, rich-result eligibility or performance. No Core Web Vitals measurement was conducted.

## Founder-reported process

The original [Starter Story interview](https://www.starterstory.com/stories/this-app-is-making-2-000-per-day) describes reviewing search impressions with few/no clicks, publishing roughly one guide per day and linking established pages to it. The founder reports majority traffic from web and approximately 10% web conversion, with CTAs around common reader exits. These are unaudited claims; the conversion event is unspecified. The transcript calls its query source Keyword Planner, but site-specific query impressions, clicks and average positions are [Search Console metrics](https://support.google.com/webmasters/answer/7042828?hl=en).

A [founder LinkedIn post](https://www.linkedin.com/posts/synopsi_well-vaultaireapp-made-16271-in-may-2026-activity-7468018307430985729-VxHu) also mentions ASO and a viral tweet. Do not attribute all acquisition or revenue to SEO.

## Measurement limitation

An attempted US domain overview through Treg/Serpstat failed because the connected service token is invalid or expired; no traffic or keyword estimate was returned. No authenticated Search Console, analytics, install attribution, representative rank tracking or backlink analysis was available.

## Practical adaptation

For Health.md, validate task-oriented opportunities such as Apple Health to CSV, understanding export XML, exporting sleep history and moving data to Obsidian. These are hypotheses, not measured keyword opportunities or product-support assertions. Prioritize real query evidence, useful output examples and accurate limitations, contextual links, and a relevant product action. Measure non-brand search clicks through qualified installs and paid users before scaling content volume or translations.
