---
title: "Daily Note Injection"
description: "Merge selected health metrics into the YAML frontmatter (and optionally the body) of your existing daily notes — the ones you write in Obsidian or any other Markdown app."
---

## What it does
<p>If you keep daily notes (e.g. <code>Daily/2026-04-28.md</code>), turn this on and the app will <em>merge</em> your selected metrics into the YAML frontmatter of those notes on every export — without touching the rest of your note content.</p>

<div class="doc-diagram merge-preview" aria-label="Daily note frontmatter before and after Health.md merge">
<div class="merge-card">
<strong>Before</strong>
<pre><code>---
title: Tuesday note
mood: focused
---

Wrote launch notes...</code></pre>
</div>
<div class="merge-card">
<strong>After export</strong>
<pre><code>---
title: Tuesday note
mood: focused
steps: 12642
sleep_total_hours: 7.31
workout_count: 1
---

Wrote launch notes...</code></pre>
</div>
</div>

<p>Optionally, the app can also inject Markdown sections (Sleep, Activity, Heart, etc.) into the note body. Those sections are <em>app-managed</em>: replaced cleanly on each export. Headings you write yourself stay untouched.</p>

## Location
<div class="options">
<div class="option"><strong>Folder</strong><p>Vault-relative path to your daily notes folder. Default <code>Daily</code>. Leave empty to target the vault root. Examples: <code>Daily</code>, <code>Journal/Daily</code>.</p></div>
<div class="option"><strong>Filename</strong><p>Pattern for the note filename without extension. Default <code>{date}</code> resolves to <code>2026-04-28</code>.</p></div>
</div>

## Filename placeholders
<p>Mix and match:</p>
<ul>
<li><code>{date}</code> — full ISO date (<code>2026-04-28</code>)</li>
<li><code>{year}</code>, <code>{month}</code>, <code>{day}</code></li>
<li><code>{weekday}</code> — short name (<code>Tue</code>)</li>
<li><code>{monthName}</code> — long name (<code>April</code>)</li>
<li><code>{quarter}</code> — Q1 / Q2 / Q3 / Q4</li>
</ul>
<p>Example: <code>{year}/{monthName}/{date}-{weekday}</code> → <code>2026/April/2026-04-28-Tue.md</code>. The preview line below the field shows the resolved path live.</p>

## Options
<div class="options">
<div class="option"><strong>Create note if missing</strong><p>If the daily note doesn't exist for a given date, create a fresh one. Leave off if you create your own daily notes via Obsidian Templater or a similar plugin.</p></div>
<div class="option"><strong>Inject metric sections</strong><p>Also write Sleep, Activity, Heart, etc. headings into the note body. App-managed, replaced cleanly on each export. Off by default.</p></div>
</div>

## Which metrics get injected
<p>Whatever you've selected in <em>Health Metrics</em>. There is no separate selector here. Change your metric selection there, and Daily Note Injection follows.</p>

## Frontmatter preview
<p>The bottom of the Daily Note Injection screen has a live preview of the frontmatter that will be merged. This updates as you change metric selection or the format customization frontmatter fields.</p>

<div class="callout">
<strong>How merging works.</strong>
<p style="margin-top:6px;">If your existing daily note already has frontmatter, the app preserves your keys and adds/updates only the keys it owns. App-managed body sections are wrapped in HTML comments so re-runs are idempotent.</p>
</div>

## Related

<div class="related">
  <a href="/docs/metrics/"><span>Prereq</span>Health Metrics — pick what gets injected.</a>
  <a href="/docs/format/"><span>Format</span>Frontmatter Fields editor — rename keys, add custom fields.</a>
  <a href="/docs/individual-tracking/"><span>Granular</span>Individual Tracking — alternative for per-event tracking.</a>
</div>
