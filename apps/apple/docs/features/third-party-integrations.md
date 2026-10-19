# Third-Party Provider Integrations

## Status

- **Docs status:** WHOOP staged rollout; other providers deferred
- **Primary screen:** Settings → Connected Apps
- **Rollout gate:** `CONNECTED_APPS_WHOOP_ENABLED=YES`
- **Source files:** `HealthMd/Shared/Integrations/*`, `HealthMd/iOS/Managers/ExternalIntegrationManager.swift`, `HealthMd/iOS/Views/ExternalIntegrationsView.swift`, `HealthMd/Shared/Managers/APIExportClient.swift`, `HealthMd/Shared/Sync/MacExportJobBuilder.swift`, `HealthMd/macOS/Managers/MacExportJobExecutor.swift`, `worker/oauth-broker/*`

## What it does

Health.md can connect a WHOOP account and export two complementary fidelity layers: reviewed typed WHOOP data inside retained Apple `healthmd.health_data` v8 daily records, plus provider-native sidecar JSON. The WHOOP rollout is independent: only WHOOP appears when `CONNECTED_APPS_WHOOP_ENABLED` is enabled. Fitbit, Oura, Withings, and Strava remain implemented prototypes and are not exposed by that flag.

WHOOP sidecars preserve WHOOP's native response fields. The typed `providers.whoop` section exposes only reviewed fields and never overwrites Apple summaries. The app requests these read-only scopes:

```text
offline read:recovery read:cycles read:sleep read:workout read:body_measurement
```

`offline` is required for refresh tokens. Health.md does not request `read:profile` because it does not need the member's name or email.

## Choose WHOOP data to export

Open **Export → Health Metrics → WHOOP** to enable or disable **Cycles & Strain**, **Recovery**, **Sleep**, **Workouts**, and **Body Measurements**. **All WHOOP Data** changes all five. Each switch controls a whole native API resource, including its reviewed typed projections and provider-native sidecar pages; it is not a field-level redaction control. Apple Health selections remain independent.

Choices are saved per export profile and frozen for schedules, API uploads, Connected Mac/CLI generated files, previews, and durable recovery. Unselected endpoints are not contacted or reported as missing-permission failures. Turning all groups off skips WHOOP fetching and token refresh while leaving the connection intact. Old configurations default to all groups enabled. Selection changes do not remove existing exported files or revoke OAuth access; use **Disconnect** to revoke access.

Body data is still today-only, and WHOOP still supplements retained Apple Health days rather than creating WHOOP-only days. Selected recovery/sleep records retain relationship IDs even when related resources are not selected. Android's equivalent five-group settings/profile controls are planned separately; its existing Raw API Snapshot endpoint selection and daily compatibility profiles remain unchanged.

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

The app validates the callback scheme, host, path, and OAuth state before exchanging the code, and rejects duplicate or conflicting callback parameters. It uses S256 PKCE to bind the authorization code to a device-generated verifier; the broker still holds the client secret and forwards the verifier during code exchange. This matches Android's WHOOP authorization protection. Callback query values use form decoding (`+` for a space, `%2B` for a literal plus). WHOOP currently documents an exactly eight-character state value, so the WHOOP flow uses a random eight-character value. Other future providers are not forced to use that provider-specific constraint.

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

WHOOP's body measurement resource is a current profile singleton with no measurement timestamp. Health.md includes it only for the current calendar day, as native `body_measurements_snapshot` data in the sidecar and as a typed `current_profile_snapshot` under `providers.whoop.body`. Historical and range exports do not repeat today's body profile for every requested day.

### Public API coverage audit (2026-10-06)

The [current WHOOP OpenAPI specification](https://api.prod.whoop.com/developer/doc/openapi.json) documents five health-resource groups available through ordinary user OAuth: cycles, recovery, sleep, workouts, and body measurements. Health.md connects to all five, subject to selection, granted scopes, retained Apple days, and capture limits. Fetch-by-ID and cycle-to-sleep/recovery lookup routes are alternate access to those resources, not additional health categories. Connecting every category does not mean the typed export projects every native field.

The audit identified two field-level gaps, both addressed in current source:

- **Cycle steps:** WHOOP [added `Cycle.step_count` on 2026-09-23](https://developer.whoop.com/docs/api-changelog#2026-09-23), using the existing `read:cycles` scope without new consent. Apple daily v10/WHOOP provider v2 retains the optional typed count as well as the selected native response. WHOOP's [cycle documentation](https://developer.whoop.com/docs/developing/user-data/cycle#step-count) explicitly defines this as a physiological-cycle total, not a midnight-to-midnight daily total; do not substitute it for Apple/Health Connect daily steps. Missing/null means unavailable, while zero is meaningful. Historical daily v8/WHOOP v1 remains unchanged.

**Workout heart-rate zones are corrected:** the Apple normalizer reads the documented `score.zone_durations` from the [workout API](https://developer.whoop.com/docs/developing/user-data/workout). It accepts legacy `score.zone_duration` only when the canonical key is absent; canonical null, empty, malformed, or partial values never resurrect or blend legacy values. Explicit zero and integer millisecond precision survive normalization and JSON/CSV output. Native sidecars remain unchanged. This uses the existing typed zone fields without changing daily v8 or WHOOP v1 grammar. Verification uses synthetic API responses, not a member account.

The other ordinary user read resource is the [basic profile](https://developer.whoop.com/docs/developing/user-data/user#basic-profile): name, email, and user ID under `read:profile`. Health.md intentionally excludes it; it adds identity information, not health measurements. The current public user API does not document separate endpoints for continuous raw heart-rate/sensor streams, journal entries, Stress Monitor, Healthspan/WHOOP Age, ECG, or Strength Trainer exercise/set/repetition detail. Workout summaries, including Strength Trainer activities, belong to the existing workout resource; their availability is noted in the [API changelog](https://developer.whoop.com/docs/api-changelog#2024-05-01).

WHOOP also publishes a distinct [Healthcare Partner API](https://developer.whoop.com/docs/partner/overview) for lab requisitions, service requests, diagnostic-result submission, and clinical-report review. It is restricted to WHOOP-approved healthcare partners with separate server-to-server credentials; it cannot be enabled by adding a scope to the existing member connection. Standard [webhooks](https://developer.whoop.com/docs/developing/webhooks/) could improve update/deletion freshness for supported resources, but do not expose new data categories. Neither partner workflows nor webhook ingestion are implemented by this integration.

## Output shapes

### Provider-native sidecar

Local iPhone and Connected Mac file exports retain WHOOP's native response layer at:

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

### Typed daily section

A retained Apple daily v10 record may also contain (new captures use WHOOP v2; historical v1 remains readable):

```json
{
  "schema": "healthmd.health_data",
  "schema_version": 10,
  "providers": {
    "whoop": {
      "schema": "healthmd.provider.whoop_daily",
      "schema_version": 2,
      "capture_status": "complete",
      "fetched_at": "2026-07-13T18:00:00Z",
      "resources": [
        { "resource": "recovery", "status": "success", "record_count": 1 }
      ],
      "cycles": [],
      "recoveries": [
        {
          "cycle_id": "123456",
          "recovery_score_percent": 82,
          "hrv_rmssd_ms": 54.3
        }
      ],
      "sleep": [],
      "workouts": [],
      "warnings": []
    }
  }
}
```

WHOOP public `Cycle.step_count` is retained as optional `cycles[].step_count` in provider v2. These are physiological-cycle counts, **not calendar-day steps**. Zero is meaningful; missing/null or invalid counts remain unavailable. Counts stay attached to cycle IDs and timestamps, including in-progress cycles. Scalar `whoop_cycle_step_count` appears only for a single cycle; repeated cycles remain structured. No summing, primary-step replacement, or roll-up is permitted. Existing `read:cycles` suffices. The **Cycles & Strain** resource switch controls these counts independently from Apple Health steps.

The complete nested schema preserves string IDs, event relationships, exact integer millisecond durations, the signed recent-nap adjustment, `sport_name`, explicit missingness, and deterministic ordering. `fetched_at` is capture metadata, never a measurement timestamp. Partial captures retain successful resources with bounded safe errors and no URLs, headers, cursors, credentials, account identity, or raw response bodies.

JSON keeps the nested model. Markdown renders WHOOP tables. Bases/frontmatter and CSV emit `whoop_*` scalars only when exactly one relevant record supplies them; repeated records remain structured Markdown/JSON/CSV rows. WHOOP fields have no period roll-ups and do not participate in Individual Entry Tracking. See [Export schema contract](./export-schema.md) and `packages/contracts/provider-sections/v2/contract.md` in the repository; the v1 proposal/fixture remains frozen for historical reads.

## Export destinations

When the WHOOP rollout flag is enabled and an account is connected:

- Local manual and scheduled exports attach typed WHOOP data to retained daily files and write daily WHOOP sidecars.
- Connected Mac file-writing, streaming, corpus, resume, and recovery paths carry the same typed daily records and `externalDailyRecords`; the Mac writes the daily files and the same `Health/integrations/whoop/{yyyy-MM-dd}.json` sidecar path.
- Legacy Mac raw requests that omit `raw_profile` can return sidecars in `raw_data.externalDailyRecords`.
- Strict CLI `--raw` requests use `raw_profile: canonical_source_records_v1`, return `healthmd.raw_result` v1, and currently contain canonical Apple Health daily records only; they do not fetch or embed provider sidecars.
- API Endpoint export uses the `healthmd.api_export` v2 envelope, with typed WHOOP sections inside `records` and provider-native sidecars under `external_records`.

When the flag is disabled, Connected Apps is hidden, provider fetches do not run, and API Endpoint export remains at envelope v1.

Provider records are intentionally supplemental. Health.md only fetches and attaches WHOOP data for a day that proceeds through the canonical Apple Health daily export path. A WHOOP-only day does not make an otherwise empty Health.md export successful. Successful-empty WHOOP capture is still represented as a complete typed section on a retained Apple day, while an empty native collection alone does not create a sidecar.

## Errors and retries

- Missing granted scopes skip only the affected endpoint and add an actionable 403 payload error.
- A 401 triggers one serialized token refresh and one retry. WHOOP's newly rotated access and refresh tokens replace the old pair atomically in Keychain.
- A refresh response without the mandatory new refresh token is rejected instead of saving an unusable credential pair.
- A 429 records a retry message using `X-RateLimit-Reset` when present and starts a client-wide cooldown, suppressing later WHOOP endpoint/day requests until the reset window instead of amplifying throttling.
- Malformed success responses and per-endpoint server/network failures are preserved as payload errors without discarding successful endpoint results.
- Provider response data is capped at 16 MiB per request and, separately, 16 MiB in aggregate for one provider/day fetch. This keeps paginated responses bounded; exceeding either limit produces a provider warning instead of retaining additional pages.
- Disconnect calls WHOOP's revoke endpoint before deleting local credentials. Revocation is attempted even during a data cooldown for privacy; a revoke 429 extends the same cooldown. If revocation fails, credentials remain available so the user can retry.

The Connected Apps screen explains missing permissions, revoked access, rate limiting, and days where WHOOP has not produced data or a score yet. Connection/disconnection feedback uses the same bottom-pinned activity/toast component as exports, inside the sheet so it remains visible while scrolling. Progress remains visible until the operation finishes. Success and cancellation notices dismiss after eight seconds; errors remain until dismissed or retried. OAuth callback errors show stable, actionable messages rather than raw provider descriptions or hints. A connection is reported successful only after credentials and account metadata have been saved.

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
6. Repeat through Connected Mac file-writing, streaming/corpus recovery, a legacy Mac raw request without `raw_profile`, scheduled export, and API Endpoint v2; typed daily data and sidecars are expected on each supported provider path.
7. Run strict CLI `--raw` separately and confirm the result contains canonical Apple Health data but no typed or native provider data.
8. Inspect every typed daily section and sidecar for tokens, URLs, cursors, account identity, or raw error bodies.
9. Disconnect, verify WHOOP access revocation, reconnect, and export again.

## Schema policy

Typed provider sections originally advanced Apple daily v7 to v8/WHOOP v1. Current source writers advance to Apple daily v10/WHOOP v2 for physiological-cycle steps; the primary metric catalog is unchanged and unified daily v9 remains reserved. The v8 signature and WHOOP-v1 schema/fixture remain frozen. Compatible consumers must be released before enabling these writer defaults against them; no deployment or live-provider qualification is implied. The provider-native sidecar remains `healthmd.external_provider_daily` v1, and API Endpoint remains independently versioned at envelope v2 when Connected Apps is enabled. Android frozen v4 and analytical v5 are unchanged.
