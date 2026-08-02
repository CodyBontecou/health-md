---
title: Start with Health.md.
description: Export Apple Health or Health Connect data, connect the signed Mac helper to a local agent, and build against versioned Health.md contracts.
---

<div class="docs-hero" data-strand-stage>
  <canvas class="docs-dna" data-three-strand aria-hidden="true"></canvas>
  <div class="docs-hero-copy">
    <p class="docs-eyebrow">Available now · signed Mac helper</p>
    <p>Export health data from your phone, connect a local agent through the signed Mac helpers, or build against versioned contracts. HealthKit reads stay on iPhone and Health Connect reads stay on Android.</p>
    <div class="docs-command" aria-label="Bundled Health.md readiness command"><span aria-hidden="true">$</span> "/Applications/Health.md.app/Contents/Helpers/healthmd" doctor</div>
    <p class="docs-command-note">Installed somewhere else? Copy the bundled helper path from <strong>Health.md for Mac → CLI</strong>.</p>
    <div class="docs-actions">
      <a class="docs-button" href="/docs/iphone-first-export/">First iPhone Export</a>
      <a class="docs-button-secondary" href="/docs/configuration/">Connect an Agent</a>
      <a class="docs-button-secondary" href="/docs/reference/">Browse Contracts</a>
    </div>
  </div>
</div>

<div class="agent-path" aria-label="Choose a Health.md goal">
  <a href="/docs/iphone-first-export/"><span>01 · Export</span><strong>Start on iPhone</strong>Authorize Apple Health, choose a folder, preview the output, and run a first export.</a>
  <a href="/docs/configuration/"><span>02 · Ask</span><strong>Connect a local agent</strong>Use the signed Mac MCP helper with Codex, Claude, or another stdio client.</a>
  <a href="/docs/reference/"><span>03 · Build</span><strong>Use stable contracts</strong>Integrate schemas, records, evidence, generated fixtures, and exact envelopes.</a>
</div>

<div class="reference-stats">
<div><strong>21</strong><span>bundled Mac MCP tools</span></div>
<div><strong>4</strong><span>export formats</span></div>
<div><strong>v7</strong><span>public export schema</span></div>
<div><strong>0</strong><span>required Health.md cloud hops</span></div>
</div>

<p class="docs-section-kicker">Available now · macOS</p>

## Five-minute local agent quickstart

Open Health.md on Mac, then open Health.md on the paired iPhone and wait for connectivity. The bundled helper checks readiness without returning health values, lists Sleep metrics, and runs a one-day query:

```bash
HMD="/Applications/Health.md.app/Contents/Helpers/healthmd"
"$HMD" doctor
"$HMD" metrics list --category Sleep
"$HMD" query --category Sleep --yesterday
```

A ready `doctor` result uses the `healthmd.cli_doctor` schema and includes next actions when setup is incomplete. For Codex or Claude, continue to [Configure your agent](/docs/configuration/) and point the client at the separate signed `healthmd-mcp` helper.

<p class="docs-section-kicker">Choose by goal</p>

## Configure and connect

<div class="related">
  <a href="/docs/configuration/"><span>Available now · Mac</span>Configuration — connect Codex, Claude, or another stdio client to the signed MCP helper.</a>
  <a href="/docs/mcp/"><span>Available now · Mac</span>MCP server &amp; App — discover 21 bundled tools, render private visualizations, and understand the portable preview.</a>
  <a href="/docs/cli/"><span>Available now · Mac</span>Health.md CLI — install the bundled helper, inspect readiness, query data, and distinguish the portable preview.</a>
  <a href="/docs/agents/"><span>Architecture</span>Agent context — learn request scope, local trust, encrypted context, evidence, retention, and privacy.</a>
</div>

<p class="docs-section-kicker">Everyday operations</p>

## Query, extract, and automate

<div class="related">
  <a href="/docs/agent-queries/"><span>Typed queries</span>Ask for metrics, sleep sessions, workouts, comparisons, coverage, and factual evidence.</a>
  <a href="/docs/cli-direct/"><span>Preview · portable CLI</span>Direct iPhone access — understand Manual IP or Tailscale pairing before standalone packaging is released.</a>
  <a href="/docs/cli-extract/"><span>Source data</span>Canonical extraction — acquire selected schema-v7 days, source records, projections, or JSONL.</a>
  <a href="/docs/cli-jobs/"><span>Reliable runs</span>Durable jobs — handle timeouts, unknown outcomes, resume, cancellation, and partial results safely.</a>
  <a href="/docs/agent-api/"><span>Low level</span>Loopback API — use exact query, evidence, cursor, refresh, and durable job routes.</a>
  <a href="/docs/reference/integration-recipes/"><span>Patterns</span>Integration recipes — parse and validate Health.md outputs without weakening their contracts.</a>
</div>

<p class="docs-section-kicker">Stable interfaces</p>

## Data contracts and structures

<div class="related">
  <a href="/docs/reference/"><span>Contract map</span>Export reference — browse schemas, metrics, formats, records, and interoperability fixtures.</a>
  <a href="/docs/reference/api-and-cli/"><span>Automation</span>API &amp; CLI contracts — inspect envelopes, routes, exit behavior, and generated examples.</a>
  <a href="/docs/reference/evidence-packets/"><span>Agent results</span>Queries &amp; evidence — typed values, coverage, missingness, operations, and deterministic identities.</a>
  <a href="/docs/reference/daily-records/"><span>Schema v7</span>Daily records — understand the public source document and its ownership rules.</a>
  <a href="/docs/shared-metric-registry/"><span>Vocabulary</span>Metric registry — use stable cross-platform metric IDs, categories, units, and profile metadata.</a>
  <a href="/docs/reference/generated/"><span>Machine-readable</span>Generated artifacts — open canonical fields, fixtures, message inventories, and CLI contracts.</a>
</div>

<p class="docs-section-kicker">Product workflows</p>

## Apps and exports

<div class="related">
  <a href="/docs/iphone-first-export/"><span>Start here · iPhone</span>First export — authorize Apple Health, choose a folder, preview output, and verify written files.</a>
  <a href="/docs/android/"><span>Android</span>Health Connect — choose a document-provider folder and configure platform automation.</a>
  <a href="/docs/export/"><span>Files</span>Export — run explicit date ranges in Markdown, CSV, JSON, or Obsidian Bases.</a>
  <a href="/docs/format/"><span>Structure</span>Format customization — control units, dates, frontmatter, filenames, and write behavior.</a>
  <a href="/docs/scheduling/"><span>Background</span>Scheduling — understand daily and weekly export behavior and platform limits.</a>
  <a href="/docs/shortcuts/"><span>Automation</span>Shortcuts &amp; App Intents — trigger exports, summaries, and status checks from Apple workflows.</a>
</div>

<p style="margin-top:48px; color:var(--sl-color-gray-3); font-size:12px; font-family:var(--sl-font-mono);">Documentation structure updated 2026-08-02</p>
