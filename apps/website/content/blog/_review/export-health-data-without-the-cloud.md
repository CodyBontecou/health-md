# Claim ledger: How to export your health data without the cloud.

Slug: `export-health-data-without-the-cloud`
Verified: 2026-09-26
Verified by: Edison (agent)
Method: traced

## Claims

- [x] **The basic workflow has no Health.md health-data server: phone reads the platform API, builds output on-device, writes to a user-chosen folder.**
  Traced to `content/blog/local-first-health-data-architecture.md` ("The
  simplest workflow has no Health.md health-data server"). Registry:
  `verified-snippets.md` → "No Health.md health-data server".
- [x] **No Health.md account is required for core export workflows.**
  Traced to the built `apple-health-export` landing page HTML (exact line:
  "No account is required for core export workflows."). Registry:
  `verified-snippets.md` → "No account required".
- [x] **The iPhone reads Apple Health through HealthKit, on-device.**
  Traced to the architecture post ("The iPhone reads Apple Health through
  HealthKit").
- [x] **User-chosen destinations (iCloud Drive, Google Drive, Obsidian Sync) follow those providers' own privacy models.**
  Traced to the architecture post ("that provider's own network and privacy
  model applies"). Wording is conservative: it claims only that the provider's
  rules apply. Registry: `verified-snippets.md` → "Provider destinations follow
  provider rules".
- [x] **The four-question checklist (where data is read, where it travels, where it rests, what leaves the device) is a framing device, not a product claim.**
  No verification needed beyond: it makes no factual assertions about any
  product.
- [x] **Internal links resolve.**
  Covered by the site link checker: `/blog/local-first-health-data-architecture/`,
  `/apple-health-export/`.
- [x] **No medical advice anywhere in the post.**
  Full read-through 2026-09-26: the post is a privacy checklist.
