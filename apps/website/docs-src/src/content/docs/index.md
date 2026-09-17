---
title: Start with Health.md
description: Export health data, connect a local agent, or build with Health.md contracts.
---

<div class="docs-hero" data-strand-stage>
  <canvas class="docs-dna" data-three-strand aria-hidden="true"></canvas>
  <div class="docs-hero-copy">
    <p class="docs-eyebrow">Available now · signed Mac helper</p>
    <p>Export health data, connect a local agent, or use a versioned contract. HealthKit stays on iPhone. Health Connect stays on Android.</p>
    <div class="docs-command" aria-label="Bundled Health.md readiness command"><span aria-hidden="true">$</span> "/Applications/Health.md.app/Contents/Helpers/healthmd" doctor</div>
    <p class="docs-command-note">For a different install location, copy the helper path from <strong>Health.md for Mac → CLI</strong>.</p>
    <div class="docs-actions">
      <a class="docs-button" href="/docs/iphone-first-export/">First iPhone Export</a>
      <a class="docs-button-secondary" href="/docs/configuration/">Connect an Agent</a>
      <a class="docs-button-secondary" href="/docs/reference/">Browse Contracts</a>
    </div>
  </div>
</div>

<div class="agent-path" aria-label="Choose a Health.md goal">
  <a href="/docs/iphone-first-export/"><span>01 · Export</span><strong>Start on iPhone</strong>Authorize Apple Health, choose a folder, preview the output, and export one day.</a>
  <a href="/docs/configuration/"><span>02 · Ask</span><strong>Connect a local agent</strong>Connect Codex or Claude to the signed Mac helper. Then request a limited data scope.</a>
  <a href="/docs/reference/"><span>03 · Build</span><strong>Use stable contracts</strong>Use versioned schemas, records, evidence, fixtures, and response envelopes.</a>
</div>

<div class="reference-stats">
<div><strong>21</strong><span>bundled Mac MCP tools</span></div>
<div><strong>4</strong><span>export formats</span></div>
<div><strong>v8</strong><span>Apple public export schema</span></div>
<div><strong>0</strong><span>required Health.md cloud hops</span></div>
</div>

<p class="docs-section-kicker">Available now · macOS</p>

## Ten-minute local agent quickstart

Use the signed Mac helper with a connected iPhone. This example checks setup, lists sleep metrics, and queries one day.

```bash
HMD="/Applications/Health.md.app/Contents/Helpers/healthmd"
"$HMD" doctor
"$HMD" metrics list --category Sleep
"$HMD" query --category Sleep --yesterday
```

A ready `doctor` result uses the `healthmd.cli_doctor` schema. It gives the next action when setup is incomplete.

For Codex or Claude, configure the separate `healthmd-mcp` helper.

[Agent configuration reference →](/docs/configuration/)

<p class="docs-section-kicker">Choose by goal</p>

## Configure and connect

<div class="related">
  <a href="/docs/configuration/"><span>Available now · Mac</span>Connect Codex, Claude, or another stdio client.</a>
  <a href="/docs/mcp/"><span>Available now · Mac</span>Review the 21 bundled tools, private visualizations, and portable preview.</a>
  <a href="/docs/cli/"><span>Available now · Mac</span>Install the helper, check setup, and query data.</a>
  <a href="/docs/agents/"><span>Architecture</span>Review scope, trust, evidence, retention, and privacy.</a>
</div>

<p class="docs-section-kicker">Everyday operations</p>

## Query, extract, and automate

<div class="related">
  <a href="/docs/agent-queries/"><span>Typed queries</span>Query metrics, sleep, workouts, comparisons, coverage, and evidence.</a>
  <a href="/docs/cli-direct/"><span>Preview · portable CLI</span>Pair a phone through Manual IP or Tailscale. Review current device compatibility.</a>
  <a href="/docs/cli-extract/"><span>Source data</span>Extract schema-v8 days, source records, projections, or JSONL.</a>
  <a href="/docs/cli-jobs/"><span>Reliable runs</span>Handle timeouts, unknown outcomes, resumed jobs, canceled jobs, and partial results.</a>
  <a href="/docs/agent-api/"><span>Low level</span>Use loopback routes for queries, evidence, cursors, refreshes, and durable jobs.</a>
  <a href="/docs/reference/integration-recipes/"><span>Patterns</span>Parse and validate Health.md output without changing its contract.</a>
</div>

<p class="docs-section-kicker">Stable interfaces</p>

## Data contracts and structures

<div class="related">
  <a href="/docs/reference/"><span>Contract map</span>Browse schemas, metrics, formats, records, and test fixtures.</a>
  <a href="/docs/reference/api-and-cli/"><span>Automation</span>Review envelopes, routes, exit behavior, and generated examples.</a>
  <a href="/docs/reference/evidence-packets/"><span>Agent results</span>Review typed values, coverage, missing data, operations, and stable identities.</a>
  <a href="/docs/reference/daily-records/"><span>Schema v8</span>Review the public source document and its ownership rules.</a>
  <a href="/docs/shared-metric-registry/"><span>Vocabulary</span>Use stable metric IDs, categories, units, and profile metadata.</a>
  <a href="/docs/reference/generated/"><span>Machine-readable</span>Open canonical fields, fixtures, message lists, and CLI contracts.</a>
</div>

<p class="docs-section-kicker">Product workflows</p>

## Apps and exports

### Export profiles

- Choose Summary or shared Detailed Time-Series output. Lossless Health Records is available only on Apple platforms.
- Save separate settings, destinations, and schedules in local profiles.
- A stop or cancel action affects only the active attempt. Completed dates stay complete, and unresolved dates remain available to retry. The action does not disable a recurring schedule.

Read [Export profiles](/docs/export-profiles/) for stable IDs, automation, destination history, and failure behavior.

<div class="related">
  <a href="/docs/export-profiles/"><span>Repeatable workflows</span>Save settings, destinations, schedules, and an automation identity.</a>
  <a href="/docs/iphone-first-export/"><span>Start here · iPhone</span>Authorize Apple Health, select a folder, preview output, and verify files.</a>
  <a href="/docs/android/"><span>Android</span>Select a document-provider folder and configure Android automation.</a>
  <a href="/docs/export/"><span>Files</span>Export a date range as Markdown, CSV, JSON, or Obsidian Bases.</a>
  <a href="/docs/format/"><span>Structure</span>Set units, dates, frontmatter, filenames, and write behavior.</a>
  <a href="/docs/scheduling/"><span>Background</span>Review schedules, recovery, and platform timing limits.</a>
  <a href="/docs/shortcuts/"><span>Automation</span>Start exports, summaries, and status checks from Apple workflows.</a>
</div>

<p style="margin-top:48px; color:var(--sl-color-gray-3); font-size:12px; font-family:var(--sl-font-mono);">Documentation structure updated 2026-08-31</p>
