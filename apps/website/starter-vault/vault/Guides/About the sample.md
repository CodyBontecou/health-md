# About the sample

[[Start here]] · [[Health Dashboard]]

## Made for learning

There are 28 fictional daily notes, from September 28 through October 25, 2026. They illustrate a file-and-journal workflow. They are not a clinical dataset, an anonymized person's records, or complete Health.md exports.

Each note uses a small, unversioned frontmatter example with familiar Health.md property names. It deliberately makes no export-schema or capture-completeness claim. Health.md's actual exports include more metadata and vary with platform, permissions, available data, and settings. See the [export reference](https://healthmd.app/docs/reference/export-formats/).

## Fields and units

| Property | Meaning in this example | Unit |
| --- | --- | --- |
| `date` | Calendar date attached to the example note | YYYY-MM-DD |
| `steps` | Fictional daily step total | steps |
| `sleep_total_hours` | Fictional sleep duration attributed to this date | hours, decimal |
| `resting_heart_rate` | Fictional daily resting heart rate | beats per minute (bpm) |
| `sample_data` | `true` marks fictional notes | boolean |

The sleep value is attributed to the **night beginning on the note's date**, not the following morning. That is the Apple workflow illustrated here; when adding real data, check the source platform's date attribution instead of shifting dates by assumption. Decimal hours are not hours-and-minutes: 7.5 hours means 7 hours 30 minutes.

## Missing is not zero

- October 8 has no sleep measurement.
- October 15 has no resting-heart-rate measurement.
- Those properties are **omitted**, the log cells stay blank, and line charts break at the missing day.
- Averages include only days with that metric. Each summary shows its own coverage count.

For example, six observed days in a seven-day week yield an average over six days. That is not an estimate for the missing day. A zero, if genuinely recorded, would remain a measurement and belong in that calculation.

## Chart snapshots and interactive charts

The three SVG files in `Attachments` are generated from exactly these 28 notes. They are **fixed sample snapshots**, not live charts. Editing the notes does not redraw the images. The raw-data table below each chart remains the accessible source of values.

The optional [[Guides/Optional interactive charts|interactive charts]] read files from `Health` after you install Health.md Visualizations. The plugin can update those charts as the source notes change. It is not needed for the main dashboard.

No thresholds, scores, diagnoses, or causal claims are assigned to these values. The vertical scales are labeled; steps start at zero, while sleep and resting-heart-rate lines use a narrower scale to show variation.

## Reuse

You may copy, adapt, and redistribute the notes, templates, synthetic measurements, and generated charts under the included MIT license. Attribution to [healthmd.app](https://healthmd.app/) is appreciated; the license notice must accompany redistributed copies. Obsidian and optional plugins have their own licenses and are not included in this download.
