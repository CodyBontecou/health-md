# Claim ledger: Analyze your Apple Health data with Claude. No terminal, no code.

Slug: `analyze-apple-health-with-claude`
Verified: 2026-09-26
Verified by: Edison (agent)
Method: mixed

## Claims

- [x] **Health.md iPhone app exports Apple Health as CSV/JSON/Markdown/Obsidian files.**
  Traced to the `apple-health-export` landing page ("Export Apple Health Data —
  CSV, JSON, Markdown & Obsidian").
- [x] **Claude Projects accept uploaded files as persistent project knowledge; CSV is a supported type.**
  Traced to Anthropic's Projects and file-upload documentation (2026-09-26).
  Registry: `verified-snippets.md` → "Claude Projects file upload".
- [x] **A new export requires a new upload; Claude only sees the file you hand it.**
  Follows from the Project knowledge model (no live file sync; manual re-upload).
  Conservative wording, no sync capability claimed.
- [x] **ChatGPT path is file upload; there is no MCP connection to Health.md.**
  Traced to repo (`apps/cli` `healthmd-mcp` crate, Mac bundled MCP server) —
  Health.md's MCP surface is CLI/Mac-side. Registry: `verified-snippets.md` →
  "ChatGPT path is file upload".
- [x] **The six example prompts contain no diagnosis or treatment claims.**
  Reviewed individually 2026-09-26: all ask for patterns, summaries, and
  correlations, never diagnoses, treatments, or medical advice.
- [x] **"Claude is not a doctor, and this isn't medical advice" disclaimer is present.**
  Checked in the post source; rendered in the prompts section.
- [x] **Internal links resolve.**
  Covered by the site link checker (`check-site-links.mjs`): `/health-data-for-ai/`,
  `/blog/query-apple-health-with-claude-or-codex/`, `/docs/guides/connect-agent/`.
- [x] **No medical advice anywhere in the post.**
  Full read-through 2026-09-26: the post describes a file-upload workflow only.
