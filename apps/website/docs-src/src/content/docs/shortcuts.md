---
title: "Shortcuts & App Intents"
description: "Use seven Health.md actions from Shortcuts and Siri. Mac context refresh actions are proposed, not available."
---

<div class="availability preview"><strong>Seven actions registered in source</strong><p>Refresh Mac Health Context and Get Mac Context Refresh Status are proposed, not implemented or development-available. Track <a href="https://github.com/CodyBontecou/health-md/issues/173">issue #173</a>; availability requires implementation, qualification, and an exact Apple release note.</p></div>

## Actions

- export yesterday, one date, a range, or the last N days;
- get a health summary or the last export status;
- turn scheduling on or off.

### Proposed Mac context actions (not available)

The requested **Refresh Mac Health Context** action would use an explicit profile/date scope, authenticated compatible peers, and durable context acquisition without export files or file-export quota. **Get Mac Context Refresh Status** would report pending/completed/failed status with a recoverable job identity. These are requirements, not supported action names, parameters, or results in the current app.

Computer-side MCP refresh does not satisfy an iOS personal automation. Do not use ordinary Export Shortcuts as a substitute: they retain iPhone-folder semantics. No automation can be promised to wake a sleeping Mac or bypass protected HealthKit data. Physical-iPhone automation QA after wake is still required before this feature can be qualified.

The four export actions accept an optional **Profile**. An unknown name fails without fallback. Ordinary Shortcuts write to the iPhone folder and do not silently switch to API Endpoint or Connected Mac.

Allowing locked execution does not unlock HealthKit. Health.md preserves the request and shows **Health Export Needs Attention**.

### Morning automation

1. Create a time automation.
2. Add **Export Yesterday's Health Data**.
3. Add **Get Last Export Status** and a notification.

Yesterday includes sleep whose night began yesterday. See [Sleep dates](/docs/sleep-date-attribution/).

<div class="related"><a href="/docs/export-profiles/"><span>Profiles</span>Use stable identities.</a><a href="/docs/release-status/"><span>Compatibility</span>Check qualified versions.</a></div>
