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

Verified: 2026-09-26
Source: `content/blog/local-first-health-data-architecture.md`
("The simplest workflow has no Health.md health-data server").

## Provider destinations follow provider rules

"If the user chooses iCloud Drive, Google Drive, OneDrive, Syncthing, or
Obsidian Sync, that provider's own network and privacy model applies."

Verified: 2026-09-26
Source: `content/blog/local-first-health-data-architecture.md` (exact
statement). Wording is intentionally conservative: it claims only that the
provider's own rules apply, nothing about what those rules are.

## Claude Projects file upload

Claude Projects accept uploaded files as persistent project knowledge across
conversations in that Project. CSV is a supported upload type. Adding a new
export requires a new upload — Claude only sees the files it was given.

Verified: 2026-09-26
Source: Anthropic's Projects and file-upload documentation (Projects help
page; file-upload help lists CSV among supported types).

## ChatGPT path is file upload

Health.md's MCP surface is the CLI/Mac MCP server (repo: `apps/cli`
`healthmd-mcp` crate; Mac app bundles an MCP server). The consumer ChatGPT
product has no MCP client connection to Health.md, so file upload is the
accurate path there.

Verified: 2026-09-26
Source: repository structure (`apps/cli`, Mac MCP server docs); conservative
wording — asserts only what the file-upload path is, not a claim about
OpenAI's roadmap.
