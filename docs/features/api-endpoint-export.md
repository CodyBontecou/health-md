# API Endpoint Export

## Status

- **Docs status:** draft
- **Video priority:** medium
- **Primary screen:** Export → Export Target → API Endpoint
- **Source files:** `HealthMd/iOS/Views/ExportTabView.swift`, `HealthMd/iOS/ContentView.swift`, `HealthMd/Shared/Models/APIExportSettings.swift`, `HealthMd/Shared/Managers/APIExportClient.swift`

## What it does

API Endpoint export sends Apple Health data directly from the iPhone app to a user-configured HTTP(S) endpoint. Instead of writing files to an iPhone folder or a connected Mac, Health.md fetches the selected dates from HealthKit, applies the current metric and granular-data settings, wraps the existing public Health.md JSON records in an API envelope, and POSTs that JSON to your endpoint. API Endpoint can be used manually from the Export tab or as the destination for Scheduled Exports.

Use this when you want Health.md data to feed your own server, webhook, automation, database, dashboard, or personal data pipeline.

## Who it is for

- Users who run their own API, webhook, or ingestion service.
- Developers building dashboards or automations on top of Health.md JSON.
- Users who prefer direct upload over local file handoff.
- Teams testing a controlled pipeline before adding downstream processing.

For local-only workflows, use **Local iPhone Folder** or **Connected Mac** instead.

## Where to find it

1. Open Health.md on iPhone.
2. Go to **Export**.
3. In **Export Target**, tap **API Endpoint**.
4. Enter the endpoint URL.
5. Optionally enter a bearer token.
6. Tap **Done**.
7. Choose date range, metrics, and export options.
8. Tap **Export**.

## Prerequisites

- HealthKit permission granted.
- At least one export format selected. The API payload uses JSON records, but the export gate still requires a selected format.
- At least one enabled metric with data for the selected dates.
- A valid HTTP or HTTPS endpoint URL.
- Free export quota remaining or Full Access unlocked.
- Your endpoint must accept `POST` requests with `Content-Type: application/json`.

## Setup

1. Choose **API Endpoint** as the export target.
2. Enter a URL such as:

   ```text
   https://api.example.com/healthmd/ingest
   ```

3. Optional: enter an access token. Health.md stores it in Keychain.
4. Configure **Health Metrics** to limit what is sent.
5. Turn **Time-Series Data** on only if your endpoint needs timestamped samples.
6. Choose the date range.
7. Tap **Export**.

If the token field is filled, Health.md sends an `Authorization` header. Plain tokens are sent as `Bearer <token>`. If the value already starts with `Bearer ` or `Basic `, Health.md sends it as entered.

## Payload shape

Health.md sends one POST per export action. The body is a JSON envelope:

```json
{
  "schema": "healthmd.api_export",
  "schema_version": 1,
  "daily_record_schema": "healthmd.health_data",
  "daily_record_schema_version": 2,
  "exported_at": "2026-07-01T17:24:00.000Z",
  "source": "ios",
  "date_range": {
    "start": "2026-06-30",
    "end": "2026-07-01"
  },
  "record_count": 2,
  "records": [
    {
      "schema": "healthmd.health_data",
      "schema_version": 2,
      "date": "2026-06-30",
      "type": "health-data",
      "unit_system": "metric",
      "units": {
        "steps": "count"
      },
      "activity": {
        "steps": 8432
      }
    }
  ],
  "failed_date_details": []
}
```

`records` contains the same public daily JSON shape documented in [JSON Export](./json-export.md) and governed by the [Export schema contract](./export-schema.md). Empty dates are omitted from `records` and reported in `failed_date_details`.

Connected-app provider sidecars are deferred and are not part of the active API payload while `ConnectedAppsFeature.isEnabled` is false.

## Endpoint behavior

Health.md treats any HTTP status in the `200...299` range as success. Other status codes fail the export and show the response preview in the error message when available.

Recommended endpoint behavior:

- Validate the `Authorization` header if you configured a token.
- Accept idempotent repeats for the same date range.
- Store or process each object in `records` by its `date` field.
- Return a `2xx` response only after the payload is safely accepted.
- Keep response bodies short; Health.md only shows a short preview in errors.

## Privacy notes

API Endpoint export intentionally sends selected Apple Health data to the endpoint you configure. Health.md does not proxy the request through Health.md servers, but the receiving service can store, log, or forward the data according to that service's behavior.

Before exporting to an API:

- Use an endpoint you control or trust.
- Prefer HTTPS for real health data.
- Limit metrics to only what the endpoint needs.
- Review whether granular time-series samples are necessary.
- Rotate or remove the token if you stop using the endpoint.

## Scheduled API exports

1. Configure the API Endpoint URL and optional token in **Export → Export Target → API Endpoint**.
2. Open the **Schedule** tab.
3. Enable Scheduled Exports.
4. Set **Export Destination** to **API Endpoint**.
5. Choose the frequency, preferred time, and lookback window.

Scheduled API exports POST the same `healthmd.api_export` envelope as a manual API export. The scheduled run uses the configured lookback window ending yesterday, respects metric selection and time-series settings, and preserves pending work if HealthKit data is locked or the endpoint upload fails.

## Tips

- Test with a one-day range before sending a long backfill.
- Use a temporary webhook inspector only with non-sensitive test data.
- If your endpoint needs flat rows, transform the JSON server-side rather than asking Health.md to emit CSV to the API target.
- Use the Schedule tab’s destination picker when you want the upload to run daily or weekly.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| API target says it is not ready | Endpoint URL is empty or invalid | Tap API Endpoint and enter a valid HTTP(S) URL. |
| Export fails with HTTP 401 or 403 | Token missing, expired, or rejected | Update the token in API Endpoint settings. |
| Export fails with HTTP 404 | Endpoint path is wrong | Check the URL and server route. |
| Export fails with HTTP 413 | Payload is too large | Reduce the date range or disable time-series data. |
| Some dates are missing from `records` | Those dates had no enabled HealthKit data or failed to fetch | Check `failed_date_details`, metric selection, and Apple Health data. |
| Token appears not to work | Endpoint expects a different auth scheme | Include the full header value, such as `Basic ...`, if needed. |

## Video outline

- **Suggested title:** Send Apple Health Data to Your Own API with Health.md
- **Hook:** “Health.md can export to files, your Mac, or directly to your own endpoint.”
- **Demo flow:**
  1. Show Export Target and select API Endpoint.
  2. Enter an HTTPS ingest URL and optional token.
  3. Choose a small date range and a few metrics.
  4. Tap Export and show the upload status.
  5. Show the received JSON envelope on the server side.
  6. Explain privacy and why users should only send to trusted endpoints.
- **Key screenshot/recording moments:** API Endpoint card, settings sheet, progress message, server payload.
- **CTA / next video:** “Next, we’ll build a small dashboard from the JSON payload.”

## Implementation notes

- `APIExportSettings` stores the endpoint URL in `UserDefaults` and the optional token in Keychain.
- `ContentView.exportDataToAPIEndpoint()` fetches each requested date from HealthKit, filters by metric selection, tracks partial failures, and uploads only days with data.
- `APIExportClient` builds a `healthmd.api_export` envelope containing public `healthmd.health_data` JSON daily records.
- Connected-app provider sidecars remain implemented but deferred behind `ConnectedAppsFeature.isEnabled == false`; when revived, the API envelope version should change independently from the daily `HealthMdExportSchema.version`.
- API exports count as an export action when at least one day uploads successfully.
