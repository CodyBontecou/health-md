# Optional interactive charts

[[Start here]] · [[Health Dashboard]]

The main dashboard already contains chart images. This page adds interactive charts with **Health.md Visualizations**, a separately installed community plugin.

## Set up

1. In Obsidian **Settings → Community plugins**, review the community-plugin prompt yourself.
2. Browse for **Health.md Visualizations**, install it, and enable it. Use the current release on Obsidian 1.12 or later. [Official listing](https://community.obsidian.md/plugins/health-md) · [source and compatibility notes](https://github.com/CodyBontecou/health-md-visualizations).
3. In its settings, set **Data folder** to `Health`, **Data format** to `Markdown` (or `auto`), **File pattern** to `*.md`, and keep the folder structure **Flat**.
4. Switch this note to Reading view. You should see 28 dates; sleep and resting-heart-rate charts each have one missing measurement.

No plugin JavaScript or community-plugin permissions are bundled in the starter. Until you enable the plugin, the blocks below appear as configuration text.

These ranges are fixed to the sample dates, so the example stays visible over time. When using real data, edit both dates. `metric-trend` uses numeric property IDs and leaves gaps for missing values.

## Daily steps

```health-viz
type: metric-trend
metric: steps
from: 2026-09-28
to: 2026-10-25
height: 260
```

## Sleep duration · hours

```health-viz
type: metric-trend
metric: sleep_total_hours
from: 2026-09-28
to: 2026-10-25
height: 260
```

Sleep is attributed to the night beginning on each sample date. October 8 has no sleep value.

## Resting heart rate · bpm

```health-viz
type: metric-trend
metric: resting_heart_rate
from: 2026-09-28
to: 2026-10-25
height: 260
```

October 15 has no resting-heart-rate value. These example values are not personal targets.

## If you see no data

Confirm that the data folder is `Health`, not the vault's parent directory, and that the sample `.md` files are inside it. Check the fixed date range, update the plugin, and reopen this note. Metric names are case-sensitive. To inspect values without any community plugin, use [[Views/Health log.base|the built-in log]] or open a daily note.
