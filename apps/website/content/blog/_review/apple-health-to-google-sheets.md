# Claim ledger: From Apple Health to Google Sheets.

Slug: `apple-health-to-google-sheets`
Verified: 2026-09-26
Verified by: Edison (agent)
Method: mixed

## Claims

- [x] **One CSV file per day with header `Date,Category,Metric,Value,Unit,Timestamp`; `Value` numeric, `Timestamp` ISO-8601.**
  Traced to the built `apple-health-to-csv` landing page HTML (exact header
  string) and the existing Obsidian article. Registry: `verified-snippets.md` →
  "CSV export header contract".
- [x] **Summary rows omit the timestamp column; timestamped sample rows include all six fields.**
  Traced to the `apple-health-to-csv` landing page ("summary rows omit the
  timestamp column").
- [x] **Week-label formula `=YEAR(A2)&"-W"&WEEKNUM(A2,2)` is valid Google Sheets syntax; type `2` starts weeks on Monday.**
  Verified against Google Sheets function documentation 2026-09-26.
  This exact formula replaced `=TEXT(A2,"YYYY-WW")`, which is NOT valid Sheets
  syntax — that error is what created this verification system. Registry:
  `verified-snippets.md` → "Google Sheets week-label formula".
- [~] **Sheets UI labels: File > Import > Upload, "Replace spreadsheet", Data > Pivot table, Insert > Chart.**
  Spot-checked against the current Google Sheets menu structure 2026-09-26.
  Full click-through of the import flow was not performed; recommended on the
  next edit of this post.
- [x] **App Store URL `https://apps.apple.com/us/app/health-md/id6757763969`.**
  Exact match with the badge URL asserted in `test/seo-landing-pages.test.mjs`.
  Registry: `verified-snippets.md` → "App Store URL".
- [~] **Troubleshooting: open the CSV in a text editor to distinguish export vs. import problems; Format > Number fixes numbers stored as text.**
  Standard Sheets behavior, spot-checked 2026-09-26. No product-specific claim.
- [x] **Internal links resolve.**
  Covered by the site link checker: `/apple-health-export/`, `/apple-health-to-csv/`,
  `/docs/`, `/blog/query-apple-health-with-claude-or-codex/`.
- [x] **No medical advice anywhere in the post.**
  Full read-through 2026-09-26: the post is a spreadsheet tutorial.
