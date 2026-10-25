# Article verification system

This directory records claim checks for blog articles. The site build checks
structure, links and the sitemap; the ledgers record evidence and its limits.

The local-export article remains an unpublished draft. Its dated ledger
is historical review material, not current publication approval. Before publishing,
recheck product behavior, third-party instructions, privacy disclosures and linked
destinations; record the evidence and restore verification frontmatter only after
that review. The Google Sheets and Claude guides were rechecked and published on 2026-10-25
using source and official-documentation tracing; their ledgers record the unrun UI
walkthrough and verification limits.

## The rule

Any post with `draft: false` whose `date` or `updated` is on or after
**2026-09-26** must have all three frontmatter fields:

```yaml
verified: "2026-09-26"        # date the claims were checked (YYYY-MM-DD)
verified_by: "Edison (agent)" # who checked them
verified_method: mixed        # executed | traced | mixed
```

…and a claim ledger at `_review/<slug>.md` listing every checkable statement
with its verification evidence.

`test/blog-verification.test.mjs` enforces this. Flipping `draft: false`
without verification fails the test suite.

## Verification methods

- **executed** — the steps were run in the real product (e.g. the export was
  performed, the formula was entered in Google Sheets, the UI was clicked
  through). Strongest.
- **traced** — every claim was traced to an authoritative source: repo source
  code, the built landing pages, official product documentation. No claim rests
  on memory.
- **mixed** — combination of the two.

## Ledger statuses

- `- [x]` verified — claim checked, evidence recorded.
- `- [~]` spot-checked — claim matches official docs or standard product
  behavior but was not executed end-to-end. The ledger must say what was not
  done (e.g. "UI labels spot-checked against current Sheets menus; full
  click-through not performed").
- `- [ ]` unverified — fails the gate. Do not publish.

## Reusable facts

Technical claims that appear in more than one post (CSV header contract,
tested formulas, the App Store URL, the no-account / no-cloud statements)
live in `verified-snippets.md` with their verification evidence. New posts
reference the registry instead of re-asserting from memory, so a fact cannot
be wrong in two places.

## Grandfathering

Posts published before 2026-09-26 predate this system and are exempt until
they are next updated (the gate keys off `date` and `updated`). Backfilling
ledgers for older posts is encouraged but not required.

## Adding a new post

1. Write the draft with `draft: true`.
2. Extract every checkable claim (formulas, UI labels, column names, product
   statements, URLs) into `_review/<slug>.md`.
3. Verify each claim by executing or tracing it. Record the source.
4. Reuse `verified-snippets.md` entries where they apply; add new ones for
   new reusable facts.
5. Set the three `verified` frontmatter fields and flip `draft: false`.
6. Run `node --test test/blog-verification.test.mjs`, then the full build.
