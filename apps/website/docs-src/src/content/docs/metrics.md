---
title: "Health Metrics"
description: "Pick which of the 171 HealthKit metrics across 18 categories you want exported. Search, toggle whole categories at once, or drill in for per-metric control."
---

<div class="callout">
<strong>Android note.</strong>
<p style="margin-top:6px;">This page documents the Apple Health metric picker and generated HealthKit data reference. The Android app exposes 106 Health Connect metrics; see the <a href="/docs/android/">Android guide</a> for Health Connect setup and platform-specific behavior.</p>
</div>

## Layout
<div class="options">
<div class="option"><strong>Counts header</strong><p>Live readout: <em>X of 171 metrics · Y of 18 categories</em>. Tap-and-hold to copy the exact selection state to clipboard.</p></div>
<div class="option"><strong>All Metrics Enabled</strong><p>Master toggle that flips every category on or off. Useful as a starting point — turn everything on, then disable what you don't care about.</p></div>
<div class="option"><strong>Search</strong><p>Live filter across metric names and identifiers. Try "heart", "sleep", "vo2".</p></div>
</div>

## Categories
<p>18 HealthKit categories: Sleep, Activity, Heart, Respiratory, Vitals, Body Measurements, Mobility, Cycling, Nutrition, Vitamins, Minerals, Hearing, Mindfulness, Reproductive Health, Symptoms, Medications, Other, and Workouts. Each row shows the on/off state and the live count of enabled metrics within it.</p>

<p>Tap a category to drill into its metrics. Each metric has its own toggle and HealthKit identifier. The dot color reflects whether HealthKit currently has data for that metric on this device.</p>

## Selection scope
<p>Your metric selection drives <em>everything</em>:</p>
<ul>
<li>Daily exports — only enabled metrics appear in the file</li>
<li>Individual Tracking — only enabled metrics get per-entry files</li>
<li>Daily Note Injection — only enabled metrics merge into frontmatter</li>
<li>Shortcuts — date-range exports use the same selection</li>
</ul>

<div class="callout">
<strong>Pro tip.</strong>
<p style="margin-top:6px;">Start narrow. Enable Sleep, Activity, and Heart. Run an export. See what the file looks like. Then add more categories. It's faster to add than to wade through a 50-line file with metrics you don't care about.</p>
</div>

## Related

<div class="related">
  <a href="/docs/data-reference/"><span>Reference</span>Data Reference — every Apple metric, key, unit, and export structure.</a>
  <a href="/docs/android/"><span>Android</span>Android App — Health Connect setup, metrics, destinations, and automation.</a>
  <a href="/docs/format/"><span>How</span>Format — change how the metrics you pick are written.</a>
  <a href="/docs/individual-tracking/"><span>Granular</span>Individual Tracking — also write one file per timestamped entry.</a>
  <a href="/docs/daily-notes/"><span>Obsidian</span>Daily Note Injection — push these metrics into your daily notes.</a>
</div>
