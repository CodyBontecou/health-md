# Third-Party Provider Integrations

## Status

- **Docs status:** WHOOP staged rollout; other providers deferred
- **Primary screen:** Settings → Connected Apps
- **Rollout gate:** `CONNECTED_APPS_WHOOP_ENABLED=YES`
- **Source files:** `HealthMd/Shared/Integrations/*`, `HealthMd/iOS/Managers/ExternalIntegrationManager.swift`, `HealthMd/iOS/Views/ExternalIntegrationsView.swift`, `HealthMd/Shared/Managers/APIExportClient.swift`, `HealthMd/Shared/Sync/MacExportJobBuilder.swift`, `HealthMd/macOS/Managers/MacExportJobExecutor.swift`, `worker/oauth-broker/*`

## What it does

Health.md can connect a WHOOP account and export provider-native data as sidecar JSON next to the normal Apple Health export. The WHOOP rollout is independent: only WHOOP appears when `CONNECTED_APPS_WHOOP_ENABLED` is enabled. Fitbit, Oura, Withings, and Strava remain implemented prototypes and are not exposed by that flag.

WHOOP sidecars preserve WHOOP's response fields instead of silently merging them into the long-lived `healthmd.health_data` schema. The app requests these read-only scopes:

```text
offline read:recovery read:cycles read:sleep read:workout read:body_measurement
```

`offline` is required for refresh tokens. Health.md does not request `read:profile` because it does not need the member's name or email.

## OAuth and privacy model

WHOOP requires the application client secret to remain server-side. Health.md uses a minimal Cloudflare Worker OAuth broker to:

1. construct the authorization URL from the server-side WHOOP client ID;
2. exchange the authorization code using the server-side client secret;
3. rotate tokens during refresh.

The broker does not store provider tokens, WHOOP data, vault paths, or export files. Access and rotating refresh tokens are stored in iOS Keychain. WHOOP data requests go directly from the iPhone to WHOOP over HTTPS. The broker responses use `Cache-Control: no-store`.

WHOOP's documented redirect is registered exactly as:

```text
healthmd://oauth/callback
```

The app validates the callback scheme, host, path, and OAuth state before exchanging the code. WHOOP currently documents an exactly eight-character state value, so the WHOOP flow uses a random eight-character value. Other future providers are not forced to use that provider-specific constraint.

The broker has its own exact redirect allowlist and a mobile client gate. The gate limits casual abuse but is not treated as a durable secret because values in a shipped mobile app can be inspected.

## WHOOP API behavior

Health.md uses the current `/developer/v2` endpoints:

- `GET /cycle`
- `GET /recovery`
- `GET /activity/sleep`
- `GET /activity/workout`
- `GET /user/measurement/body`
- `DELETE /user/access` when disconnecting

Daily collection queries use a half-open `[start, end)` window. Health.md converts the selected calendar day's local boundaries to offset-aware RFC 3339 UTC timestamps. This preserves 23- and 25-hour days across daylight-saving changes.

Collection requests use WHOOP's maximum page size of 25. Pagination follows response `next_token` values via the request parameter `nextToken`, keeps the original day window fixed, rejects repeated cursors, and caps a single endpoint at 100 pages. Pagination cursors are redacted from exported endpoint URLs.

WHOOP's body measurement resource is a current profile singleton with no measurement timestamp. Health.md includes it only in the sidecar for the current calendar day, under `body_measurements_snapshot`. Historical and range exports do not repeat today's body profile for every requested day.

## Output shape

Local iPhone and Connected Mac file exports write WHOOP sidecars only at:

```text
Health/integrations/whoop/{yyyy-MM-dd}.json
```

Example:

```json
{
  "schema": "healthmd.external_provider_daily",
  "schema_version": 1,
  "provider": "whoop",
  "provider_display_name": "WHOOP",
  "date": "2026-07-13",
  "fetched_at": "2026-07-13T18:00:00Z",
  "payloads": [
    {
      "name": "recovery",
      "endpoint": "https://api.prod.whoop.com/developer/v2/recovery?start=2026-07-13T07:00:00Z&end=2026-07-14T07:00:00Z&limit=25",
      "status_code": 200,
      "fetched_at": "2026-07-13T18:00:00Z",
      "data": {
        "records": [
          {
            "cycle_id": 123456,
            "score_state": "SCORED",
            "score": { "recovery_score": 82 }
          }
        ]
      }
    }
  ],
  "warnings": []
}
```

Sidecar dates are validated before file writes. Authorization values, access/refresh tokens, client secrets, OAuth codes, and pagination cursors are redacted during encoding. Empty collection pages alone do not create a sidecar.

## Export destinations

When the WHOOP rollout flag is enabled and an account is connected:

- Local manual and scheduled exports write daily WHOOP sidecars.
- Connected Mac file-writing jobs transfer `externalDailyRecords`; the Mac writes the same `Health/integrations/whoop/{yyyy-MM-dd}.json` path.
- Legacy Mac raw requests that omit `raw_profile` can return sidecars in `raw_data.externalDailyRecords`.
- Strict CLI `--raw` requests use `raw_profile: canonical_source_records_v1`, return `healthmd.raw_result` v1, and currently contain canonical Apple Health daily records only; they do not fetch or embed provider sidecars.
- API Endpoint export uses the `healthmd.api_export` v2 envelope and includes sidecars under `external_records`.

When the flag is disabled, Connected Apps is hidden, provider fetches do not run, and API Endpoint export remains at envelope v1.

Provider records are intentionally supplemental. Health.md only fetches/writes a WHOOP sidecar for a day that proceeds through the canonical Apple Health daily export path. A WHOOP-only day does not make an otherwise empty Health.md export successful. This avoids creating a second definition of an exportable day during the first rollout and is covered by contract tests.

## Errors and retries

- Missing granted scopes skip only the affected endpoint and add an actionable 403 payload error.
- A 401 triggers one serialized token refresh and one retry. WHOOP's newly rotated access and refresh tokens replace the old pair atomically in Keychain.
- A refresh response without the mandatory new refresh token is rejected instead of saving an unusable credential pair.
- A 429 records a retry message using `X-RateLimit-Reset` when present and starts a client-wide cooldown, suppressing later WHOOP endpoint/day requests until the reset window instead of amplifying throttling.
- Malformed success responses and per-endpoint server/network failures are preserved as payload errors without discarding successful endpoint results.
- Provider response data is capped at 16 MiB per request and, separately, 16 MiB in aggregate for one provider/day fetch. This keeps paginated responses bounded; exceeding either limit produces a provider warning instead of retaining additional pages.
- Disconnect calls WHOOP's revoke endpoint before deleting local credentials. Revocation is attempted even during a data cooldown for privacy; a revoke 429 extends the same cooldown. If revocation fails, credentials remain available so the user can retry.

The Connected Apps screen explains missing permissions, revoked access, rate limiting, and days where WHOOP has not produced data or a score yet.

## Rollout configuration

The app callback scheme and broker placeholders are committed, but secrets are not. For a beta/release machine:

```bash
bash scripts/set-oauth-broker-config.sh \
  "https://<oauth-broker-host>" \
  "<BROKER_CLIENT_TOKEN>"

xcodebuild \
  -project HealthMd.xcodeproj \
  -scheme HealthMd \
  -destination 'generic/platform=iOS' \
  CONNECTED_APPS_WHOOP_ENABLED=YES \
  archive
```

The setup script stores the endpoint and mobile gate in macOS Keychain. The iOS build phase creates `OAuthBrokerConfig.plist` inside the built app only when WHOOP is enabled and fails closed if either value is missing.

The Worker requires these Cloudflare secrets:

```bash
cd worker/oauth-broker
wrangler secret put WHOOP_CLIENT_ID
wrangler secret put WHOOP_CLIENT_SECRET
wrangler secret put BROKER_CLIENT_TOKEN
```

Register `healthmd://oauth/callback` exactly in the WHOOP Developer Dashboard and set the Worker `ALLOWED_REDIRECT_URIS` to the same value.

## Physical-device beta checklist

1. Build with WHOOP enabled and install on a physical iPhone.
2. Connect WHOOP and approve all six requested scopes.
3. Force-quit/relaunch and confirm Keychain persistence.
4. Export one day and a multi-day range locally; confirm body measurements appear only for today.
5. Force an expired access token, confirm one refresh/retry, and relaunch again to verify the rotated refresh token persisted.
6. Repeat through a Connected Mac file-writing job, a legacy Mac raw request without `raw_profile`, scheduled export, and API Endpoint v2; sidecars are expected on each supported provider path.
7. Run strict CLI `--raw` separately and confirm the result contains canonical Apple Health data but no provider sidecar.
8. Inspect every sidecar path and payload for tokens or sensitive query values.
9. Disconnect, verify WHOOP access revocation, reconnect, and export again.

## Schema policy

This rollout does **not** bump `HealthMdExportSchema.version`: canonical Markdown, Bases, JSON, CSV, and data dictionary output are unchanged. The WHOOP sidecar stays at `healthmd.external_provider_daily` schema v1. API Endpoint's wrapper advances independently from v1 to v2 only when Connected Apps is enabled.

If provider fields are later merged into canonical daily exports or the data dictionary, follow `docs/features/export-schema.md` and bump the public export schema version.
