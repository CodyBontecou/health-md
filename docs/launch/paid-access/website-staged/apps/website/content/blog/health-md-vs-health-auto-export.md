---
title: "Health.md vs Health Auto Export: which export workflow fits?"
description: "Compare Health.md and Health Auto Export for Apple Health CSV, Obsidian notes, automation, MCP, and pricing. Check the differences before choosing an app."
lead: "Choose Health.md for configurable daily files and Obsidian notes. Consider Health Auto Export when its built-in destination integrations match your workflow."
date: "2026-10-26"
updated: "2026-10-26"
category: "App comparison"
related:
  - apple-health-xml-export
  - export-apple-health-data-to-obsidian
  - export-health-data-without-the-cloud
draft: false
verified: "2026-10-26"
verified_by: "Codex (agent)"
verified_method: traced
tags:
  - apple-health
  - comparison
  - export
  - obsidian
---

**Health.md and Health Auto Export both export Apple Health data and support automation.** Health.md is a good fit if you want configurable daily files, Obsidian Bases properties, or health sections in existing daily notes. Health Auto Export is worth considering if you want its documented integrations for services such as Home Assistant, MQTT, Google Drive, or Dropbox.

This comparison is published by Health.md. We checked our documentation and Health Auto Export's official sources on **October 26, 2026**. It is a documentation comparison, not a hands-on performance test. The scope is the iPhone Apple Health workflow. For Android, use our separate [Health Connect guide](/health-connect-export/).

<a class="button" href="/assets/downloads/healthmd-obsidian-starter.zip">Try the free Obsidian starter vault</a>

The starter vault contains fictional notes and charts. You can inspect the output without buying an app or granting health permissions.

## Compare the workflow you actually need

<div class="article-table-scroll" role="region" aria-label="Health.md and Health Auto Export workflow comparison" tabindex="0">

| Your task | Health.md | Health Auto Export |
|---|---|---|
| Open health data in a spreadsheet | Daily CSV files, with selectable metrics, dates, and detail | CSV export with configurable aggregation |
| Keep health data in notes | Markdown templates, Obsidian Bases properties, and Daily Note Injection | Its current App Store listing includes Markdown export |
| Send data to your own service | API Endpoint sends a versioned JSON envelope to your receiver | Documents REST API, MQTT, Home Assistant, and storage integrations |
| Query data from an AI client | Bundled Mac MCP helper; a separate portable direct MCP remains a preview | Documents an iPhone MCP server for clients on the same local network |

</div>

For Health.md, see the [format reference](/docs/format/), [daily note behavior](/docs/daily-notes/), and [API Endpoint guide](/docs/api-endpoint/). For Health Auto Export, see its [current App Store listing](https://apps.apple.com/us/app/health-auto-export-json-csv/id1115567069), [manual export guide](https://help.healthyapps.dev/en/health-auto-export/manual-export/), and [official integration overview](https://www.healthyapps.dev/apps/health-auto-export/). A shared format name does not mean the two apps write interchangeable files.

## For Obsidian: check properties and existing notes

In Health.md, you can write separate daily health notes or [inject a managed health section into existing daily notes](/docs/daily-notes/). Configure the destination, filename, template, and write behavior before exporting. Obsidian Bases output uses structured frontmatter for filtering and comparing notes.

Start with the [free starter vault](/assets/downloads/healthmd-obsidian-starter.zip), then follow the [Apple Health to Obsidian walkthrough](/blog/export-apple-health-data-to-obsidian/) for your own data.

Health Auto Export's listing includes Markdown. If you are considering it for an existing vault, check its current output against your required filenames, properties, and note update behavior. We have not tested that workflow and do not claim it cannot work with Obsidian.

## For CSV: compare one day before moving your workflow

[Download Health.md's synthetic CSV](/docs/reference/generated/core/summary-day.csv) and try it in your spreadsheet. Health.md writes one CSV per day. Rows identify the metric, value, and unit; metadata and optional canonical records need different handling from daily numeric totals. The [CSV guide](/apple-health-to-csv/) explains import and filtering.

With either app, export one date you can check in Apple Health. Compare the selected metrics, units, aggregation, timestamps, and missing values before combining multiple days. Do not append the two apps' files and assume matching column names or daily totals mean identical records. Keep original files when changing tools.

## For automation and AI: check the destination and device requirements

Health.md supports [profile schedules](/docs/scheduling/) and [Shortcuts](/docs/shortcuts/). Its API destination sends JSON directly to an endpoint you configure. A folder synchronized by a storage provider is a different setup from a dedicated service integration.

Health Auto Export documents dedicated destination integrations in its [automation guides](https://help.healthyapps.dev/en/health-auto-export/automations/). That is a useful reason to consider it when one of those services is your destination.

Both apps depend on iOS background execution and protected health data access. A scheduled time is a target. Verify the actual output after a run; neither app should be chosen on an assumption of guaranteed background delivery. See our [scheduling limits](/docs/scheduling/) and Health Auto Export's [automation FAQ](https://help.healthyapps.dev/en/health-auto-export/faq/).

Both also document MCP access. Health.md's [bundled Mac MCP](/docs/mcp/) requires the Mac app open and a connected iPhone for fresh reads. The separate portable direct MCP is an explicitly unqualified preview. Health Auto Export's [server guide](https://help.healthyapps.dev/en/health-auto-export/automations/server-connection/) describes an iPhone server that stays in the foreground, with local network access and client setup requirements. Check the intended topology before choosing either.

## Pricing and where the data goes

The subscription-enabled Health.md phone release offers weekly/yearly subscriptions and Lifetime. Eligible subscriptions include a 7-day trial; existing purchases remain valid. Manual and scheduled exports require active access; see [purchase and restore details](/docs/paywall/).

Health Auto Export lists a seven-day Premium trial, a free tier, a Basic one-time purchase, and Premium subscription or lifetime options. Basic covers manual exports; Premium adds automated integrations and Mac sync. Check its [purchase description](https://github.com/Lybron/health-auto-export#pricing) and each app's purchase sheet for current local prices and feature access. A subscription is not the only purchase option for either app.

Health.md's folder workflow creates no Health.md server copy. A sync provider or endpoint you choose has its own data handling terms. The separate optional Health.md Cloud pilot has different retention rules; see our [privacy policy](/privacy-policy.html#retention).

Health Auto Export's [privacy policy](https://www.healthyapps.dev/health-auto-export/privacy-policy/) says processing happens on the device and exports go directly to destinations the user chooses. We do not claim Health.md is the only option for keeping control of exported files.

## Make a small first export

Choose one completed day, one metric, and the destination you intend to keep. Inspect the file, confirm the unit and date, then test any automation. You can [try Health.md for iPhone](https://apps.apple.com/us/app/health-md/id6757763969) or review [Health Auto Export's setup guide](https://help.healthyapps.dev/en/health-auto-export/getting-started/).

If your starting point is an existing Apple XML archive, note that Health.md reads authorized Apple Health data on the iPhone. It does not import or convert that archive. Our [Apple Health export guide](/apple-health-export/) explains the built-in archive and selected-data workflows.
