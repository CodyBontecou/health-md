---
title: "Query Apple Health with Claude or Codex using the CLI preview"
description: "Connect the standalone Health.md MCP preview to an open iPhone, run a seven-day Apple Health query, and verify dates, units, coverage and pagination."
lead: "Use the standalone direct-phone preview for one explicit Apple Health question, then verify the returned scope and coverage. The bundled Mac helper has a separate setup path."
date: "2026-09-22T13:20:00.000Z"
updated: "2026-10-27"
verified: "2026-10-27"
verified_by: "Codex (agent)"
verified_method: traced
category: "Workflow guide"
related:
  - healthmd-cli-direct-iphone-mcp
  - analyze-apple-health-with-claude
  - local-first-health-data-architecture
draft: false
tags:
  - healthmd
  - mcp
  - codex
  - claude
  - apple-health
---

A useful health-data agent should not begin with “read everything.” It should begin by checking the connection, discovering exact metric IDs, and asking a bounded question with visible coverage.

Health.md's standalone CLI and MCP server support that workflow over a direct, authenticated connection to an open, paired iPhone. The iPhone performs the Apple Health read. There is no Health.md account or Health.md health-data cloud in the path.

## Choose the connection before setup

This article uses the **standalone CLI/MCP preview** on macOS, Linux or Windows with an open, compatible iPhone. It is not the signed `healthmd-mcp` helper bundled with Health.md for Mac. For that released Mac component, follow [Connect an agent](/docs/guides/connect-agent/); existing encrypted Mac context and fresh iPhone acquisition have different readiness requirements. For manual file upload, use the [Claude file walkthrough](/blog/analyze-apple-health-with-claude/). Compare all three in [Health data for AI](/health-data-for-ai/).

No CLI/mobile pair is yet qualified for stable 1.0. Availability checked October 26, 2026: alpha.6 is published; alpha.7 is a draft with no assets. Check the exact release and compatible mobile build in [release status](/docs/release-status/). Runtime readiness does not establish release qualification.

## Pair the phone

Follow the [standalone CLI installation and first-export guide](/blog/healthmd-cli-direct-iphone-mcp/), verify the installed version, then use the manual pairing path:

```bash
healthmd direct pair
healthmd status
```

Open **Health.md → Direct CLI Access** on the iPhone, scan or enter the handoff, verify the computer, and keep Health.md in the foreground while a new typed request starts. Manual IP and Tailscale are supported transport choices.

Check `healthmd status` for the intended paired device and reported query readiness. Follow its blocking checks before asking an agent to read data. A paired device alone does not prove that protected data is available or that the selected dates have records.

## Connect Codex or Claude

Configure the absolute standalone `healthmd` executable with the arguments `mcp serve` in your local MCP host. Keep this separate from the Mac app's bundled helper and its credentials. The [MCP reference](/docs/mcp/) documents both surfaces.

For Codex, the combined `healthmd setup codex` command handles configuration and pairing as an alternative setup flow. If you use it, follow that flow rather than assuming the bundled Mac connection is interchangeable with direct pairing.

Discover the tools exposed by your installed build. Published preview tools and development-source tools can differ; do not copy an unreleased operation merely because it appears in a current repository checkout.

## Ask in a safe order

Tell the agent to:

1. call `healthmd_doctor`;
2. inspect `healthmd_capabilities`;
3. discover metric IDs with `healthmd_metrics`;
4. use an exact date range and the smallest useful scope;
5. preserve units, source coverage, missingness, and limitations in the answer.

The equivalent direct CLI query below uses seven inclusive dates, not all available history. First inspect the operation schema without making a phone query, then replace the example dates with the user's intended range:

```bash
healthmd query healthmd_sleep_sessions
healthmd query healthmd_sleep_sessions \
  --arguments '{"dates":{"type":"exact","range":{"start_date":"2026-10-12","end_date":"2026-10-18"}},"all_pages":true}'
```

In MCP, pass the same arguments object to `healthmd_sleep_sessions` after readiness and capability discovery. `all_pages` requests pages within that bounded date scope; it does not expand the range into lifetime history. Check any returned `next_cursor`, limits and warnings rather than assuming every page was included.

A bounded agent request can be:

> Check readiness and available capabilities first. Inspect the sleep-session input schema. Query only October 12 through October 18, 2026, inclusive, after confirming those are the dates I want. Describe the returned sessions and units, missing dates, source coverage and any pagination or warnings. Do not replace missing records with zero, infer complete history from readiness, or make a diagnosis.

### Verify the first answer

- Compare the actual returned date scope with the requested seven days. Check returned session start/end timestamps and the query window; do not infer session boundaries from a daily sleep total. Daily summaries use a separate noon-to-noon journal window. See [sleep-date attribution](/docs/sleep-date-attribution/).
- Inspect the response's units, coverage, missingness and limitations before accepting an average or trend. Seven requested dates do not guarantee seven observed nights.
- Distinguish a complete phone acquisition from a complete set of query pages. Follow the returned cursor and aggregate limits when needed.
- If readiness or acquisition fails, follow the reported next action. For interrupted durable exports, inspect the saved job and use [resume](/docs/cli-reference/resume/) rather than repeatedly creating overlapping exports. A typed-query cursor and a durable export job are different mechanisms.

These are verification steps, not a demonstrated agent answer. No model output or personal health records are needed to understand the example.

## Keep payloads out of the conversation when possible

Health.md returns structured results for bounded queries and can render approved charts. Large raw exports belong in validated private files, not automatically in model context. Ask the agent to summarize from the narrowest sufficient evidence and never expose pairing codes, credentials, private paths, routes, or clinical attachments.

A local MCP connection does not keep a remotely hosted model's processing on your computer. Review your host and model provider's handling before returning health values to that conversation. This direct-phone path does not use the separate opt-in Health.md Cloud pilot; its distinct retention terms are in the [privacy policy](/privacy-policy.html#retention).

The tools provide factual data access, not diagnosis or treatment advice. A responsible response says what was measured, in which unit and period, what coverage was available, and what remains unknown.

Android supports direct durable exports. The typed MCP queries in this guide require iPhone.

<div class="cta-row">
<a class="button" href="/docs/cli/">Open the standalone CLI docs</a>
<a class="button secondary" href="/docs/cli-reference/query/">Inspect typed query arguments</a>
<a class="button secondary" href="/health-data-for-ai/">Compare AI connection paths</a>
</div>
