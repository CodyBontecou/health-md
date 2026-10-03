# Raw API Snapshots

## Status

- **Docs status:** draft
- **Video priority:** medium
- **Primary screen:** Export
- **Source files:** `app/src/main/java/com/healthmd/rawexport/RawSnapshotExportOrchestrator.kt`, `app/src/main/java/com/healthmd/rawexport/RawExportModels.kt`, `docs/export-contract/raw-snapshot-v1.md`

## What it does

Raw API Snapshot is a separate export product next to the normal compatibility export. Instead of converting records into daily `HealthData` summaries, it writes **one immutable, versioned JSON or NDJSON artifact** for the selected range that preserves provider-native records: Health Connect snapshots keep every field the pinned AndroidX API exposes (native IDs, nanosecond timestamps, raw enums, nested samples/stages/routes, exact FHIR JSON), and Fitbit/Oura/WHOOP/Withings snapshots keep the exact successful provider response bytes.

## Who it is for

- Migration and archival workflows that need provider fidelity, not readable summaries
- People leaving a platform who want an API-complete capture before account closure
- Not for journaling — use compatibility exports (Markdown/Bases/JSON/CSV) for daily notes

## Where to find it

1. Open **Export**.
2. Under **Export Target**, select the API endpoint or folder destination.
3. Choose **Raw API Snapshot** as the export mode, pick JSON or NDJSON, and choose the scope (selected record types, or all authorized supported data).

## Prerequisites

- Health Connect permissions for the selected record types, or a connected provider (see [Cloud Providers](./cloud-providers.md))
- For uploads: an HTTPS endpoint — raw uploads require HTTPS and never follow redirects
- Device floor: Android 9 / API 28

## Setup

1. Configure a destination: a folder through the Android folder picker, or an HTTPS API endpoint.
2. Select Raw API Snapshot mode, format, and date range.
3. Preview first — preview performs the full provider-native read into private no-backup storage, shows bounded head/tail text, and deletes the temporary artifact without uploading anything.

## Example output

One JSON or NDJSON file ending with a manifest: per-type status, issues, counts, and checksums. Folder exports also receive a `.sha256` sidecar. Upload requests carry `X-HealthMD-Schema`, `X-HealthMD-Export-ID`, checksum, calendar-zone, and provider headers.

## Tips

- A raw snapshot is API-complete for the pinned provider API — **not** a provider-database backup. It cannot recover inaccessible records, deleted records, or fields unknown to the installed SDK.
- Snapshots are non-transactional: records can change while the export runs; `createdAt` is creation time, not a consistency watermark.
- Unsupported providers are reported as unsupported — never silently replaced with Health Connect data.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Upload rejected | Non-HTTPS URL or a redirect was returned | Use a final HTTPS URL with no redirects |
| Type listed with errors | Provider returned issues for that type | Inspect the manifest's per-type status/issues |
| Fitbit range rejected | Fitbit intraday endpoints are day-scoped; ranges over 366 days are rejected before reads | Split the range or exclude Fitbit |

## Video outline

- **Suggested title:** Archive Your Health Data Exactly as the API Returns It
- **Hook:** "Summaries are for journaling. This is for keeps."
- **Demo flow:** pick raw mode → preview → export NDJSON to folder → inspect manifest.
- **Key screenshot/recording moments:** format toggle, preview text, manifest tail.
- **CTA / next video:** Cloud Providers.

## Implementation notes

`RawSnapshotExportOrchestrator` sorts type keys and metric IDs deterministically, streams records through `DiskBackedCanonicalSpool` under `noBackupFilesDir/raw-export` (batch size 1 for native-payload providers), computes checksums via `DigestOutputStream`, and emits a `RawSnapshotManifest` with per-type `RawTypeReport`s. Statuses: `PENDING/RUNNING/COMPLETE/PARTIAL/CANCELLED/FAILED`. Partial or failed manifests are never uploaded. The `healthmd.raw-changes` backend (Health Connect change tokens + deletion tombstones) supports future incremental archives. Normative contract: [Raw snapshot v1](../export-contract/raw-snapshot-v1.md); record and provider ledgers are linked from it.
