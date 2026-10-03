---
title: "Query Apple Health locally with Claude or Codex."
description: "Pair the Health.md CLI with an iPhone, connect its local MCP server to Codex or Claude, and make bounded, evidence-aware health queries."
lead: "The phone performs the HealthKit read; the local Health.md MCP server gives an agent explicit tools without a Health.md health-data cloud."
date: "2026-09-22T13:20:00.000Z"
updated: "2026-09-22T13:20:00.000Z"
category: "Workflow guide"
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

## Pair the phone

Install the published CLI preview, then run:

```bash
healthmd direct pair
healthmd status
```

Open **Health.md → Direct CLI Access** on the iPhone, scan or enter the handoff, verify the computer, and keep Health.md in the foreground while a new typed request starts. Manual IP and Tailscale are supported transport choices.

The portable package is still an explicitly unqualified preview. Match the exact `healthmd-cli/v<version>` release with a compatible mobile build; do not use the repository-wide “latest release” pointer as a CLI compatibility contract.

## Connect Codex or Claude

Codex can be configured with:

```bash
healthmd setup codex
```

For Claude or another local MCP host, configure the absolute `healthmd` executable with the arguments `mcp serve`.

The published `0.1.0-alpha.7` preview exposes 19 portable tools. Current development source has 21, but its two full-corpus tools are not an alpha.7 promise. The cloud-free `serve-read-only` entry exposes only the 13 readiness and typed-query tools.

## Ask in a safe order

Tell the agent to:

1. call `healthmd_doctor`;
2. inspect `healthmd_capabilities`;
3. discover metric IDs with `healthmd_metrics`;
4. use an exact date range and the smallest useful scope;
5. preserve units, source coverage, missingness, and limitations in the answer.

A direct CLI query might look like:

```bash
healthmd query healthmd_sleep_sessions \
  --arguments '{"dates":{"type":"all_available"},"all_pages":true}'
```

“All available” is convenient for exploration but not the best default for an agent. Prefer a week or month unless the task truly needs lifetime coverage. Check `next_cursor` or request all pages explicitly; a completed phone acquisition can still have another query page.

## Keep payloads out of the conversation when possible

Health.md returns structured results for bounded queries and can render approved charts. Large raw exports belong in validated private files, not automatically in model context. Ask the agent to summarize from the narrowest sufficient evidence and never expose pairing codes, credentials, private paths, routes, or clinical attachments.

The tools provide factual data access, not diagnosis or treatment advice. A responsible response says what was measured, in which unit and period, what coverage was available, and what remains unknown.

Android supports direct durable exports, but typed MCP queries currently require iPhone. That is an explicit platform boundary, not an invitation to fabricate parity.

<div class="cta-row">
<a class="button" href="/docs/guides/connect-agent/">Connect an agent</a>
<a class="button secondary" href="/docs/mcp/">Read the MCP reference</a>
</div>
