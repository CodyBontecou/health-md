---
title: "Troubleshooting Health.md"
description: "Diagnose empty exports, missing sleep, unavailable phones, schedules, folders, partial results, and timeouts."
---

Start with one device, one day, one category, and one destination. Do not publish health data, routes, clinical documents, tokens, pairing codes, or private paths.

## Empty data

Confirm the value in Apple Health or Health Connect, review permission, and export one category for one day. Distinguish `complete_empty`, missing permission, unsupported, skipped, partial, and failed. Missing is not zero.

## Sleep is missing from Today

Sleep belongs to the day on which the night began. On Tuesday morning, export **Yesterday**, or Monday and Tuesday. See [Sleep dates](/docs/sleep-date-attribution/).

## Files and schedules

Check the vault, folder access, subfolder, template, and profile. iOS background work and Android WorkManager use target times, not universal guarantees. Unlock the device and use pending recovery.

## CLI timeout

A timeout does not cancel an accepted job:

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300
```

Before claiming completeness, inspect status, missing dates, coverage, `next_cursor`, version, and limitations. `--allow-partial` changes exit policy only.

<div class="related"><a href="/docs/cli-jobs/"><span>Jobs</span>Resume and cancel safely.</a><a href="/docs/release-status/"><span>Versions</span>Check exact compatibility.</a></div>
