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

Before you trust an exporter with your health data, ask these. The answers should be obvious in under a minute; if they're buried in a privacy policy, that's an answer too.

**1. Where does the read happen — on your phone or their server?**
The read should happen on your device, through the platform's health API. If the app uploads your health records to process them, you're not exporting from your phone — you're giving a server your data and getting a file back.

**2. Does it need an account?**
An export is a file operation. It shouldn't require a login, a profile, or an email address. If an app won't let you export without an account, your data is touching their infrastructure somewhere.

**3. Where does the file land — a folder you chose?**
A real export ends with a file in a place you picked: a folder, your notes vault, your own computer. If the file lands "in the app" with a share button as the only way out, the app is the destination, not a stop along the way.

**4. Does anything get uploaded — and if so, where exactly?**
Sometimes an upload is legitimate: you might *want* the file in your cloud storage. The question is whether the destination is your explicit choice, or a silent hop through the vendor's cloud on the way there.

A vendor's own server should never be an unlisted stop on the route.

## Doing it with Health.md

Health.md is built to pass that checklist, so the walkthrough is short:

1. **Install and authorize.** Download Health.md and authorize the Apple Health categories you want to share. Health permissions stay under your control, and no Health.md account is required.
2. **Pick what, where, and when.** Choose the metrics, a format (CSV, JSON, Markdown, or Obsidian), a destination folder you control, and a date range.
3. **Preview, then export.** You see exactly what will be written before anything is created. The files land where you chose — ready for spreadsheets, notes, or analysis tools.

The read happens on your iPhone through HealthKit. The file is built on-device. There is no Health.md health-data server in the path, so there's nothing to sign up for and nothing to leak.

One honest nuance: "Health.md has no cloud hop" describes Health.md's side of the trip, not yours. If *you* choose iCloud Drive, Google Drive, or Obsidian Sync as the destination, that provider's own sync and privacy model applies to the file from that point on. That's your choice, explicitly made — which is the whole point. A local-first tool doesn't magically make your chosen sync provider local; it makes sure the provider is your choice, not the vendor's.

## What "private export" means in practice

A private export isn't a feeling. It's a few concrete properties you can verify:

- **No account in the path.** There's nothing to log into, so there's no identity to attach your health data to.
- **Plain files you can delete.** The export is a normal file in a folder you chose. You can open it, move it, back it up, or delete it yourself — no retention policy to read, no "contact support to delete your data."
- **No health values in analytics.** Product telemetry, if any, must not contain your metrics, dates, or file contents. The numbers stay in your file.

That's the bar. If an exporter clears those four checklist questions and gives you a file you fully control, the cloud question answers itself: the only cloud involved is the one you picked.

## Going deeper

If you want the engineering version of this — where reads happen, how destinations and credentials are handled, and where the cloud boundaries are drawn — read [What local-first health-data architecture actually means](/blog/local-first-health-data-architecture/). That's the design contract; this post is the consumer checklist.

And if you're ready to try it: [export your Apple Health data](/apple-health-export/) with the formats and destinations above.

<div class="cta-row">
<a class="button" href="/apple-health-export/">Export your Apple Health data</a>
<a class="button secondary" href="/docs/">Read the product docs</a>
</div>
