---
title: "Individual Entry Tracking"
description: "Optionally write one Markdown file for each timestamped workout, blood-pressure reading, or mood log. Include the timestamp in the filename."
---

## When to use it
<p>Daily exports give you one summary file per day. Use <em>Individual tracking</em> to cite one event or link to a specific workout. You can also link a mood entry to a weekly review.</p>

<p>This is on top of the daily export, not instead. With both on, you get both kinds of files.</p>

## Two-step setup
<p>The settings UI is intentionally a two-step funnel:</p>
<ol>
<li><strong>Master switch.</strong> Turn the feature on globally.</li>
<li><strong>Per-metric selection.</strong> Choose <em>which</em> metrics get individual files. Most people do not want a file per heart-rate reading (10,000 / day), but they do want one per workout (~1 / day).</li>
</ol>

## Quick actions
<div class="options">
<div class="option"><strong>Enable Suggested Metrics</strong><p>Sensible defaults: mood, symptoms, workouts, blood pressure, blood glucose. The metrics where one-file-per-entry actually makes sense.</p></div>
<div class="option"><strong>Enable All Metrics</strong><p>Everything. Be careful, this can produce thousands of files per day.</p></div>
<div class="option"><strong>Disable All Metrics</strong><p>Clears the per-metric selection without flipping the master switch.</p></div>
</div>

## Folder structure
<div class="options">
<div class="option"><strong>Entries Folder</strong><p>Vault-relative path where individual files land. Default: <code>entries</code>.</p></div>
<div class="option"><strong>Organize by Category</strong><p>If on, entries are nested under category subfolders (<code>entries/workouts/</code>, <code>entries/symptoms/</code>). If off, all entries sit in one flat folder.</p></div>
</div>

## Filename template
<p>Default: <code>{date}_{time}_{metric}</code>. Available placeholders: <code>{date}</code>, <code>{time}</code>, <code>{metric}</code>, <code>{category}</code>. Example output:</p>

<div class="doc-diagram folder-tree" aria-label="Example individual entry file tree">
<span>{vault}/entries/</span>
<span>├─ workouts/2026_07_14_0920_workouts_workouts_71000000-0000-0000-0000-000000000008.md</span>
<span>├─ symptoms/2026_07_14_0916_symptom_headache_symptom_headache_71000000-0000-0000-0000-000000000002.md</span>
<span>└─ vitals/2026_07_14_0918_blood_pressure_blood_pressure_71000000-0000-0000-0000-000000000004.md</span>
</div>

<p>Canonical source-backed entries append the selected metric and lowercase HealthKit UUID after the configured filename. This keeps the same source record stable across reruns and prevents same-minute collisions. UUID-free compatibility entries retain the shorter legacy filename behavior.</p>

<div class="callout">
<strong>Heads up.</strong>
<p style="margin-top:6px;">Only categories with an enabled metric in <em>Health Metrics</em> appear here. Enable a metric there first. Then return here to select per-entry tracking. Before you automate paths, read the <a href="/docs/reference/individual-entry-tracking/">source-record identity contract</a> and generated <a href="/docs/reference/generated/individual/filename-path-matrix/">filename matrix</a>.</p>
</div>

## Related

<div class="related">
  <a href="/docs/metrics/"><span>Prereq</span>Health Metrics, enable metrics first.</a>
  <a href="/docs/format/"><span>Output</span>Format, applies to entry files too.</a>
  <a href="/docs/daily-notes/"><span>Alt</span>Daily Note Injection, different way to attach metrics to notes.</a>
  <a href="/docs/reference/individual-entry-tracking/"><span>Contract</span>Individual Entry Reference, UUID identity, frontmatter, specialized entries, and compatibility fallbacks.</a>
</div>
