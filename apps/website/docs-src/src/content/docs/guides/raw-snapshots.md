---
title: Raw API Snapshots
description: Export immutable, versioned JSON or NDJSON snapshots of Health Connect records and Fitbit, Oura, WHOOP, and Withings provider responses with per-type manifests and checksums.
---

<div class="docs-hero">
  <p class="docs-eyebrow">Android · archival-grade export</p>
  <p>Raw API Snapshot is a separate Health.md for Android export product for migration and archival workflows: one immutable, versioned JSON or NDJSON artifact per selected range, preserving native records.</p>
  <div class="docs-actions">
    <a class="docs-button" href="https://play.google.com/store/apps/details?id=com.healthmd.android" target="_blank" rel="noopener">Get on Google Play</a>
    <a class="docs-button-secondary" href="/docs/android/">Android App Guide</a>
  </div>
</div>

## What a raw snapshot is

Compatibility exports convert Health Connect records into readable daily `HealthData` summaries. A raw snapshot skips that conversion entirely:

- **Health Connect snapshots** preserve every field exposed by the pinned AndroidX API, including native identity and metadata, nanosecond timestamps, nullable source offsets, raw enum values, nested samples, stages, routes, and planned-workout structures.
- **Fitbit, Oura, WHOOP, and Withings snapshots** preserve the exact successful provider response bytes and disclose endpoint pagination and server-side aggregation. Providers that are not supported are reported rather than normalized or silently replaced with Health Connect data.
- Every artifact ends with a **manifest** containing per-type status, issues, counts, and checksums. Folder exports also receive a `.sha256` sidecar.

A raw snapshot is API-complete for the app's pinned provider API, not a transactional provider-database backup. It cannot recover inaccessible records, original units the API does not expose, deleted records, or fields unknown to the installed SDK.

## Preview before destination

Raw snapshots can be previewed without a configured destination. Preview performs the full provider-native read into private no-backup storage, keeps only bounded head/tail text in memory, and deletes the temporary artifact without uploading anything.

## Delivery rules

Raw API uploads are deliberately stricter than compatibility API exports:

| Rule | Reason |
|---|---|
| HTTPS only | The streamed artifact never travels in plaintext |
| Redirects rejected | The artifact and credentials can never be replayed to another origin |
| Schema, export, and checksum headers | The receiving endpoint can verify what it accepted |
| Temporary private artifact deleted after the attempt | No copy lingers on device |

## Incremental archives

The separately versioned `healthmd.raw-changes` backend uses Health Connect change tokens and deletion tombstones for future incremental archive workflows, so a full snapshot does not have to be the only archival strategy.

## Requirements

- Health.md for Android with the Raw API Snapshot product.
- Health Connect permissions for the selected record types, or a connected Fitbit, Oura, WHOOP, or Withings account for provider snapshots.
- An HTTPS endpoint if you upload snapshots; local folder export has no transport requirements.

## Where to learn more

- [Raw snapshot v1 contract](https://github.com/CodyBontecou/health-md/blob/main/apps/android/docs/export-contract/raw-snapshot-v1.md)
- [Raw record v1 contract](https://github.com/CodyBontecou/health-md/blob/main/apps/android/docs/export-contract/raw-record-v1.md)
- [Raw changes v1 contract](https://github.com/CodyBontecou/health-md/blob/main/apps/android/docs/export-contract/raw-changes-v1.md)
