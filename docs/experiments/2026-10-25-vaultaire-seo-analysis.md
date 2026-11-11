# Vaultaire SEO analysis

Checked 2026-10-25. Public website, raw homepage HTML, robots.txt, both child sitemaps, selected content pages, and the original publisher's founder interview. Observations describe the current site; they do not establish which historical change caused growth. No production changes made.

## Finding

Vaultaire combines narrowly targeted task guides, commercial comparisons, scenario pages, free tools, localization, contextual internal links, and app conversion prompts. The founder describes a feedback loop that chooses topics from search data rather than an arbitrary editorial calendar. This is a plausible explanation of acquisition, not an independently measured traffic attribution study.

## What the founder reports

In the October 18 Starter Story interview, Rasty Turek says incumbents dominate App Store discovery but neglect web searches. He describes using coding agents and his Gum Google-service tools to identify searches with impressions but no clicks, publish roughly one useful guide daily, and link existing pages to new guides. He reports the web is the majority of traffic and approximately 10% web conversion toward the app, with CTAs placed around common reader exit points. These are founder-reported figures; the interview does not provide an independently reproducible attribution dataset. Its three-to-four-day discovery claim is an observation, not a service guarantee. [Original interview and transcript](https://www.starterstory.com/stories/this-app-is-making-2-000-per-day)

The transcript loosely calls the impression/position source Keyword Planner. Site-specific query impressions, clicks and average positions are Search Console metrics. Keep that separate from Keyword Planner's keyword-demand research in any reproduction. [Google metric definitions](https://support.google.com/webmasters/answer/7042828?hl=en)

## Measured public footprint

Fetched the sitemap index and its two children, parsed XML with Python ElementTree, collected `sitemap:loc` values, deduplicated, and grouped by first path segment. There were **7,550 unique listed URLs** and **32 language/locale versions**, including English and distinct Portuguese/Chinese variants. These are advertised URLs, not an indexed-page count.

English path counts:

| Section | URLs | Interpretation |
| --- | ---: | --- |
| `/guides/` | 122 | Hub plus 121 articles |
| `/scenarios/` | 44 | Hub plus 43 scenarios |
| `/compare/` | 33 | Hub plus 16 comparison/review pairs |
| `/features/` | 13 | Hub plus 12 feature pages |
| `/tools/` | 31 | Hub, 12 tools, 18 supporting articles |

The remaining English URLs include the homepage and company/legal/support/update pages. Locale section sizes vary, so this is not a perfectly identical translation matrix. Sources: [sitemap index](https://vaultaire.app/sitemap.xml), [first child](https://vaultaire.app/sitemap-1.xml), [second child](https://vaultaire.app/sitemap-2.xml).

## How the content captures demand

- **Practical questions:** The hide-photos guide gives an immediate answer, explains Apple's built-in method, uses illustrated steps, compares options and links related tasks. This targets users who know their problem before they know the product. Its security comparisons are the publisher's assertions, not independently verified findings in this analysis. [Example](https://vaultaire.app/guides/hide-photos-iphone/)
- **Commercial evaluation:** A best-apps guide, named competitor comparisons, review subpages and migration guides address different stages of choosing or replacing an app. [Roundup](https://vaultaire.app/guides/best-photo-vault-apps-iphone/), [comparison hub](https://vaultaire.app/compare/), [Keepsafe comparison](https://vaultaire.app/compare/vaultaire-vs-keepsafe/).
- **Specific requirements:** Pages such as an offline vault without an account match restrictive buying criteria, with a close connection to product positioning. [Example](https://vaultaire.app/guides/offline-photo-vault-no-account-iphone/)
- **Concrete situations:** Scenario pages describe phone handoffs, shared passcodes, private records, repairs and other moments that create the need. These extend acquisition beyond the phrase “photo vault.” [Scenario hub](https://vaultaire.app/scenarios/)
- **Useful utilities:** Tools cover metadata removal, face blur, compression, resizing and conversion. Supporting articles address related questions. The metadata tool presents local processing, capabilities and limitations, then bridges to keeping originals private in the app. The tool's traffic and conversion contribution are unknown. [Tools](https://vaultaire.app/tools/), [metadata tool](https://vaultaire.app/tools/photo-metadata/).

My inference: the strongest strategic feature is the close relationship between searcher's task and product use. Tools that are farther from the product may increase visits without increasing purchases; evaluate these separately.

## Internal linking and conversion

The guides link sideways to related tasks and forward to feature explanations, commercial comparisons and app downloads. The roundup links individual competitor comparisons and narrower requirement guides. This creates discovery paths for readers and crawlers. [Hide-photos guide](https://vaultaire.app/guides/hide-photos-iphone/), [roundup](https://vaultaire.app/guides/best-photo-vault-apps-iphone/).

The useful conversion pattern is to answer a task first, explain where the native solution stops meeting that need, and offer a relevant app action. Reader-exit CTA placement is reported by the founder; the public pages alone do not verify its measured lift.

## Technical observations

The fetched homepage HTML contains its substantive text and links before JavaScript execution, a descriptive title and meta description, a self-canonical URL, 32 locale alternates plus `x-default`, social metadata, deferred script tags, stylesheet/font preloads and JSON-LD. JSON-LD types include SoftwareApplication, Organization, Brand, WebSite, FAQPage, HowTo and BreadcrumbList. These are homepage observations, not a sitewide validation. [Homepage](https://vaultaire.app/)

Robots permits crawling of public content and blocks `/go/`, with explicit bot groups and a sitemap reference. The homepage also advertises a machine-readable MCP manifest. These demonstrate deliberate discoverability work, not proof of higher rankings or AI recommendations. [Robots](https://vaultaire.app/robots.txt)

Do not attribute success to FAQ/HowTo markup. Google's current update log says FAQ rich results no longer appear, and HowTo rich results were deprecated earlier. Nor is one article per day a ranking exemption: Google's policy evaluates value and purpose, including AI-generated output. [Current updates](https://developers.google.com/search/updates), [HowTo change](https://developers.google.com/search/blog/2023/08/howto-faq-changes), [AI content guidance](https://developers.google.com/search/docs/fundamentals/using-gen-ai-content).

Localization reaches actual article bodies, not just menus. However, the sampled Spanish comparison shows older product allowances than current English content. Locale synchronization is a maintenance issue worth checking before copying this scale. [Spanish comparison](https://vaultaire.app/es/compare/vaultaire-vs-keepsafe/), [current English comparison](https://vaultaire.app/compare/vaultaire-vs-keepsafe/).

## Limits

No authenticated Search Console, analytics, App Store attribution or backlink dataset was available. An attempted SpyFu overview through Treg could not run because its service token was expired/invalid; no traffic estimate was obtained. Search samples are not a representative country/device rank-tracking study. No Core Web Vitals field data or performance audit was collected. Sitemap inventory cannot establish indexing, translation quality, uniqueness, backlink strength or acquisition value.

## Suggested adaptation for Health.md

These are proposed experiments, not verified keyword opportunities or product-support promises:

1. Start with actual Search Console queries and group them by user task. Examine relevant impressions, existing landing pages and conversion potential.
2. Improve an existing page when it already answers the intent; create a new guide only for a meaningfully different task.
3. Candidate topics to validate: Apple Health to CSV, inspecting Apple Health export XML, exporting sleep history, moving health data to Obsidian, and automating an authorized export. Verify current product capabilities before making claims.
4. Use genuine output examples, screenshots, limitations and reproducible steps. Health interpretation requires greater care than file-format guidance.
5. Add contextual links from relevant established pages and a task-specific next action to try the product.
6. Track non-brand query clicks, landing-page visits, download actions, installs and paid cohorts separately. Avoid treating an App Store link click as a verified install.
7. Expand localization only after identifying valuable pages and a process to keep technical facts synchronized. Evaluate free tools on qualified acquisition, not raw visits.

Priority: build a measured query-to-content-to-product loop; then scale the parts that produce qualified users.
