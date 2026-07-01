---
title: "API Endpoint"
description: "Send selected Apple Health JSON directly from iPhone to your own HTTP(S) endpoint."
---

<p>API Endpoint is an export target for users who want Health.md data to flow into their own server, webhook, database, dashboard, or automation. The iPhone still reads Apple Health; instead of writing files, it POSTs JSON to the endpoint you configure.</p>

<div class="callout">
<strong>Privacy reminder.</strong>
<p style="margin-top:6px;">This target intentionally sends selected health data to the URL you enter. Use an endpoint you control or trust, prefer HTTPS, and limit metrics to what your service actually needs.</p>
</div>

## Set up the target

<ol>
<li>Open Health.md on iPhone.</li>
<li>Go to <strong>Export</strong>.</li>
<li>In <strong>Export Target</strong>, choose <strong>API Endpoint</strong>.</li>
<li>Enter a URL such as <code>https://api.example.com/healthmd/ingest</code>.</li>
<li>Optional: enter a bearer token. Health.md stores it in Keychain.</li>
<li>Tap <strong>Done</strong>, choose your date range and metrics, then tap <strong>Export</strong>.</li>
</ol>

<p>If you enter a plain token, Health.md sends it as <code>Authorization: Bearer &lt;token&gt;</code>. If the value already starts with <code>Bearer </code> or <code>Basic </code>, Health.md sends it as entered.</p>

## Payload shape

<p>Health.md sends one POST per export action. The body is a wrapper envelope with one public Health.md JSON record per successful day.</p>

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
      "units": {},
      "activity": {
        "steps": 8432
      }
    }
  ],
  "failed_date_details": []
}
```

<div class="options">
<div class="option"><strong><code>records</code></strong><p>Daily Health.md JSON objects for dates that had enabled HealthKit data.</p></div>
<div class="option"><strong><code>failed_date_details</code></strong><p>Dates that had no data or could not be fetched.</p></div>
<div class="option"><strong><code>daily_record_schema_version</code></strong><p>The version of the stable daily Health.md JSON schema used inside <code>records</code>.</p></div>
</div>

## Endpoint requirements

<div class="options">
<div class="option"><strong>Method</strong><p>Accept <code>POST</code>.</p></div>
<div class="option"><strong>Content type</strong><p>Accept <code>application/json</code>.</p></div>
<div class="option"><strong>Success</strong><p>Return any <code>2xx</code> status after the payload is safely accepted.</p></div>
<div class="option"><strong>Failures</strong><p>Return <code>4xx</code> or <code>5xx</code> for rejected requests. Health.md shows a short response preview when available.</p></div>
</div>

<p>For reliable ingestion, make your endpoint idempotent by date. A user may repeat the same export range after changing metrics or fixing a server error.</p>

## Tips

<ul>
<li>Test with one day before uploading a long backfill.</li>
<li>Disable Time-Series Data unless your pipeline needs individual timestamped samples.</li>
<li>Validate the token server-side before storing any payload.</li>
<li>Use <code>records[].date</code> as the primary per-day key.</li>
<li>Return a concise error body; Health.md only displays a short preview.</li>
</ul>

## Troubleshooting

| Problem | Usually means | Fix |
|---|---|---|
| API target is not ready | URL is empty or invalid | Reopen API Endpoint settings and enter a valid HTTP(S) URL. |
| HTTP 401 or 403 | Token missing or rejected | Update the token or server auth rules. |
| HTTP 404 | URL path is wrong | Check the route on your server. |
| HTTP 413 | Payload is too large | Export fewer days or disable Time-Series Data. |
| Some dates are missing | No enabled HealthKit data for those dates | Check <code>failed_date_details</code> and your metric selection. |

## Related

<div class="related">
  <a href="/docs/export/"><span>Source</span>Export — choose targets, date ranges, and run manual exports.</a>
  <a href="/docs/data-reference/"><span>Schema</span>Data Reference — every metric, key, unit, and export structure.</a>
  <a href="/docs/format/"><span>Output</span>Format Customization — JSON, CSV, Markdown, units, and fields.</a>
</div>
