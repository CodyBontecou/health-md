---
title: "How to export your health data without the cloud."
description: "Keep your Apple Health export fully local: what to check in any exporter, and how Health.md keeps the cloud out of the path."
lead: "Local export is a checklist, not a vibe: where the read happens, where the file lands, and who else gets a copy."
date: "2026-09-26T12:00:00.000Z"
updated: "2026-09-26T12:00:00.000Z"
category: "Workflow guide"
draft: false
verified: "2026-09-26"
verified_by: "Edison (agent)"
verified_method: traced
tags:
  - healthmd
  - apple-health
  - privacy
  - local-first
---

Exporting your health data sounds like a local operation. It usually isn't. Plenty of "export" apps route your data through their own servers, require an account before you can even start, or hand the file to a sync service without telling you. None of that is visible in the App Store screenshots.

If you want an export that stays yours — no server in the middle, no account, no mystery copy — you don't need to read a whitepaper. You need a short checklist and a tool that passes it.

## Four questions for any health exporter

For a local folder export, ask these before you trust the tool with your health data. The answers should be obvious in under a minute; if they're buried in a privacy policy, that's an answer too.

**1. Where does the read happen — on your phone or their server?**
The read should happen on your device, through the platform's health API. If the app uploads your health records to process them, you're not exporting from your phone — you're giving a server your data and getting a file back.

**2. Does it need an account?**
Writing a local file shouldn't require a login, a profile, or an email address. A cloud destination is different: ask what its account controls and what data the service retains.

**3. Where does the file land — a folder you chose?**
A local folder export ends with a file in a place you picked: a folder, your notes vault, your own computer. If the file lands "in the app" with a share button as the only way out, the app is the destination, not a stop along the way.

**4. Does anything get uploaded — and if so, where exactly?**
Sometimes an upload is legitimate: you might *want* the file in your cloud storage. The question is whether the destination is your explicit choice, or a silent hop through the vendor's cloud on the way there.

A vendor's own server should never be an unlisted stop on the route.

## Doing it with Health.md

Health.md's local folder export passes that checklist, so the walkthrough is short:

1. **Install and authorize.** Download Health.md and authorize the Apple Health categories you want to share. Health permissions stay under your control, and no Health.md account is required for this local folder workflow.
2. **Pick what, where, and when.** Choose the metrics, a format (CSV, JSON, Markdown, or Obsidian), a non-synced local folder such as one under On My iPhone, and a date range.
3. **Preview, then export.** You see exactly what will be written before anything is created. The files land where you chose — ready for spreadsheets, notes, or analysis tools.

For this local folder workflow, the read happens on your iPhone through HealthKit and the file is built on-device. The export goes directly to the folder you chose, without uploading it to a Health.md server. Local files still need protection: they can contain sensitive records and identifiers.

A folder is only fully local if it isn't synced. If *you* choose iCloud Drive, Google Drive, or Obsidian Sync as the destination, that provider's own sync and privacy model applies to the file. Check the folder's sync and backup settings before calling the export cloud-free.

This guide doesn't use the separate opt-in, single-owner Health.md Cloud pilot. That pilot retains only API exports intentionally sent to it, has no public signup or automatic device sync, and is not generally available. See the [privacy policy](/privacy-policy.html) for that separate destination's boundaries.

## What "private export" means in practice

For this local folder workflow, there are a few concrete properties you can verify:

- **No Health.md login for local export.** That doesn't anonymize your records; they can still contain identifiers from the source health data.
- **Plain files you can delete.** You can open, move, or delete the local file yourself. Copies in synced folders, backups, or a recipient's service follow that destination's retention and deletion rules.
- **No health values in product analytics.** Health.md's product telemetry excludes health values, health dates, and export contents. Those exclusions are separate from any upload you choose.

Keeping the folder off sync services keeps this export out of cloud storage. Choosing a synced folder or sending the file elsewhere changes that boundary.

## Going deeper

If you want the engineering version of this — where reads happen, how destinations and credentials are handled, and where the cloud boundaries are drawn — read [What local-first health-data architecture actually means](/blog/local-first-health-data-architecture/). That's the design contract; this post is the consumer checklist.

And if you're ready to try it: [export your Apple Health data](/apple-health-export/) with the formats and destinations above.

<div class="cta-row">
<a class="button" href="/apple-health-export/">Export your Apple Health data</a>
<a class="button secondary" href="/docs/">Read the product docs</a>
</div>
