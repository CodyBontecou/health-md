# Verified snippets

Reusable technical facts for blog posts. Each entry records what was checked,
when, and against what source. Posts should reference these instead of
re-asserting the fact from memory.

## CSV export header contract

The iPhone export produces one CSV file per day with the header
`Date,Category,Metric,Value,Unit,Timestamp`. The `Value` column is numeric,
`Timestamp` is ISO-8601. Summary rows omit the timestamp column; timestamped
sample rows always include all six fields.

Verified: 2026-09-26
Source: built `apple-health-to-csv` landing page HTML (contains the exact
header string); corroborated by `content/blog/export-apple-health-data-to-obsidian.md`
("CSV exports use a stable `Date,Category,Metric,Value,Unit,Timestamp` header").

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
