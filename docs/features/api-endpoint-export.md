# API Endpoint Export

## Status

- **Docs status:** draft
- **Video priority:** medium
- **Primary screen:** Export → Export Target → API Endpoint
- **Source files:** `HealthMd/Shared/Models/APIExportSettings.swift`, `HealthMd/Shared/Managers/APIExportClient.swift`, `HealthMd/Shared/Managers/APIEndpointExportRunner.swift`, `HealthMd/Shared/Export/JSONExporter.swift`

## What it does

API Endpoint export POSTs selected daily JSON records directly from iPhone to a user-configured HTTP(S) endpoint. Each record follows current `healthmd.health_data` schema v7. With **Lossless Health Records** on, it includes the authoritative `healthkit_record_archive` (`healthmd.healthkit_records` v1) alongside daily summaries.

Lossless Health Records is on by default for new installs; an existing explicit off choice remains summary-only. API export respects the selected metrics and this setting. The exhaustive envelope, request/response, sidecar, and parser contract is in [API and CLI](../reference/api-and-cli.md), with complete generated JSON fixtures.

## Setup

1. Open **Export → Export Target → API Endpoint**.
2. Enter a URL such as `https://api.example.com/healthmd/ingest`.
3. Optionally enter an access token; Health.md stores it in Keychain.
4. Choose metrics and review **Lossless Health Records**.
5. Export one day before sending a long range.

Plain tokens are sent as `Bearer <token>`. Values beginning with `Bearer ` or `Basic ` are sent as entered.

## Payload shape (abridged)

Complete v1 and provider-sidecar v2 envelopes are under [`docs/reference/generated/automation/`](../reference/generated/automation/).

```json
{
  "schema": "healthmd.api_export",
  "schema_version": 1,
  "daily_record_schema": "healthmd.health_data",
  "daily_record_schema_version": 7,
  "exported_at": "2026-07-15T17:24:00.000Z",
  "source": "ios",
  "date_range": {
    "start": "2026-07-14",
    "end": "2026-07-15"
  },
  "record_count": 2,
  "records": [
    {
      "schema": "healthmd.health_data",
      "schema_version": 7,
      "date": "2026-07-14",
      "raw_capture_status": "complete",
      "time_context": {
        "calendar_timezone": "America/Los_Angeles",
        "timestamp_timezone": "UTC"
      },
      "activity": { "steps": 8432 },
      "healthkit_record_archive": {
        "schema": "healthmd.healthkit_records",
        "schema_version": 1,
        "capture_status": "complete",
        "records": [],
        "query_manifest": { "results": [] }
      }
    }
  ],
  "failed_date_details": []
}
```

`records` contains the same public document described in [JSON Export](./json-export.md). A complete-empty lossless day is retained because its query manifest is evidence; dates that fail before a daily document can be built are reported through `failed_date_details`.

Provider sidecars use independent rollout/versioning. With WHOOP enabled, the API wrapper may advance to v2 and add `external_records`; that does not change daily schema v7 or the HealthKit archive.

## Endpoint guidance

- Validate authorization and `Content-Type: application/json`.
- Accept idempotent repeats for the same date range.
- Branch on envelope, daily, and archive schema versions independently.
- Check `raw_capture_status`, every query-manifest result, warnings, and partial failures.
- Treat summaries as projections; use the archive for exact source identity.
- Deduplicate UUID-backed records only by UUID and external records only by documented external identity.
- Return `2xx` only after safely accepting the payload.

Health.md treats `200...299` as success. Other statuses fail the action and may show a short response preview.

## Privacy and security

API Endpoint intentionally sends health data to the service you configure. Lossless payloads may include exact timestamps, source/device details, clinical content, State of Mind, medications, routes, ECG measurements, and base64 binary attachments.

- Use an endpoint you control or trust.
- Prefer HTTPS for real data.
- Select only required metrics.
- Turn Lossless Health Records off if the receiver needs summaries only.
- Apply retention, encryption, and access controls appropriate for sensitive health data.
- Rotate/remove tokens when no longer needed.

Health.md preserves source URLs as data but never fetches them. Your receiver should not automatically follow untrusted/source URLs without its own security policy.

## Scheduled API exports

Scheduled API exports use the same selected metrics and Lossless Health Records setting. They send the configured complete-day lookback ending yesterday and preserve pending work when HealthKit is locked or upload fails.

## Practical limits

One API action serializes a JSON envelope for the selected range. Dense routes, ECGs, FHIR/CDA documents, WorkoutKit data, or attachments can make the request large and can require substantial memory before upload.

For large historical ranges, Health.md automatically splits the selected dates into bounded, sequential batches (7 calendar days per batch by default) instead of sending one oversized request. Batches upload one at a time, in date order; each batch has its own `date_range`, `record_count`, `records`, and `failed_date_details`. The endpoint URL and authorization value are snapshotted when the action starts, so every batch in that action goes to the same destination even if saved settings change while it runs. A batch containing only failed dates is sent as a scoped `record_count: 0` envelope when the same run also has a deliverable data batch; an entirely empty range still sends no request. If a batch fails, Health.md stops immediately — no later batches are sent — and reports which date range failed, while all earlier, successfully uploaded batches remain counted as successful.

Scheduled retries persist only unresolved dates. Successfully uploaded records and successfully reported terminal no-data dates are removed from pending work, while device-lock, HealthKit, transport, cancellation, and unattempted dates remain retryable. Your endpoint may still receive a repeated date when its earlier outcome was not durably accepted, so it should retain the latest revision for a given day.

If dense per-day payloads are still too large for your endpoint even at the default batch size, reduce the selected range or turn off Lossless Health Records.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Target is not ready | URL is empty/invalid | Enter a valid HTTP(S) URL. |
| HTTP 401/403 | Token missing, expired, or wrong scheme | Update the token/header value. |
| HTTP 413 | Lossless payload or a single batch is too large | Reduce the range or turn off Lossless Health Records. |
| Archive is absent | Lossless Health Records was off or legacy source used | Check `raw_capture_status`; re-export if needed. |
| Archive is partial | One source branch did not complete | Inspect manifest/warnings/partial failures; do not mark ingestion complete. |
| Some dates are absent | No retained data or date fetch failed | Inspect `failed_date_details` and selected metrics. |
| Export stopped partway through a large range | A batch upload failed | Check the reported failed date range, fix the underlying issue (auth, size, connectivity), and re-run — already-uploaded batches are safe to resend. |

## Implementation notes

- `APIEndpointExportRunner` fetches/filters dates, tracks partial failures, and splits the normalized date range into sequential batches (`APIEndpointExportRunner.defaultMaxBatchDaySpan`, 7 days by default) that are uploaded one at a time. It stops on the first failed batch and preserves the success count from prior batches.
- `APIExportClient` wraps public v7 daily JSON and stores the optional token in Keychain-backed settings; it is invoked once per batch with that batch's own records, failed-date details, date range, and immutable request-scoped destination snapshot.
- `JSONExporter` and `HealthKitRecordArchiveSerializer` own the daily/archive contracts.
- API output is direct iPhone → configured endpoint; Health.md does not proxy it through its servers.
