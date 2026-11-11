# Use your own data

[[Start here]] · [[Health Dashboard]]

## Keep the example separate

Open a **new vault** for real health data, or make a backup of your existing vault first. Keep this starter intact as a reference. This avoids mixing fictional records with your measurements.

Copy `Templates`, `Views`, and any guide you need into your real vault. Do not copy `Health`, `Reviews/2026-10-19 Weekly review.md`, `Attachments`, or the sample dashboard into the real health folder. The SVG charts are fixed fictional examples.

## Export one real day

Health.md can export selected health data to files you control. The starter itself is free; the exporter is a separate app with its own trial and purchase terms. See [current pricing](https://healthmd.app/about/#key-facts).

1. On the device containing your health data, authorize only the categories you want.
2. In Health.md, select **Obsidian Bases** for numeric Markdown frontmatter and choose a `Health` folder inside your real vault. You do not need JSON or CSV as well for this workflow.
3. Start with a single date and a few metrics: steps, sleep, and resting heart rate where available. Preview, then export.
4. Open the resulting note in Obsidian. Check its date, units, and properties against the [export reference](https://healthmd.app/docs/reference/export-formats/). The example views expect `steps`, `sleep_total_hours`, and `resting_heart_rate`; if your export settings rename them, update the view columns to match.
5. Open `Views/Health log.base` and select **All days**. Confirm that the real note appears and missing measurements stay blank.

Keep the health folder flat at first, with one note per date. Multiple notes for the same date will appear as multiple rows and can double-count summaries. Avoid daily-note injection initially; retain your writing in separate reflection notes.

The app's **Obsidian Bases** export creates property-bearing Markdown files. The `.base` view in this starter supplies the table; the export does not create that view for you.

## Platform setup

- [Apple Health → Obsidian](https://healthmd.app/blog/export-apple-health-data-to-obsidian/)
- [Android Health Connect → Obsidian](https://healthmd.app/blog/export-health-connect-to-obsidian/)

Available metrics, units, date attribution, destinations, and scheduling behavior depend on the platform, permissions, source data, and installed release. Begin with a manual export that you can verify, then follow the platform's scheduling instructions. Do not assume a scheduled time guarantees delivery.

## Start your first review

Enable the **Templates** core plugin and set the template folder to `Templates`. Create an empty note in `Reviews` and use **Templates: Insert template → Weekly review**.

Set `week_start` and `week_end` to the inclusive dates you want, in YYYY-MM-DD form. The embedded **Review week** view uses those properties. They are intentionally blank in the template; today's date is only the date you wrote the review, not an assumed week boundary.

The view calculates per-column summaries. Transfer those values and their observed-day counts into the reflection table yourself; the prose and table cells are not automatically filled. Never treat an empty metric cell as zero.

For interactive charts, follow [[Guides/Optional interactive charts]]. Change the fixed `from` and `to` values to dates you actually exported, or remove them and use `last: 28` for a moving window after confirming the plugin's behavior with your data.

## Keep private data private

The starter's samples are safe to share because they are fictional. Your real health vault may contain sensitive measurements and journal entries. Choose its storage, sync, backups, screenshots, and AI integrations deliberately. Installing this starter does not connect your phone or send health data anywhere.
