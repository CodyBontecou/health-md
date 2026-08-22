# API Endpoint Export

## Status

- **Docs status:** draft
- **Video priority:** medium
- **Primary screen:** Export
- **Source files:** `app/src/main/java/com/healthmd/data/export/APIExportClient.kt`, `app/src/main/java/com/healthmd/data/export/APIExportCredentialStore.kt`, `app/src/main/java/com/healthmd/data/export/APIExportHeaders.kt`, `docs/api-endpoint-export.md`

## What it does

Instead of (or besides) writing files, Health.md can POST your export to an HTTP(S) endpoint you control. Compatibility mode sends one `healthmd.api_export` JSON envelope; raw mode streams an immutable Raw API Snapshot artifact with checksum headers.

## Who it is for

- Self-hosted dashboards, backups, or automation pipelines that accept JSON/NDJSON
- Users whose analysis tooling lives on a server
- Not for endpoints you don't control — the export contains your health records

## Where to find it

1. Open **Export**.
2. Under **Export Target**, select **API endpoint**.
3. Enter the URL, optional Authorization (token or full `Bearer …`/`Basic …` value), and optional custom headers.

## Prerequisites

- An endpoint that accepts POST with a JSON (or NDJSON) body
- Compatibility exports accept HTTP or HTTPS (HTTP is **not** encrypted in transit); raw snapshots require HTTPS and reject redirects
- Android 9 / API 28+

## Setup

1. Select API endpoint as the target and enter the URL.
2. Add Authorization and custom headers (`Name: value` per line) as needed.
3. Preview, then export — or enable scheduled uploads from the Schedule tab.

## Example output

```json
{
  "schema": "healthmd.api_export",
  "schema_version": 1,
  "daily_record_schema": "healthmd.health_data",
  "exported_at": "2026-07-13T12:00:00Z",
  "source": "android",
  "date_range": { "start": "2026-07-12", "end": "2026-07-13" },
  "record_count": 1,
  "records": [],
  "failed_date_details": []
}
```

Any final `2xx` is success. Raw mode adds `X-HealthMD-Schema`, export-ID, checksum, calendar-zone, and provider headers.

## Tips

- Put secrets in encrypted request headers, not URL query parameters — the URL is stored in plain app preferences.
- Credentials live in Android Keystore-backed `EncryptedSharedPreferences`, excluded from backup, logs, history, and WorkManager input; saved header values are never displayed again.
- Network failures, HTTP 408/429, and `5xx` retry with bounded WorkManager backoff; configuration errors and other `4xx` do not.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| 4xx rejected | Bad path, auth, or headers | Check endpoint path, saved authorization/headers, server logs |
| Raw upload rejected | Non-HTTPS URL or redirect | Use a final HTTPS URL; redirects are always rejected for raw |
| Headers rejected | Malformed/duplicate header, >20 headers, or unsafe framing header | Fix the header lines; framing headers stay app-controlled |

## Video outline

- **Suggested title:** Ship Health Exports Straight to Your Own API
- **Hook:** "No middleman: your phone, your endpoint."
- **Demo flow:** configure URL + token → preview envelope → export → server log shows POST.
- **Key screenshot/recording moments:** Export Target picker, header editor, raw-mode HTTPS notice.
- **CTA / next video:** Raw API Snapshots.

## Implementation notes

`APIExportClient.upload` validates headers via `APIExportHeaders`, applies Authorization then custom headers last (so custom schemes can override), and classifies `408/429/5xx` as retryable. `EncryptedAPIExportCredentialStore` persists secrets with Keystore-backed encryption; saving a raw `Authorization:` header line replaces the convenience Bearer/Basic value. Each action atomically snapshots endpoint + credentials before collecting records. Scheduled API runs store destination type plus a salted one-way URL fingerprint with pending dates, so changing targets cannot silently reroute old pending records. Full request contract: [API endpoint export](../api-endpoint-export.md).
