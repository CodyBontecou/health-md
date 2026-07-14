# API Endpoint Export

Health.md can send selected Health Connect records directly to an HTTP or HTTPS endpoint configured by the user. This is an explicit alternative to Device Folder export; Health.md does not proxy or store the request.

## Configure

1. Open **Export**.
2. Under **Export Target**, select **API endpoint**.
3. Enter an `http://` or `https://` URL.
4. Optionally enter a token or full `Bearer …` / `Basic …` Authorization value.
5. Optionally add raw request headers, one `Name: value` per line—for example `X-API-Key`, `X-Client-ID`, or an `Authorization` value using a custom scheme.
6. Choose dates, metrics, and time-series settings, then preview or export.

The URL is stored in private app preferences. Authorization and custom header values are stored separately with Android EncryptedSharedPreferences backed by Android Keystore. Export settings and encrypted secrets are excluded from Android backup/device transfer, UI labels, export history, logs, and WorkManager input. Because URL query parameters are part of the settings URL, put API keys and other secrets in encrypted request headers instead. Saved header values are not displayed again; entering new custom headers replaces the complete saved custom-header set.

HTTP and HTTPS endpoints are accepted. HTTP connections send health data and configured headers without transport encryption. Standard HTTP redirects are followed, including redirects between HTTP and HTTPS, so only configure URLs whose full redirect chain you trust. OkHttp removes the `Authorization` header when a redirect changes origin, but other custom headers can be forwarded. URL fragments and embedded username/password values remain rejected.

Health.md also rejects malformed or duplicate headers, control characters, more than 20 custom headers, and unsafe framing/proxy headers. `Content-Type`, `Content-Length`, `Host`, `Connection`, `Transfer-Encoding`, and related framing headers remain controlled by the app. Custom headers are applied after the optional Authorization field. Saving a raw `Authorization: …` line clears and replaces the convenience Bearer/Basic value, preventing a hidden credential from resurfacing later.

## Request

Each export action atomically snapshots its endpoint, Authorization value, and custom headers before collecting records, then sends one request:

```http
POST /your/path HTTP/1.1
Content-Type: application/json
Accept: application/json
Authorization: Bearer … # only when configured
X-API-Key: …           # example custom header
```

The body is a JSON envelope:

```json
{
  "schema": "healthmd.api_export",
  "schema_version": 1,
  "daily_record_schema": "healthmd.health_data",
  "daily_record_schema_version": 4,
  "exported_at": "2026-07-13T12:00:00Z",
  "source": "android",
  "date_range": { "start": "2026-07-12", "end": "2026-07-13" },
  "record_count": 1,
  "records": [],
  "failed_date_details": []
}
```

`records` contains the existing Android/iOS-compatible daily JSON export shape after applying the selected metrics and granular-data settings. Dates with no readable data are omitted from `records` and included in `failed_date_details`.

Any final `2xx` response is successful. Redirects use OkHttp’s standard behavior: `301`, `302`, and `303` can change the redirected POST to GET, while `307` and `308` preserve the POST method and JSON body. Network failures, HTTP 408/429, and server `5xx` responses are eligible for bounded WorkManager retry; invalid configuration and ordinary `4xx` responses are not.

Any valid end-to-end request header can be configured, including `Authorization`, `X-API-Key`, vendor-specific version headers, and custom `Accept` or `User-Agent` values. The request body always remains JSON.

## Scheduled exports and recovery

The Schedule screen has its own destination selection. API schedules require network connectivity and Full Access. When Android’s Alarms & reminders access is granted, Health.md uses a one-shot exact alarm for each intended occurrence and immediately dispatches expedited export work. A durable one-time WorkManager trigger remains as a delayed backup and becomes the primary scheduler when exact-alarm access is unavailable. Each occurrence carries its intended local date, so a delayed start or retry cannot accidentally export a different day after midnight. Alarms are restored after reboot, app update, clock/timezone changes, and exact-alarm access changes.

Failed scheduled work records its destination type and a salted one-way fingerprint of the configured API URL plus encrypted request credentials/headers with each pending date. Changing the target cannot retry API data into a device folder, and changing the endpoint or routing/authentication headers cannot automatically send old pending records to a different service or tenant. Neither secrets nor unsalted secret hashes are written to WorkManager or DataStore. History retries are explicit user actions: they preserve the destination type but use the currently configured endpoint and headers, which may differ from the original request.

## Privacy

API Endpoint export intentionally transmits the selected health records to the configured service and any redirect destinations. Use only endpoints and redirect chains you control or trust, prefer HTTPS, minimize selected metrics, and disable time-series data unless needed. HTTP traffic is not encrypted in transit. The receiving service controls its own logging, storage, and retention behavior.
