# Verified snippets

Reusable technical facts for blog posts. Each entry records what was checked,
when, and against what source. Posts should reference these instead of
re-asserting the fact from memory.

## CSV export header contract

The iPhone daily export produces one CSV file per day with the header
`Date,Category,Metric,Value,Unit,Timestamp`. The `Value` column is mixed-type:
metadata and capture-status strings appear alongside numbers; selected data
can also add clock times, booleans, UUIDs, or quoted JSON. Filter by Category,
Metric, and Unit before numeric analysis. Populated `Timestamp` cells are
ISO-8601. Some summary rows have five fields without Timestamp; six-field
metadata, diagnostic, and provenance rows may have an empty Timestamp.
Timestamped sample rows have all six fields.

Verified: 2026-10-04
Source: `apps/apple/HealthMd/Shared/Export/CSVExporter.swift` and its production-generated
`apps/apple/docs/reference/generated/core/summary-day.csv`, `lossless-day.csv`,
and `csv-row-contracts.md` fixtures. The fixtures are produced by
`apps/apple/HealthMdTests/Documentation/GeneratedExportDocumentation.swift`.
`test/blog-export-workflows.test.mjs` checks the article and evidence against
these producer artifacts.

## Google Sheets week-label formula

`=YEAR(A2)&"-W"&WEEKNUM(A2,2)` turns a date into a `2026-W39`-style week
label. `WEEKNUM(date, [type])` with type `2` starts weeks on Monday.

Verified: 2026-09-26
Source: Google Sheets function documentation — `WEEKNUM` accepts an optional
type argument; type `2` means the week begins on Monday.
Note: `TEXT(date,"YYYY-WW")` is NOT valid Sheets syntax and must never be
used; a post shipped with it once (fixed 2026-09-26).

## App Store URL

`https://apps.apple.com/us/app/health-md/id6757763969`

Verified: 2026-09-26
Source: exact match with the App Store badge URL asserted in
`test/seo-landing-pages.test.mjs` and present on the live landing pages.

## No account required

"No account is required for core export workflows. Health permissions, files,
and settings stay under the controls of your device and the destinations you
pick."

Verified: 2026-09-26
Source: built `apple-health-export` landing page HTML (exact line).

## No Health.md health-data server

"The simplest workflow has no Health.md health-data server: the phone reads
an authorized platform API, Health.md builds the selected output on-device,
and writes into a folder the user chose."

Verified: 2026-10-22
Source: `apps/apple/HealthMd/Shared/Managers/VaultManager.swift`, native export
plans, and the separately selected `APIEndpointExportRunner.swift`; Android
folder export remains a separate destination from `RawSnapshotApiClient.kt`.
Physical #182 synthetic local-folder export on producer source now merged in
main `4da74b120e2858c29ee4a77aac0bb46810668974` also exercised this Apple path.
This fact excludes intentionally selected API/cloud destinations and does not
claim that a file provider or paired computer has no network or storage copy.

## Provider destinations follow provider rules

"If the user chooses iCloud Drive, Google Drive, OneDrive, Syncthing, or
Obsidian Sync, that provider's own network and privacy model applies."

Verified: 2026-09-26
Source: `content/blog/local-first-health-data-architecture.md` (exact
statement). Wording is intentionally conservative: it claims only that the
provider's own rules apply, nothing about what those rules are.

## Claude Projects file upload

Claude supports CSV and JSON uploads to chats and project files/knowledge.
Projects can reuse supplied context; the interface is changing during a staged
rollout. The manual file-upload tutorial provides a snapshot: a new export needs
a new upload. This does not describe every connector or agent workflow.

Verified: 2026-10-25
Source: Anthropic's current upload and Projects documentation:
https://support.claude.com/en/articles/8241126-upload-files-to-claude,
https://support.claude.com/en/articles/9517075-what-are-projects, and
https://support.claude.com/en/articles/9519177-how-can-i-create-and-manage-projects.
Instructions are documentation-traced; no authenticated upload was run.

## ChatGPT path is file upload

For the file-upload tutorial, the ChatGPT path is to attach an exported file
to a conversation. This shares a snapshot and does not configure the local
CLI/MCP connection described as the alternative. It is not a claim about
every ChatGPT integration or Health.md MCP topology.

Verified: 2026-10-04
Source: `content/blog/analyze-apple-health-with-claude.md`, Step 2 and its
local-query alternative. This entry describes the tutorial's chosen workflow,
not a product-wide capability limit. `test/blog-workflow-privacy.test.mjs`
checks that scope in the article, ledger, and this entry.

## Sleep CSV summary and interval rows

Apple daily CSV sleep durations use seconds in the production v8 example.
Compatibility summary rows can omit Timestamp; a timestamped Sleep Stage row
contains a label plus duration in Value and an ISO-8601 start Timestamp.
Keep daily totals separate from individual interval rows when calculating.
Health.md assigns a sleep session to its local start day.

Verified: 2026-10-25
Source: `apps/apple/HealthMd/Shared/Export/CSVExporter.swift` Sleep block,
`apps/apple/docs/reference/generated/core/summary-day.csv`, and
`docs-src/src/content/docs/sleep-date-attribution.md`. The website's
`test/sleep-export-sample.test.mjs` checks the published excerpt against the
producer fixture. This is source tracing, not a newly executed device export.
