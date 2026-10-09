---
title: "Analyze your Apple Health data with Claude. No terminal, no code."
description: "Export your Apple Health data with Health.md, drop the file into a Claude Project, and explore trends with example prompts."
lead: "The non-technical path: export on iPhone, upload the file, ask questions in plain language."
date: "2026-09-26T12:00:00.000Z"
updated: "2026-09-26T12:00:00.000Z"
category: "Workflow guide"
draft: false
verified: "2026-09-26"
verified_by: "Edison (agent)"
verified_method: mixed
tags:
  - healthmd
  - apple-health
  - claude
  - ai
---

Your iPhone has been quietly recording your steps, sleep, and workouts for years. The hard part was never the collecting — it was getting the data out in a shape you could actually look at. A modern AI assistant is a surprisingly good way to explore it: hand Claude a file of your health data and ask questions in plain language.

This post covers a simple file-upload workflow: export a file from the Health.md iPhone app to a folder, upload it to Claude, and chat. No terminal or code, and no server for you to run. It is deliberately limited — Claude only sees the file you hand it, and every new export means a new upload. If that tradeoff sounds fine, this is your path.

## Step 1: Export what you want to explore

In the Health.md app on your iPhone, run a folder export for the metrics and date range you're curious about. Choose CSV or JSON — both work for this, and CSV is the friendliest if you also want to peek at the data yourself in a spreadsheet.

What you'll get: one file per day. CSV uses the header `Date,Category,Metric,Value,Unit,Timestamp`. Tell Claude which `Category` and `Metric` rows you want analyzed and to check their `Unit`. The `Value` field can also contain text or JSON, so it shouldn't treat every row as a numeric measurement.

JSON is a nested daily object, with top-level `date`, `schema`, and `schema_version` fields and sections such as `activity`, `heart`, and `sleep` when those have data. It has fields and arrays, not CSV columns. Ask Claude to inspect the fields actually present, use the `units` and `time_context` metadata, and keep missing values separate from zero.

Keep the export scoped. A month of sleep and steps is plenty for your first pass; you can always export more later.

## Step 2: Upload it to a Claude Project

Create a new Project in Claude and add your exported file (or files) as project knowledge. Everything you ask inside that Project can reference the data, and the Project keeps this analysis separate from your other chats.

For ChatGPT in this file-upload workflow, start a conversation and attach the exported file. You're sharing a snapshot, not configuring the local CLI/MCP connection described below.

## Step 3: Ask about patterns, not prescriptions

Stick to descriptive questions — what happened, when, and how much. Here are prompts that work well:

- "Summarize my sleep duration trend over the last 30 days. Give me the weekly averages."
- "Which weeks had my highest step counts? List the top three with their totals."
- "Compare my workout frequency month over month for the period in this file."
- "Show me my average resting heart rate by week, and flag any weeks where the data looks sparse or missing."
- "On days I worked out, how did my step count compare to rest days?"
- "What percentage of days in this file have no recorded sleep data?"

Notice the pattern: each question names the metric, the period, and asks for a summary — not an interpretation. If Claude starts editorializing about what your numbers *mean* for your health, treat that as conversation, not counsel. **Claude is not a doctor, and this isn't medical advice** — it's a faster way to read your own records.

## A word on privacy

When you upload a file to Claude or ChatGPT, you're sharing that data with the AI provider — that's the entire point of this workflow, but do it deliberately:

- Use a dedicated Project so the data doesn't linger in unrelated chats.
- Export only the date range and metrics you actually want analyzed.
- Delete the files from the Project when you're done exploring.

For the local folder export used in this file-upload workflow, Health.md builds the file on your iPhone and does not upload it to a Health.md server. A synced folder follows its provider's rules; the AI provider receives the file you upload and handles it under its own policies.

This guide doesn't use the separate opt-in, single-owner Health.md Cloud pilot. That pilot retains only API exports intentionally sent to it, has no public signup or automatic device sync, and is not generally available. See the [privacy policy](/privacy-policy.html) for that separate destination's boundaries.

## The power-user alternative

If you're comfortable in the terminal, there's a local-query alternative: pair the Health.md CLI with your iPhone and let an agent run live, scoped queries through the local MCP server without manual file uploads. That path queries the paired phone rather than the cloud pilot's retained exports. Returned values still follow the agent's storage and model-provider settings. That's covered in [Query Apple Health locally with Claude or Codex](/blog/query-apple-health-with-claude-or-codex/).

For more on file uploads and local agent access, see [Use Apple Health with Claude, ChatGPT & Codex](/health-data-for-ai/).

<div class="cta-row">
<a class="button" href="/health-data-for-ai/">Use health data with AI</a>
<a class="button secondary" href="/docs/guides/connect-agent/">Connect an agent</a>
</div>
