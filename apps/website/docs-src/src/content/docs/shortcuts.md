---
title: "Shortcuts & App Intents"
description: "Use seven published actions and two current-development Mac context actions from Shortcuts and Siri."
---

<div class="availability preview"><strong>Seven published actions · nine in current source</strong><p>The two Mac context actions require compatible iPhone and Mac builds. Check the exact release notes.</p></div>

## Actions

- export yesterday, one date, a range, or the last N days;
- get a health summary or the last export status;
- turn scheduling on or off;
- **Refresh Mac Health Context** (development): request a durable encrypted-context refresh bound to a profile;
- **Get Mac Context Refresh Status** (development): read its status and job ID.

The four export actions accept an optional **Profile**. An unknown name fails without fallback. Ordinary Shortcuts write to the iPhone folder and do not silently switch to API Endpoint or Connected Mac.

Allowing locked execution does not unlock HealthKit. Health.md preserves the request and shows **Health Export Needs Attention**.

### Morning automation

1. Create a time automation.
2. Add **Export Yesterday's Health Data**.
3. Add **Get Last Export Status** and a notification.

Yesterday includes sleep whose night began yesterday. See [Sleep dates](/docs/sleep-date-attribution/).

<div class="related"><a href="/docs/export-profiles/"><span>Profiles</span>Use stable identities.</a><a href="/docs/release-status/"><span>Compatibility</span>Check qualified versions.</a></div>
