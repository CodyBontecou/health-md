---
title: "Health.md for Mac gives iPhone exports a desktop destination."
description: "How the Health.md Mac app works as a local destination for iPhone-configured Apple Health exports."
lead: "The Mac app is built for people whose archive, Obsidian vault, scripts, or backups live on a desktop machine, while Apple Health still lives on iPhone."
date: "2026-06-12"
updated: "2026-07-16"
category: "Product update"
draft: false
image: "/assets/screenshots/optimized/macos-sync-with-iphone-1200.webp"
imageAlt: "Health.md Mac sync with iPhone"
showCover: false
tags:
  - healthmd
  - macos
  - apple-health
---
<figure>
<img alt="Health.md Mac sync with iPhone" decoding="async" height="750" src="/assets/screenshots/optimized/macos-sync-with-iphone-1200.webp" width="1200"/>
<figcaption>The Mac app stays ready to receive iPhone-configured export jobs.</figcaption>
</figure>

Health.md already lets you export Apple Health data into local Markdown, JSON, CSV, and Obsidian Bases files. The Mac companion extends that workflow by making your Mac the renderer and destination for iPhone-captured export jobs.

The important detail is that the iPhone remains the HealthKit source. Your iPhone captures the selected Apple Health data and an exact snapshot of the metrics, formats, date range, filename template, folder structure, and write mode. It transfers that versioned job to the Mac, where shared exporters render and write the requested files into the folder you chose.

## Why use the Mac destination?

- Your Obsidian vault only lives on your Mac.
- You want exports written directly into a folder that is backed up or versioned on macOS.
- You prefer desktop storage for large backfills and long-term health archives.
- You want a menu bar app that keeps destination readiness visible.

<figure>
<img alt="Health.md Mac export destination" decoding="async" height="750" loading="lazy" src="/assets/screenshots/optimized/macos-export-health-data-1200.webp" width="1200"/>
<figcaption>Choose a destination folder on Mac, then configure and launch the export from iPhone.</figcaption>
</figure>

## What stays private

No remote account is required for this workflow. The Mac destination is local to your Apple devices and folders. Health data is not uploaded to a Health.md cloud service. The files land where you choose: local disk, iCloud Drive, an Obsidian vault, or another folder available to macOS.

## What to read next

The updated docs include a Mac Sync guide, a macOS app guide, and a production-backed Export Reference covering every public schema, metric definition, source-record shape, field, format, and connected protocol.

<div class="cta-row">
<a class="button" href="/docs/sync/">Read Mac Sync docs</a>
<a class="button secondary" href="/docs/reference/">Open Export Reference</a>
</div>
