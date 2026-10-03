---
title: "Sleep dates and daily notes"
description: "Learn why overnight sleep belongs to its start date and which range to export in the morning."
---

Health.md assigns a sleep session to the date on which it **started**. Sleep from Monday at 11:45 PM to Tuesday at 7:30 AM belongs to Monday's summary. Apple and Android share this rule even when Health Connect displays the wake date.

| Goal | Export |
|---|---|
| Last night's sleep on Tuesday morning | **Yesterday** (Monday) |
| Tuesday's activity | **Today** |
| Both | Monday and Tuesday |

Readable summaries keep the night together. Canonical source records retain their original start and end and belong to the start day; Health.md does not invent two halves. Use `healthmd_sleep_sessions` when software needs session semantics.

Daily Note Injection and API Endpoint use the same attribution. If the source synchronizes late, export the start day again. Health.md does not currently offer a setting that moves summaries to the wake date.

<div class="related"><a href="/docs/scheduling/"><span>Automation</span>Include Yesterday in a morning run.</a><a href="/docs/troubleshooting/"><span>Help</span>Diagnose empty or delayed data.</a></div>
