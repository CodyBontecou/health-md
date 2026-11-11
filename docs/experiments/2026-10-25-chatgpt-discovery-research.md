# ChatGPT discovery research

**Checked:** 2026-10-25. **Scope:** official documentation for website discoverability and measurement; no production settings or listings changed. This note follows the repository's dated research briefs in `docs/experiments/`.

## What the evidence supports

- Allow **OAI-SearchBot** on public pages intended for search, and check CDN/firewall handling against OpenAI's published search-bot IP ranges. OpenAI identifies this as its search crawler and says robots changes can take about 24 hours to propagate. **GPTBot** governs potential training use independently, so training access need not be enabled to allow search. **ChatGPT-User** handles certain user-triggered visits; it does not determine search eligibility. [OpenAI crawler documentation](https://developers.openai.com/api/docs/bots)
- Crawl access is a prerequisite, not evidence of a future recommendation. The reviewed OpenAI documentation does not establish a ranking formula or a guarantee that a particular app will be recommended. Do not promise lift from enabling a bot, schema markup, or an `llms.txt` file.
- Google's current AI-search guidance emphasizes original, useful content and standard crawl/index fundamentals. It advises against overfocusing on structured data and says there is no special schema.org markup required for generative AI search. This is **Google-specific evidence**, not proof about ChatGPT's ranking. [Google guide](https://developers.google.com/search/docs/fundamentals/ai-optimization-guide)

## Practical changes to evaluate

These are implementation hypotheses, not demonstrated ranking factors:

1. Test each app's homepage, important use-case pages, and documentation for useful public HTML, working internal links, correct canonical URLs, and bot challenges. Check existing robots rules before adding redundant bot groups; do not alter training preferences as a discovery shortcut.
2. Give each app a clear factual identity: who it serves, the task it completes, supported platforms, output/integration details, current free/paid boundaries, and important limitations. Keep the website and App Store description consistent.
3. Publish a small number of original workflow guides with screenshots and reproducible examples from the actual product. Prefer concrete user questions over generic “best apps” articles, unsupported superiority claims, or many thin keyword variants.
4. Ensure ordinary site navigation reaches these pages. Keep any structured data consistent with visible facts. Treat extra machine-readable files as optional documentation conveniences, not a ranking project.

## Measurement and interpretation

Use the same dates, dimensions, and metric definitions across apps. Save monthly App Referrer/ChatGPT downloads and proceeds, plus web-referrer observations. Apple attributes subsequent sales and usage to the recorded download/redownload source; a manual redownload resets attribution. Consequently, reported ChatGPT proceeds are **attributed proceeds**, not a causal estimate of incremental revenue or a count of recommendations. [Apple acquisition](https://developer.apple.com/help/app-store-connect-analytics/acquisition/acquisition/)

Apple's Proceeds metric is estimated receipts after applicable taxes and Apple's commission; Sales is a separate gross customer-billing metric. [Apple sales definitions](https://developer.apple.com/help/app-store-connect-analytics/monetization/sales/)

For websites, count observed `chatgpt.com`/legacy `chat.openai.com` referrers and incoming `utm_source=chatgpt.com` separately from crawler requests. This is a suggested analytics convention: it cannot identify visits without attribution signals or total recommendation frequency. Inspect the actual incoming URLs before relying on a universal UTM assumption.

Annotate deployment dates and review at 30/60/90 days against the preceding equal-length period. Track site visits, App Store downloads, and proceeds separately; changes in pricing, app releases, other marketing, and assistant usage can confound the result. A fixed set of realistic search prompts can reveal incorrect product descriptions, but repeated prompt sampling is not representative market-share measurement.

## Source caveat

Search results still expose an older OpenAI Publishers and Developers FAQ under article `12627856`, including UTM guidance. Opening that URL on the research date redirected to an unrelated Atlas retirement article. Its cached snippet was **not** used as current evidence. The working crawler documentation above is the authority for bot behavior.
