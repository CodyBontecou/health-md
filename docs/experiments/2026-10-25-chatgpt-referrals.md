# ChatGPT referral optimization: four-app review

Date: October 25, 2026. Status: audit and proposed copy; no external listing changes or deployment.

## Baseline

App Store Connect → Analytics → Acquisition → Sources → App Referrers, July 26–October 23, 2026. App Download Date: All. These figures were read from the owner's authenticated UI.

| App | ChatGPT impressions | Total downloads | Estimated proceeds |
| --- | ---: | ---: | ---: |
| Health.md | 48 | 20 | $48 |
| Vox.md | 60 | 24 | $8 |
| iso.me | 112 | 61 | $32 |
| GitSync.md | 56 | 6 | $51 |
| Total | 276 | 111 | $139 |

ChatGPT leads the app-referrer tables for all four. No ChatGPT domain appeared in the web-referrer tables checked for this period. Absence is not proof of no web-origin activity. App Store impressions are not the number of recommendations displayed in ChatGPT. Total downloads include redownloads; proceeds are estimates after applicable taxes and Apple's commission, rounded in this view. Apple's source attribution is not a causal estimate of incremental revenue. [Apple acquisition](https://developer.apple.com/help/app-store-connect-analytics/acquisition/acquisition/), [sales and proceeds](https://developer.apple.com/help/app-store-connect-analytics/monetization/sales/).

## What the audit found

Health.md already has OAI-SearchBot allowed in the local robots.txt, a sitemap, structured product information, an about page, agent documentation, and export workflow articles. Adding another AI index is lower priority than improving accuracy and useful answers. Its indexed about page still described ten free exports when checked, while local source says five. The five-export experiment explicitly says release/deployment are separate from implementation: confirm the shipped build and deployed page before changing promises. A cached search result alone does not establish the current origin response. [About](https://healthmd.app/about/); local `apps/website/about/index.html`, `apps/website/robots.txt`, and `docs/experiments/2026-10-24-five-free-exports.md`.

Vox.md has extensive feature documentation, but its blog index exposes one voice-keyboard guide. There is room for shorter, task-specific tutorials that make the broader capture product easier to evaluate. Searches also surface unrelated products called Vox. Use the full name, developer identity, and exact App Store link consistently. [Homepage](https://vox.isolated.tech/), [documentation](https://vox.isolated.tech/docs/), [blog](https://vox.isolated.tech/blog/).

iso.me has a clear private location-journal proposition and one published guide on its blog index; export and battery guides are marked planned. Finish useful supporting material rather than growing the publishing queue. Its documentation entry point should lead directly to permission, tracking, backup, and recovery answers. [Homepage](https://isome.isolated.tech/), [blog](https://isome.isolated.tech/blog/), [docs](https://isome.isolated.tech/docs/).

GitSync.md already has seven workflow guides. Its current homepage supports broader remote/SSH workflows than an older search result for the former domain described. Prioritize canonical redirects and agreement between current guides, listing, and released platform support. The former `gitsyncmd.app` homepage redirects to `gitsync.md`; this audit did not verify all old paths or redirect status codes. Similar names exist in search; keep the `.md`, developer identity, store IDs, and platform differences clear. [Homepage](https://gitsync.md/), [guides](https://gitsync.md/blog/).

Live robots/WAF access for the other sites is unverified: the search tool could not retrieve their robots.txt files. That error does not establish a block. Verify through hosting configuration, actual responses, and crawler logs before editing rules.

## First changes to prepare

These are editorial hypotheses, not known ranking factors. Refine existing pages where they already answer the question; avoid near-duplicate landing pages.

| Priority | App | Work item | Acceptance evidence |
| --- | --- | --- | --- |
| 1 | iso.me | Publish “Private location history on iPhone: setup, battery, and backup.” Expand the existing guide or split substantial sections into linked tutorials. | Real screenshots; permission choices; one successful visit/route; backup and restore example; free tracking versus paid export explained. |
| 2 | Vox.md | Publish “Capture into an Obsidian daily note from iPhone.” | Exact preset setup, heading placement, sample Markdown, failed-delivery recovery, and what requires an initial model download. |
| 3 | GitSync.md | Add a decision section to the existing Obsidian guide: GitSync.md versus Obsidian Sync and Working Copy. | Current first-party competitor sources; platform and purchase differences; conflict recovery; iOS background limits; no unsupported superiority claims. |
| 4 | Health.md | Improve the existing Apple Health → CSV and Obsidian tutorials with a short answer, output preview, and format decision table. | Synthetic sample output; units/date semantics; Apple versus Android boundaries; pricing matches released version. Preserve existing in-progress edits. |

iso.me goes first because it has the most observed referred downloads and unfinished supporting guides, not because the baseline proves an expected lift. GitSync.md is a useful commercial priority too: it has the highest attributed proceeds despite fewer downloads. Do not change pricing based on this small sample.

## Proposed first-paragraph copy

Use as a replacement introduction on an existing relevant page, subject to release verification. Keep each page's details, screenshots, limitations, and examples underneath it.

**Health.md — Apple Health to CSV page:**

> Health.md exports selected Apple Health data to CSV for spreadsheets, Markdown for an Obsidian journal, or JSON for scripts. Choose the data and date range, then save the files to a destination you control. Health.md does not keep a server copy of your health data.

**Vox.md — daily-note tutorial:**

> Vox.md sends text, links, scans, photos, and on-device voice transcripts into an Obsidian vault or Markdown folder. A Capture Preset can append entries to a daily note or place them under a chosen heading. This guide sets up one daily-note workflow and shows the resulting Markdown.

**iso.me — private location-history guide:**

> iso.me is a private location journal for iPhone that records visits and routes on your device. Tracking is free; a one-time purchase unlocks export. This guide explains location permissions, battery tradeoffs, and how to keep a backup you can restore.

**GitSync.md — Obsidian setup guide:**

> GitSync.md is a Git client for iPhone and iPad that works with repositories in iOS Files, including Obsidian vaults. Clone a repository, edit your notes, then review, commit, pull, and push changes. This guide explains setup and conflict recovery; background sync remains subject to iOS scheduling.

## Publication checklist

1. Check every public claim against the released app for the stated platform, not just unreleased source. Keep prices and trial limits identical across visible text, structured data, listing, and docs.
2. Give each tutorial a clear title, concise answer, prerequisites, tested steps, real screenshot, synthetic example output where relevant, limitations, pricing link, and store link. Use genuine review dates and name the tested version.
3. Link tutorials from the product homepage and docs; include canonical URLs in sitemaps. Redirect retired URLs to the corresponding current page. Verify crawler access through both robots and hosting/WAF settings.
4. Use factual SoftwareApplication metadata where appropriate and consistent product/developer identity. Structured data and llms.txt do not guarantee inclusion or recommendations.
5. Seek independent reviews or community feedback by sharing a useful working example, clearly identifying the developer relationship. Do not fabricate reviews, seed hidden instructions, or publish unsupported “best app” comparisons. Outreach is a separate action requiring an explicit request.

## Measurement after publication

Record deployment date, exact URLs, and app release version. Compare equal 28-day periods after allowing for reporting lag. Track ChatGPT app-referrer impressions, first-time downloads where available, total downloads, proceeds, and web referrers separately. Also track site search visibility and aggregate tutorial-to-store clicks without collecting health data, notes, or location history.

Keep the all-source baseline alongside ChatGPT and note release, pricing, advertising, and seasonal changes. More attributed proceeds can reflect purchases by earlier referred users; it does not prove a new guide caused the sale. A before/after comparison is directional evidence. App Store Connect does not expose the prompts that led to these referrals.

## Implementation boundary

This checkout contains Health.md source. The other three websites were audited publicly; their repositories and release contracts have not been inspected. Several Health.md files already contain unrelated work. This document prepares changes for review without modifying those files or publishing anything.
