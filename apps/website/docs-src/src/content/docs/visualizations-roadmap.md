---
title: Visualizations & Roadmap
description: Current Health.md Obsidian visualization coverage and planned charts organized by exported data type.
---

Health.md exports a schema-versioned local data set for Markdown, Obsidian Bases, JSON, and CSV. The visualization roadmap below connects that data surface to the companion Obsidian visualization plugin: what already exists, what the exported data can support next, and which categories need generic schema-aware charting.

<div class="callout">
<strong>Data source.</strong>
<p style="margin-top:6px;">This page is organized from Health.md's export schema and data dictionary: activity, sleep, heart, vitals, body, nutrition, mindfulness, medications, workouts, reproductive health, symptoms, hearing, and lifestyle/environment metrics.</p>
</div>

## Current visualization coverage

<div class="reference-stats">
<div><strong>43</strong><span>plugin renderers today</span></div>
<div><strong>18</strong><span>export data categories</span></div>
<div><strong>220+</strong><span>canonical export keys</span></div>
<div><strong>1</strong><span>generic metric layer still needed</span></div>
</div>

<span id="visualization-screenshot-gallery"></span>

## Visualization gallery

These previews render the actual Health.md Obsidian plugin visualization bundle in-browser against deterministic mock Health.md export data. They occupy the same gallery positions as the former static screenshots, but each card below is a live canvas/HTML renderer.

<script>
window.addEventListener('message', function (event) {
  var data = event.data || {};
  if (data.type !== 'healthmd-live-visualization-height' || !data.chartId || !data.height) return;
  document.querySelectorAll('iframe[data-healthmd-chart]').forEach(function (frame) {
    if (frame.dataset.healthmdChart === data.chartId) {
      frame.style.height = Math.ceil(data.height) + 'px';
    }
  });
});
</script>

### Summary and overview

<div class="visualization-gallery live-visualization-grid">
<figure class="visualization-shot visualization-live-shot">
  <iframe
    class="visualization-live-frame"
    data-healthmd-chart="intro-stats"
    title="Live-rendered Intro stats visualization"
    loading="lazy"
    style="height:430px"
    srcdoc='<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/docs/assets/live-visualizations/assets/live-visualizations.css"></head><body class="theme-dark embed-mode" data-chart-id="intro-stats"><div id="app"></div><script type="module" src="/docs/assets/live-visualizations/assets/live-visualizations.js"></script></body></html>'
  ></iframe>
  <figcaption><strong>Intro stats</strong><code>intro-stats</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <iframe
    class="visualization-live-frame"
    data-healthmd-chart="summary-card"
    title="Live-rendered Summary card visualization"
    loading="lazy"
    style="height:430px"
    srcdoc='<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/docs/assets/live-visualizations/assets/live-visualizations.css"></head><body class="theme-dark embed-mode" data-chart-id="summary-card"><div id="app"></div><script type="module" src="/docs/assets/live-visualizations/assets/live-visualizations.js"></script></body></html>'
  ></iframe>
  <figcaption><strong>Summary card</strong><code>summary-card</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <iframe
    class="visualization-live-frame"
    data-healthmd-chart="trend-tile"
    title="Live-rendered Trend tile visualization"
    loading="lazy"
    style="height:430px"
    srcdoc='<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/docs/assets/live-visualizations/assets/live-visualizations.css"></head><body class="theme-dark embed-mode" data-chart-id="trend-tile"><div id="app"></div><script type="module" src="/docs/assets/live-visualizations/assets/live-visualizations.js"></script></body></html>'
  ></iframe>
  <figcaption><strong>Trend tile</strong><code>trend-tile</code></figcaption>
</figure>
</div>

### Activity

<div class="visualization-gallery live-visualization-grid">
<figure class="visualization-shot visualization-live-shot">
  <iframe
    class="visualization-live-frame"
    data-healthmd-chart="activity-rings"
    title="Live-rendered Activity rings visualization"
    loading="lazy"
    style="height:430px"
    srcdoc='<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/docs/assets/live-visualizations/assets/live-visualizations.css"></head><body class="theme-dark embed-mode" data-chart-id="activity-rings"><div id="app"></div><script type="module" src="/docs/assets/live-visualizations/assets/live-visualizations.js"></script></body></html>'
  ></iframe>
  <figcaption><strong>Activity rings</strong><code>activity-rings</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <iframe
    class="visualization-live-frame"
    data-healthmd-chart="vitals-rings"
    title="Live-rendered Vitals rings visualization"
    loading="lazy"
    style="height:450px"
    srcdoc='<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/docs/assets/live-visualizations/assets/live-visualizations.css"></head><body class="theme-dark embed-mode" data-chart-id="vitals-rings"><div id="app"></div><script type="module" src="/docs/assets/live-visualizations/assets/live-visualizations.js"></script></body></html>'
  ></iframe>
  <figcaption><strong>Vitals rings</strong><code>vitals-rings</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <iframe
    class="visualization-live-frame"
    data-healthmd-chart="bar-chart"
    title="Live-rendered Bar chart visualization"
    loading="lazy"
    style="height:390px"
    srcdoc='<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/docs/assets/live-visualizations/assets/live-visualizations.css"></head><body class="theme-dark embed-mode" data-chart-id="bar-chart"><div id="app"></div><script type="module" src="/docs/assets/live-visualizations/assets/live-visualizations.js"></script></body></html>'
  ></iframe>
  <figcaption><strong>Bar chart</strong><code>bar-chart</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <iframe
    class="visualization-live-frame"
    data-healthmd-chart="activity-heatmap"
    title="Live-rendered Activity heatmap visualization"
    loading="lazy"
    style="height:350px"
    srcdoc='<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/docs/assets/live-visualizations/assets/live-visualizations.css"></head><body class="theme-dark embed-mode" data-chart-id="activity-heatmap"><div id="app"></div><script type="module" src="/docs/assets/live-visualizations/assets/live-visualizations.js"></script></body></html>'
  ></iframe>
  <figcaption><strong>Activity heatmap</strong><code>activity-heatmap</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <iframe
    class="visualization-live-frame"
    data-healthmd-chart="step-spiral"
    title="Live-rendered Step spiral visualization"
    loading="lazy"
    style="height:470px"
    srcdoc='<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/docs/assets/live-visualizations/assets/live-visualizations.css"></head><body class="theme-dark embed-mode" data-chart-id="step-spiral"><div id="app"></div><script type="module" src="/docs/assets/live-visualizations/assets/live-visualizations.js"></script></body></html>'
  ></iframe>
  <figcaption><strong>Step spiral</strong><code>step-spiral</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <iframe
    class="visualization-live-frame"
    data-healthmd-chart="weekday-average"
    title="Live-rendered Weekday average visualization"
    loading="lazy"
    style="height:410px"
    srcdoc='<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/docs/assets/live-visualizations/assets/live-visualizations.css"></head><body class="theme-dark embed-mode" data-chart-id="weekday-average"><div id="app"></div><script type="module" src="/docs/assets/live-visualizations/assets/live-visualizations.js"></script></body></html>'
  ></iframe>
  <figcaption><strong>Weekday average</strong><code>weekday-average</code></figcaption>
</figure>
</div>

### Heart

<div class="visualization-gallery live-visualization-grid">
<figure class="visualization-shot visualization-live-shot">
  <iframe
    class="visualization-live-frame"
    data-healthmd-chart="heart-terrain"
    title="Live-rendered Heart terrain visualization"
    loading="lazy"
    style="height:390px"
    srcdoc='<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/docs/assets/live-visualizations/assets/live-visualizations.css"></head><body class="theme-dark embed-mode" data-chart-id="heart-terrain"><div id="app"></div><script type="module" src="/docs/assets/live-visualizations/assets/live-visualizations.js"></script></body></html>'
  ></iframe>
  <figcaption><strong>Heart terrain</strong><code>heart-terrain</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <iframe
    class="visualization-live-frame"
    data-healthmd-chart="heart-range"
    title="Live-rendered Heart range visualization"
    loading="lazy"
    style="height:390px"
    srcdoc='<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/docs/assets/live-visualizations/assets/live-visualizations.css"></head><body class="theme-dark embed-mode" data-chart-id="heart-range"><div id="app"></div><script type="module" src="/docs/assets/live-visualizations/assets/live-visualizations.js"></script></body></html>'
  ></iframe>
  <figcaption><strong>Heart range</strong><code>heart-range</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <iframe
    class="visualization-live-frame"
    data-healthmd-chart="hrv-trend"
    title="Live-rendered HRV trend visualization"
    loading="lazy"
    style="height:350px"
    srcdoc='<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/docs/assets/live-visualizations/assets/live-visualizations.css"></head><body class="theme-dark embed-mode" data-chart-id="hrv-trend"><div id="app"></div><script type="module" src="/docs/assets/live-visualizations/assets/live-visualizations.js"></script></body></html>'
  ></iframe>
  <figcaption><strong>HRV trend</strong><code>hrv-trend</code></figcaption>
</figure>
</div>

### Respiratory and oxygen

<div class="visualization-gallery live-visualization-grid">
<figure class="visualization-shot visualization-live-shot">
  <iframe
    class="visualization-live-frame"
    data-healthmd-chart="oxygen-river"
    title="Live-rendered Oxygen river visualization"
    loading="lazy"
    style="height:290px"
    srcdoc='<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/docs/assets/live-visualizations/assets/live-visualizations.css"></head><body class="theme-dark embed-mode" data-chart-id="oxygen-river"><div id="app"></div><script type="module" src="/docs/assets/live-visualizations/assets/live-visualizations.js"></script></body></html>'
  ></iframe>
  <figcaption><strong>Oxygen river</strong><code>oxygen-river</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <iframe
    class="visualization-live-frame"
    data-healthmd-chart="oxygen-range"
    title="Live-rendered Oxygen range visualization"
    loading="lazy"
    style="height:390px"
    srcdoc='<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/docs/assets/live-visualizations/assets/live-visualizations.css"></head><body class="theme-dark embed-mode" data-chart-id="oxygen-range"><div id="app"></div><script type="module" src="/docs/assets/live-visualizations/assets/live-visualizations.js"></script></body></html>'
  ></iframe>
  <figcaption><strong>Oxygen range</strong><code>oxygen-range</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <iframe
    class="visualization-live-frame"
    data-healthmd-chart="breathing-wave"
    title="Live-rendered Breathing wave visualization"
    loading="lazy"
    style="height:290px"
    srcdoc='<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/docs/assets/live-visualizations/assets/live-visualizations.css"></head><body class="theme-dark embed-mode" data-chart-id="breathing-wave"><div id="app"></div><script type="module" src="/docs/assets/live-visualizations/assets/live-visualizations.js"></script></body></html>'
  ></iframe>
  <figcaption><strong>Breathing wave</strong><code>breathing-wave</code></figcaption>
</figure>
</div>

### Sleep

<div class="visualization-gallery live-visualization-grid">
<figure class="visualization-shot visualization-live-shot">
  <iframe
    class="visualization-live-frame"
    data-healthmd-chart="sleep-schedule"
    title="Live-rendered Sleep schedule visualization"
    loading="lazy"
    style="height:530px"
    srcdoc='<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/docs/assets/live-visualizations/assets/live-visualizations.css"></head><body class="theme-dark embed-mode" data-chart-id="sleep-schedule"><div id="app"></div><script type="module" src="/docs/assets/live-visualizations/assets/live-visualizations.js"></script></body></html>'
  ></iframe>
  <figcaption><strong>Sleep schedule</strong><code>sleep-schedule</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <iframe
    class="visualization-live-frame"
    data-healthmd-chart="sleep-quality-bars"
    title="Live-rendered Sleep quality bars visualization"
    loading="lazy"
    style="height:410px"
    srcdoc='<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/docs/assets/live-visualizations/assets/live-visualizations.css"></head><body class="theme-dark embed-mode" data-chart-id="sleep-quality-bars"><div id="app"></div><script type="module" src="/docs/assets/live-visualizations/assets/live-visualizations.js"></script></body></html>'
  ></iframe>
  <figcaption><strong>Sleep quality bars</strong><code>sleep-quality-bars</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <iframe
    class="visualization-live-frame"
    data-healthmd-chart="sleep-architecture"
    title="Live-rendered Sleep architecture visualization"
    loading="lazy"
    style="height:330px"
    srcdoc='<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/docs/assets/live-visualizations/assets/live-visualizations.css"></head><body class="theme-dark embed-mode" data-chart-id="sleep-architecture"><div id="app"></div><script type="module" src="/docs/assets/live-visualizations/assets/live-visualizations.js"></script></body></html>'
  ></iframe>
  <figcaption><strong>Sleep architecture</strong><code>sleep-architecture</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <iframe
    class="visualization-live-frame"
    data-healthmd-chart="sleep-polar"
    title="Live-rendered Sleep polar visualization"
    loading="lazy"
    style="height:450px"
    srcdoc='<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/docs/assets/live-visualizations/assets/live-visualizations.css"></head><body class="theme-dark embed-mode" data-chart-id="sleep-polar"><div id="app"></div><script type="module" src="/docs/assets/live-visualizations/assets/live-visualizations.js"></script></body></html>'
  ></iframe>
  <figcaption><strong>Sleep polar</strong><code>sleep-polar</code></figcaption>
</figure>
</div>

### Mindfulness and mood

<div class="visualization-gallery live-visualization-grid">
<figure class="visualization-shot visualization-live-shot">
  <iframe
    class="visualization-live-frame"
    data-healthmd-chart="mood-trend"
    title="Live-rendered Mood trend visualization"
    loading="lazy"
    style="height:430px"
    srcdoc='<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/docs/assets/live-visualizations/assets/live-visualizations.css"></head><body class="theme-dark embed-mode" data-chart-id="mood-trend"><div id="app"></div><script type="module" src="/docs/assets/live-visualizations/assets/live-visualizations.js"></script></body></html>'
  ></iframe>
  <figcaption><strong>Mood trend</strong><code>mood-trend</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <iframe
    class="visualization-live-frame"
    data-healthmd-chart="mood-calendar-heatmap"
    title="Live-rendered Mood calendar heatmap visualization"
    loading="lazy"
    style="height:390px"
    srcdoc='<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/docs/assets/live-visualizations/assets/live-visualizations.css"></head><body class="theme-dark embed-mode" data-chart-id="mood-calendar-heatmap"><div id="app"></div><script type="module" src="/docs/assets/live-visualizations/assets/live-visualizations.js"></script></body></html>'
  ></iframe>
  <figcaption><strong>Mood calendar heatmap</strong><code>mood-calendar-heatmap</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <iframe
    class="visualization-live-frame"
    data-healthmd-chart="mood-sleep-scatter"
    title="Live-rendered Mood × sleep scatterplot visualization"
    loading="lazy"
    style="height:450px"
    srcdoc='<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/docs/assets/live-visualizations/assets/live-visualizations.css"></head><body class="theme-dark embed-mode" data-chart-id="mood-sleep-scatter"><div id="app"></div><script type="module" src="/docs/assets/live-visualizations/assets/live-visualizations.js"></script></body></html>'
  ></iframe>
  <figcaption><strong>Mood × sleep scatterplot</strong><code>mood-sleep-scatter</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <iframe
    class="visualization-live-frame"
    data-healthmd-chart="mood-day-timeline"
    title="Live-rendered Mood day timeline visualization"
    loading="lazy"
    style="height:490px"
    srcdoc='<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/docs/assets/live-visualizations/assets/live-visualizations.css"></head><body class="theme-dark embed-mode" data-chart-id="mood-day-timeline"><div id="app"></div><script type="module" src="/docs/assets/live-visualizations/assets/live-visualizations.js"></script></body></html>'
  ></iframe>
  <figcaption><strong>Mood day timeline</strong><code>mood-day-timeline</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <iframe
    class="visualization-live-frame"
    data-healthmd-chart="mood-association-breakdown"
    title="Live-rendered Mood by association visualization"
    loading="lazy"
    style="height:490px"
    srcdoc='<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/docs/assets/live-visualizations/assets/live-visualizations.css"></head><body class="theme-dark embed-mode" data-chart-id="mood-association-breakdown"><div id="app"></div><script type="module" src="/docs/assets/live-visualizations/assets/live-visualizations.js"></script></body></html>'
  ></iframe>
  <figcaption><strong>Mood by association</strong><code>mood-association-breakdown</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <iframe
    class="visualization-live-frame"
    data-healthmd-chart="mood-label-cloud"
    title="Live-rendered Mood label cloud visualization"
    loading="lazy"
    style="height:430px"
    srcdoc='<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/docs/assets/live-visualizations/assets/live-visualizations.css"></head><body class="theme-dark embed-mode" data-chart-id="mood-label-cloud"><div id="app"></div><script type="module" src="/docs/assets/live-visualizations/assets/live-visualizations.js"></script></body></html>'
  ></iframe>
  <figcaption><strong>Mood label cloud</strong><code>mood-label-cloud</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <iframe
    class="visualization-live-frame"
    data-healthmd-chart="mood-volatility"
    title="Live-rendered Mood volatility visualization"
    loading="lazy"
    style="height:430px"
    srcdoc='<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/docs/assets/live-visualizations/assets/live-visualizations.css"></head><body class="theme-dark embed-mode" data-chart-id="mood-volatility"><div id="app"></div><script type="module" src="/docs/assets/live-visualizations/assets/live-visualizations.js"></script></body></html>'
  ></iframe>
  <figcaption><strong>Mood volatility</strong><code>mood-volatility</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <iframe
    class="visualization-live-frame"
    data-healthmd-chart="mood-kind-split"
    title="Live-rendered Daily vs momentary mood visualization"
    loading="lazy"
    style="height:430px"
    srcdoc='<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/docs/assets/live-visualizations/assets/live-visualizations.css"></head><body class="theme-dark embed-mode" data-chart-id="mood-kind-split"><div id="app"></div><script type="module" src="/docs/assets/live-visualizations/assets/live-visualizations.js"></script></body></html>'
  ></iframe>
  <figcaption><strong>Daily vs momentary mood</strong><code>mood-kind-split</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <iframe
    class="visualization-live-frame"
    data-healthmd-chart="mood-circadian-clock"
    title="Live-rendered Circadian mood clock visualization"
    loading="lazy"
    style="height:490px"
    srcdoc='<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/docs/assets/live-visualizations/assets/live-visualizations.css"></head><body class="theme-dark embed-mode" data-chart-id="mood-circadian-clock"><div id="app"></div><script type="module" src="/docs/assets/live-visualizations/assets/live-visualizations.js"></script></body></html>'
  ></iframe>
  <figcaption><strong>Circadian mood clock</strong><code>mood-circadian-clock</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <iframe
    class="visualization-live-frame"
    data-healthmd-chart="mood-recovery-tile"
    title="Live-rendered Recovery + mindset tile visualization"
    loading="lazy"
    style="height:450px"
    srcdoc='<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/docs/assets/live-visualizations/assets/live-visualizations.css"></head><body class="theme-dark embed-mode" data-chart-id="mood-recovery-tile"><div id="app"></div><script type="module" src="/docs/assets/live-visualizations/assets/live-visualizations.js"></script></body></html>'
  ></iframe>
  <figcaption><strong>Recovery + mindset tile</strong><code>mood-recovery-tile</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <iframe
    class="visualization-live-frame"
    data-healthmd-chart="mood-association-matrix"
    title="Live-rendered Mood association matrix visualization"
    loading="lazy"
    style="height:510px"
    srcdoc='<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/docs/assets/live-visualizations/assets/live-visualizations.css"></head><body class="theme-dark embed-mode" data-chart-id="mood-association-matrix"><div id="app"></div><script type="module" src="/docs/assets/live-visualizations/assets/live-visualizations.js"></script></body></html>'
  ></iframe>
  <figcaption><strong>Mood association matrix</strong><code>mood-association-matrix</code></figcaption>
</figure>
</div>

### Medications

<div class="visualization-gallery live-visualization-grid">
<figure class="visualization-shot visualization-live-shot">
  <iframe
    class="visualization-live-frame"
    data-healthmd-chart="medication-overview"
    title="Live-rendered Medication overview visualization"
    loading="lazy"
    style="height:690px"
    srcdoc='<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/docs/assets/live-visualizations/assets/live-visualizations.css"></head><body class="theme-dark embed-mode" data-chart-id="medication-overview"><div id="app"></div><script type="module" src="/docs/assets/live-visualizations/assets/live-visualizations.js"></script></body></html>'
  ></iframe>
  <figcaption><strong>Medication overview</strong><code>medication-overview</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <iframe
    class="visualization-live-frame"
    data-healthmd-chart="medication-inventory"
    title="Live-rendered Medication inventory visualization"
    loading="lazy"
    style="height:430px"
    srcdoc='<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/docs/assets/live-visualizations/assets/live-visualizations.css"></head><body class="theme-dark embed-mode" data-chart-id="medication-inventory"><div id="app"></div><script type="module" src="/docs/assets/live-visualizations/assets/live-visualizations.js"></script></body></html>'
  ></iframe>
  <figcaption><strong>Medication inventory</strong><code>medication-inventory</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <iframe
    class="visualization-live-frame"
    data-healthmd-chart="medication-adherence-summary"
    title="Live-rendered Medication adherence summary visualization"
    loading="lazy"
    style="height:430px"
    srcdoc='<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/docs/assets/live-visualizations/assets/live-visualizations.css"></head><body class="theme-dark embed-mode" data-chart-id="medication-adherence-summary"><div id="app"></div><script type="module" src="/docs/assets/live-visualizations/assets/live-visualizations.js"></script></body></html>'
  ></iframe>
  <figcaption><strong>Medication adherence summary</strong><code>medication-adherence-summary</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <iframe
    class="visualization-live-frame"
    data-healthmd-chart="medication-dose-status"
    title="Live-rendered Medication dose status visualization"
    loading="lazy"
    style="height:490px"
    srcdoc='<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/docs/assets/live-visualizations/assets/live-visualizations.css"></head><body class="theme-dark embed-mode" data-chart-id="medication-dose-status"><div id="app"></div><script type="module" src="/docs/assets/live-visualizations/assets/live-visualizations.js"></script></body></html>'
  ></iframe>
  <figcaption><strong>Medication dose status</strong><code>medication-dose-status</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <iframe
    class="visualization-live-frame"
    data-healthmd-chart="medication-adherence-trend"
    title="Live-rendered Medication adherence trend visualization"
    loading="lazy"
    style="height:450px"
    srcdoc='<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/docs/assets/live-visualizations/assets/live-visualizations.css"></head><body class="theme-dark embed-mode" data-chart-id="medication-adherence-trend"><div id="app"></div><script type="module" src="/docs/assets/live-visualizations/assets/live-visualizations.js"></script></body></html>'
  ></iframe>
  <figcaption><strong>Medication adherence trend</strong><code>medication-adherence-trend</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <iframe
    class="visualization-live-frame"
    data-healthmd-chart="medication-recent-dose-events"
    title="Live-rendered Medication recent dose events visualization"
    loading="lazy"
    style="height:510px"
    srcdoc='<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/docs/assets/live-visualizations/assets/live-visualizations.css"></head><body class="theme-dark embed-mode" data-chart-id="medication-recent-dose-events"><div id="app"></div><script type="module" src="/docs/assets/live-visualizations/assets/live-visualizations.js"></script></body></html>'
  ></iframe>
  <figcaption><strong>Medication recent dose events</strong><code>medication-recent-dose-events</code></figcaption>
</figure>
</div>

### Mobility, gait, and running form

<div class="visualization-gallery live-visualization-grid">
<figure class="visualization-shot visualization-live-shot">
  <iframe
    class="visualization-live-frame"
    data-healthmd-chart="walking-symmetry"
    title="Live-rendered Walking symmetry visualization"
    loading="lazy"
    style="height:350px"
    srcdoc='<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/docs/assets/live-visualizations/assets/live-visualizations.css"></head><body class="theme-dark embed-mode" data-chart-id="walking-symmetry"><div id="app"></div><script type="module" src="/docs/assets/live-visualizations/assets/live-visualizations.js"></script></body></html>'
  ></iframe>
  <figcaption><strong>Walking symmetry</strong><code>walking-symmetry</code></figcaption>
</figure>
</div>

### Workouts

<div class="visualization-gallery live-visualization-grid">
<figure class="visualization-shot visualization-live-shot">
  <iframe
    class="visualization-live-frame"
    data-healthmd-chart="workout-log"
    title="Live-rendered Workout log visualization"
    loading="lazy"
    style="height:410px"
    srcdoc='<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/docs/assets/live-visualizations/assets/live-visualizations.css"></head><body class="theme-dark embed-mode" data-chart-id="workout-log"><div id="app"></div><script type="module" src="/docs/assets/live-visualizations/assets/live-visualizations.js"></script></body></html>'
  ></iframe>
  <figcaption><strong>Workout log</strong><code>workout-log</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <iframe
    class="visualization-live-frame"
    data-healthmd-chart="workout-heart-rate"
    title="Live-rendered Workout heart rate visualization"
    loading="lazy"
    style="height:430px"
    srcdoc='<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/docs/assets/live-visualizations/assets/live-visualizations.css"></head><body class="theme-dark embed-mode" data-chart-id="workout-heart-rate"><div id="app"></div><script type="module" src="/docs/assets/live-visualizations/assets/live-visualizations.js"></script></body></html>'
  ></iframe>
  <figcaption><strong>Workout heart rate</strong><code>workout-heart-rate</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <iframe
    class="visualization-live-frame"
    data-healthmd-chart="workout-zones"
    title="Live-rendered Workout zones visualization"
    loading="lazy"
    style="height:350px"
    srcdoc='<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/docs/assets/live-visualizations/assets/live-visualizations.css"></head><body class="theme-dark embed-mode" data-chart-id="workout-zones"><div id="app"></div><script type="module" src="/docs/assets/live-visualizations/assets/live-visualizations.js"></script></body></html>'
  ></iframe>
  <figcaption><strong>Workout zones</strong><code>workout-zones</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <iframe
    class="visualization-live-frame"
    data-healthmd-chart="workout-trends"
    title="Live-rendered Workout trends visualization"
    loading="lazy"
    style="height:590px"
    srcdoc='<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/docs/assets/live-visualizations/assets/live-visualizations.css"></head><body class="theme-dark embed-mode" data-chart-id="workout-trends"><div id="app"></div><script type="module" src="/docs/assets/live-visualizations/assets/live-visualizations.js"></script></body></html>'
  ></iframe>
  <figcaption><strong>Workout trends</strong><code>workout-trends</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <iframe
    class="visualization-live-frame"
    data-healthmd-chart="workout-intervals"
    title="Live-rendered Workout intervals visualization"
    loading="lazy"
    style="height:510px"
    srcdoc='<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/docs/assets/live-visualizations/assets/live-visualizations.css"></head><body class="theme-dark embed-mode" data-chart-id="workout-intervals"><div id="app"></div><script type="module" src="/docs/assets/live-visualizations/assets/live-visualizations.js"></script></body></html>'
  ></iframe>
  <figcaption><strong>Workout intervals</strong><code>workout-intervals</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <iframe
    class="visualization-live-frame"
    data-healthmd-chart="workout-map"
    title="Live-rendered Workout map visualization"
    loading="lazy"
    style="height:530px"
    srcdoc='<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/docs/assets/live-visualizations/assets/live-visualizations.css"></head><body class="theme-dark embed-mode" data-chart-id="workout-map"><div id="app"></div><script type="module" src="/docs/assets/live-visualizations/assets/live-visualizations.js"></script></body></html>'
  ></iframe>
  <figcaption><strong>Workout map</strong><code>workout-map</code></figcaption>
</figure>
</div>

## Foundation roadmap

The biggest product gap is not one missing chart. It is a generic schema-aware metric layer that lets any exported Health.md field be plotted without writing a custom parser and renderer for every metric.

### Built

- Schema compatibility detection for daily exports, legacy files, rollups, and data dictionary files.
- JSON, CSV, Markdown, and Obsidian Bases loading.
- Rollup awareness so weekly/monthly/yearly summaries do not pollute daily charts.
- Source-file navigation from chart points back to the contributing Health.md file.

### Planned

- **Generic schema-aware metric accessor** — read `_healthmd_data_dictionary.json` for labels, units, categories, aggregation rules, and aliases.
- **Generic metric trend** — line/area chart for any numeric exported key.
- **Generic metric bars** — generalized daily/weekly/monthly bars with goal and threshold lines.
- **Generic calendar heatmap** — any daily numeric metric as a calendar grid.
- **Visualization coverage report** — show fields present in a vault vs fields covered by dedicated renderers.

---

## Summary and overview

### Built

- `intro-stats` — dataset summary with totals, averages, sleep, and vitals.
- `summary-card` — Apple-style KPI card with sparkline and prior-period comparison.
- `trend-tile` — trends-card comparison between current and prior windows.

### Planned

- Auto-generated dashboard based on fields present in the selected Health.md folder.
- Schema coverage dashboard by data category.
- Correlation summary cards, such as sleep vs mood, HRV vs workouts, symptoms vs medications, or alcohol vs sleep.

---

## Activity

Health.md exports steps, active energy, basal energy, exercise time, stand time, flights climbed, walking/running distance, cycling, swimming, wheelchair activity, downhill snow distance, move time, physical effort, and VO₂ max.

### Built

- `activity-rings`
- `vitals-rings`
- `bar-chart`
- `activity-heatmap`
- `step-spiral`
- `weekday-average`

### Planned

- Activity load dashboard for steps, calories, exercise, stand hours, and physical effort.
- VO₂ max trend.
- Move / exercise / stand consistency chart.
- Distance mix chart across walking/running, cycling, swimming, wheelchair, and snow sports.
- Swimming distance + stroke chart.
- Wheelchair distance + push chart.

---

## Sleep

Health.md exports total sleep, bedtime, wake time, deep/REM/core/awake/in-bed durations, and granular sleep-stage intervals.

### Built

- `sleep-schedule`
- `sleep-quality-bars`
- `sleep-architecture`
- `sleep-polar`

### Planned

- Sleep debt and consistency score.
- Sleep stage ratio trend.
- Bedtime/wake regularity heatmap.
- Sleep + HRV + resting heart rate recovery dashboard.

---

## Heart

Health.md exports resting heart rate, walking heart rate, average/min/max heart rate, HRV, heart-rate samples, HRV samples, heart-rate recovery, and AFib burden.

### Built

- `heart-terrain`
- `heart-range`
- `hrv-trend`

### Planned

- Resting heart-rate trend.
- Walking heart-rate trend.
- Heart-rate recovery trend.
- AFib burden chart.
- HRV + resting heart rate recovery tile.
- Circadian heart-rate profile by time of day.

---

## Respiratory and oxygen

Health.md exports blood oxygen average/min/max, blood oxygen samples, respiratory-rate average/min/max, and respiratory-rate samples.

### Built

- `oxygen-river`
- `oxygen-range`
- `breathing-wave`

### Planned

- Dedicated respiratory range chart.
- Oxygen desaturation event chart.
- Overnight respiratory dashboard combining sleep stages, oxygen, and respiratory rate.

---

## Vitals

Health.md exports body temperature, blood pressure, blood glucose, basal body temperature, wrist temperature, electrodermal activity, forced vital capacity, FEV1, peak expiratory flow, and inhaler usage.

### Built

- Partial coverage through summary cards and generic daily charts.

### Planned

- Blood pressure systolic/diastolic range chart with threshold bands.
- Blood glucose range chart.
- Body, basal, and wrist temperature trend.
- Wrist temperature recovery / illness tile.
- Respiratory function dashboard for FVC, FEV1, peak flow, and inhaler usage.
- Electrodermal activity / stress trend.

---

## Body measurements

Health.md exports weight, height, BMI, body fat percentage, lean body mass, and waist circumference.

### Built

- No dedicated body composition renderer yet.

### Planned

- Body composition dashboard.
- Weight trend with rolling average and goal line.
- BMI trend with category bands.
- Body fat vs lean mass chart.
- Waist circumference trend.

---

## Mobility, gait, and running form

Health.md exports walking speed, step length, double support, walking asymmetry, stair ascent/descent speed, six-minute walk, walking steadiness, running speed, running stride length, ground contact time, vertical oscillation, and running power.

### Built

- `walking-symmetry`

### Planned

- Gait dashboard.
- Walking steadiness gauge.
- Six-minute walk trend.
- Stair ascent/descent speed chart.
- Running form dashboard for speed, stride, ground contact, vertical oscillation, and power.

---

## Workouts

Health.md exports workout counts, minutes, calories, distance, workout types, heart-rate stats, running/cycling form metrics, power, elevation, laps, splits, route points, heart-rate zones, and workout time-series samples.

### Built

- `workout-log`
- `workout-heart-rate`
- `workout-zones`
- `workout-trends`
- `workout-intervals`
- `workout-map`

### Planned

- Workout calendar heatmap.
- Training load chart from duration and intensity.
- Weekly workout distribution by type.
- Pace and speed trend by workout type.
- Elevation gain/loss trend.
- Route comparison small multiples.
- Power curve / best efforts.
- Running form and cycling performance dashboards.

---

## Mindfulness and mood

Health.md exports mindful minutes, mindful sessions, State of Mind entries, average valence, daily mood, momentary emotions, labels, and associations.

### Built

- `mood-trend`
- `mood-calendar-heatmap`
- `mood-sleep-scatter`
- `mood-day-timeline`
- `mood-association-breakdown`
- `mood-label-cloud`
- `mood-volatility`
- `mood-kind-split`
- `mood-circadian-clock`
- `mood-recovery-tile`
- `mood-association-matrix`

### Planned

- Mindful minutes trend.
- Mindful session streak/calendar.
- Mood vs medication adherence.
- Mood vs nutrition, alcohol, and caffeine.
- Mood label timeline.

---

## Medications

Health.md exports medication inventory, active/archived counts, dose event counts, taken/skipped counts, medication details, RxNorm/coding metadata, dose quantities, schedule type, scheduled/start/end dates, statuses, and metadata.

### Built

- `medication-overview`
- `medication-inventory`
- `medication-adherence-summary`
- `medication-dose-status`
- `medication-adherence-trend`
- `medication-recent-dose-events`

### Planned

- Medication schedule timeline.
- Medication adherence calendar heatmap.
- Medication lateness chart comparing scheduled time to taken time.
- Dose quantity trend.
- Medication vs symptom/mood correlation views.
- RxNorm / coding detail panel.

---

## Nutrition

Health.md exports dietary calories, protein, carbohydrates, fat, saturated fat, monounsaturated fat, polyunsaturated fat, fiber, sugar, sodium, cholesterol, water, and caffeine.

### Built

- No dedicated nutrition renderer yet.

### Planned

- Nutrition dashboard.
- Macro split chart.
- Calories in vs active calories chart.
- Hydration trend.
- Caffeine daily amount / timing chart.
- Sugar and sodium threshold charts.
- Fiber and protein goal progress.

---

## Vitamins and minerals

Health.md exports vitamins A, B6, B12, C, D, E, K, thiamin, riboflavin, niacin, folate, biotin, pantothenic acid, calcium, iron, potassium, magnesium, phosphorus, zinc, selenium, copper, manganese, chromium, molybdenum, chloride, and iodine.

### Built

- No dedicated micronutrient renderer yet.

### Planned

- Micronutrient heatmap.
- Recommended daily value progress grid.
- Vitamin trend dashboard.
- Mineral trend dashboard.
- Deficiency/excess flag panel.
- Nutrition completeness score.

---

## Hearing

Health.md exports headphone audio level and environmental sound level.

### Built

- Partial summary-level coverage only.

### Planned

- Hearing exposure trend.
- Loud-day calendar.
- Safe exposure threshold bands.
- Weekly exposure summary.

---

## Reproductive health and cycle tracking

Health.md exports menstrual flow, sexual activity, ovulation test result, cervical mucus quality, and intermenstrual bleeding.

### Built

- No dedicated reproductive health renderer yet.

### Planned

- Cycle calendar.
- Menstrual flow heatmap.
- Fertility signal timeline.
- Cycle symptom overlay combining reproductive health, symptoms, mood, and sleep.
- Spotting / intermenstrual bleeding timeline.

---

## Symptoms

Health.md exports daily symptom counts for headache, fatigue, nausea, dizziness, mood changes, sleep changes, appetite changes, hot flashes, chills, fever, lower back pain, bloating, constipation, diarrhea, heartburn, coughing, sore throat, runny nose, shortness of breath, chest pain, skipped heartbeat, rapid heartbeat, acne, dry skin, hair loss, memory lapse, night sweats, vomiting, abdominal cramps, breast pain, pelvic pain, body ache, fainting, loss of smell, loss of taste, wheezing, sinus congestion, bladder incontinence, and vaginal dryness.

### Built

- No dedicated symptom renderer yet.

### Planned

- Symptom calendar heatmap.
- Symptom frequency leaderboard.
- Symptom co-occurrence matrix.
- Flare timeline.
- Symptom correlation explorer.
- Body-system grouped symptom dashboard.

---

## Other health, lifestyle, and environment

Health.md exports UV exposure, time in daylight, falls, blood alcohol, alcoholic beverages, insulin delivery, toothbrushing, handwashing, water temperature, and underwater depth.

### Built

- No dedicated lifestyle/environment renderer yet.

### Planned

- Daylight / UV calendar.
- Falls timeline.
- Alcohol vs sleep / HRV chart.
- Insulin delivery trend.
- Toothbrushing and handwashing streaks.
- Water temperature / underwater depth chart.

---

## Priority order

1. Generic schema-aware metric infrastructure.
2. Generic trend, bar, and calendar heatmap renderers.
3. Vitals suite: blood pressure, glucose, temperature, respiratory function.
4. Body composition dashboard.
5. Nutrition dashboard.
6. Symptom heatmap, leaderboard, and correlation views.
7. Cycle / reproductive health calendar.
8. Micronutrient heatmap and RDA grid.
9. Expanded mobility and running form dashboard.
10. Hearing and lifestyle/environment charts.

<p style="margin-top:48px; color:var(--sl-color-gray-3); font-size:14px;">Last updated 2026-06-24</p>
