---
title: "Format Customization"
description: "Control output formatting without changing what's collected. Pick a file format, date / time / unit conventions, customize the YAML frontmatter, and choose a Markdown template."
---

## Output formats
<div class="options">
<div class="option"><strong>Markdown (.md)</strong><p>Default. One file per day. YAML frontmatter (optional) plus headed sections per category.</p></div>
<div class="option"><strong>Obsidian Bases</strong><p>Markdown with structured frontmatter optimized for Obsidian's <a href="https://help.obsidian.md/Plugins/Bases">Bases</a> plugin. Numeric properties stay numeric, dates stay dates.</p></div>
<div class="option"><strong>JSON</strong><p>One JSON file per day. Easy to script against. Top-level fields include <code>date</code>, <code>type</code>, and <code>units</code>, followed by category objects.</p></div>
<div class="option"><strong>CSV</strong><p>One CSV file per day using <code>Date,Category,Metric,Value,Unit,Timestamp</code>. Daily aggregates leave <code>Timestamp</code> blank; sample rows include an ISO timestamp.</p></div>
</div>

## Date &amp; time
<p>Pickers for date format (e.g. <code>YYYY-MM-DD</code>, <code>MMM d, yyyy</code>) and time format (12-hour, 24-hour). The preview block at the bottom of the screen updates live as you change settings.</p>

## Unit system
<p>Toggle between <em>Metric</em> and <em>Imperial</em>. Affects distance (m/km vs ft/mi), weight (kg vs lb), temperature (°C vs °F), and a few others. HealthKit always stores in canonical units; conversion happens at export time.</p>

## Frontmatter fields
<p>Tapping <em>Frontmatter Fields</em> opens a dedicated editor:</p>
<ul>
<li>Toggle individual built-in fields (date, weekday, totalSteps, etc.)</li>
<li>Rename a field — useful if your Obsidian setup expects different keys</li>
<li>Add custom fields with static values (e.g. <code>type: health</code>)</li>
<li>Add placeholder fields that resolve at export time (e.g. <code>weather: {weather}</code>)</li>
</ul>

## Markdown template
<p>Tapping <em>Markdown Template</em> opens a template editor with several built-in styles (Compact, Sections, Detailed) plus a fully custom mode. The preview block shows the result for today's data.</p>

## Preview
<p>At the bottom of the Format screen, a live preview block renders today's data with your current settings. This is the fastest way to iterate — change a toggle, look at the preview, repeat.</p>

## Related

<div class="related">
  <a href="/docs/metrics/"><span>What</span>Health Metrics — pick the data first.</a>
  <a href="/docs/individual-tracking/"><span>Granular</span>Individual Tracking — different output entirely (per-entry files).</a>
  <a href="/docs/daily-notes/"><span>Obsidian</span>Daily Note Injection — uses the same frontmatter fields.</a>
</div>
