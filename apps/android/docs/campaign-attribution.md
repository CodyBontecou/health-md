# First-party Android campaign attribution

Health.md measures campaign installs without AppsFlyer, Firebase Analytics, Google Analytics, advertising identifiers, Android identifiers, or another analytics/attribution SDK. The only Play-specific dependency is Google's official Install Referrer library (`com.android.installreferrer:installreferrer:2.2`).

This repository implements the Android client. The companion Cloudflare Worker is maintained separately in the Health.md website repository under `cloudflare/attribution-worker` and is deployed at `https://healthmd.app/v1/installs`. It uses the existing `healthmd-campaigns` D1 database. Android builds still require explicit endpoint/token configuration; without it, a valid sanitized event remains pending on-device and startup continues normally.

## Data flow

1. A visitor opens a first-party short link such as `https://healthmd.app/v/yt-csv-001`.
2. The existing Cloudflare redirect Worker records the campaign click in D1 and sends Android visitors to Google Play with an encoded `referrer` parameter.
3. After installation, Health.md reads Google Play Install Referrer off the main thread. Sideloaded builds commonly return no referrer.
4. The app accepts exactly `utm_source`, `utm_medium`, `utm_campaign`, and `utm_content`. Unknown, missing, duplicate, oversized, malformed, mismatched, or non-campaign values are terminal and create no event.
5. A valid campaign is converted to a sanitized event with random Health.md-generated install and event UUIDs. The raw referrer is discarded and never persisted, logged, or uploaded.
6. A unique WorkManager job with a network constraint sends the persisted event. Retryable failures retain the same event UUID. A successful 2xx response marks it delivered.
7. The backend can aggregate attributed installs by `campaignToken` and join that value to the redirect Worker's D1 `campaign_token`.

The app remains functional offline. Referrer discovery and delivery do not block startup, onboarding, billing, exports, or health-data processing.

## Accepted referrer contract

Decoded example:

```text
utm_source=yt&utm_medium=campaign_shortlink&utm_campaign=yt_csv_001&utm_content=csv
```

Validation:

- campaign token: `^[a-z]{1,4}_[a-z0-9]+_[0-9]{3}$`
- source: `^[a-z]{1,4}$`
- medium: exactly `campaign_shortlink`
- content angle: `^[a-z0-9]+$`
- token segment 1 must equal `utm_source`
- token segment 2 must equal `utm_content`
- all four fields must occur exactly once; no extra fields are accepted
- the complete referrer and each accepted value have conservative length bounds

Empty and known organic values are terminal and create no campaign event. `SERVICE_UNAVAILABLE` and service disconnection receive three short in-process attempts and remain discoverable on a later launch if all attempts fail. Unsupported Play services and developer/configuration failures are terminal and nonfatal.

## Gradle configuration

Both settings default to an empty string. Configure them as Gradle properties:

```bash
./gradlew assembleDebug \
  -PCAMPAIGN_ATTRIBUTION_ENDPOINT_URL=https://healthmd.app \
  -PCAMPAIGN_ATTRIBUTION_INGEST_TOKEN=replace-with-throttling-token
```

or environment variables:

```bash
CAMPAIGN_ATTRIBUTION_ENDPOINT_URL=https://healthmd.app \
CAMPAIGN_ATTRIBUTION_INGEST_TOKEN=replace-with-throttling-token \
./gradlew assembleDebug
```

`CAMPAIGN_ATTRIBUTION_ENDPOINT_URL` is a base URL. The client appends `/v1/installs`. Release builds accept HTTPS only. Debug builds additionally accept HTTP only for `localhost`, `127.0.0.1`, or `::1`. URLs containing credentials, query parameters, or fragments are rejected.

`CAMPAIGN_ATTRIBUTION_INGEST_TOKEN` is optional at the protocol level. Production fails closed unless the matching Worker secret is configured. A token embedded in an APK can be extracted, so it is only an abuse-throttling input, not a secret or an authentication boundary. The client accepts 1–512 ASCII letters, digits, `.`, `_`, `~`, `+`, `/`, `=`, or `-`; an invalid configured token leaves the event pending. During rotation, the Worker can accept both `CAMPAIGN_ATTRIBUTION_INGEST_TOKEN` and `CAMPAIGN_ATTRIBUTION_INGEST_TOKEN_PREVIOUS`. HTTP 401/403 leaves the Android event pending so a later app build with updated configuration can deliver it. Do not put signing credentials or privileged Cloudflare API tokens in this value.

On the configured maintainer machine, the production values are stored outside source control with mode `600`:

```bash
source "$HOME/.config/healthmd/campaign-attribution.env"
./gradlew assembleDebug
```

Release automation must inject the same two environment variables from its own secret store.

## Deployed Cloudflare ingestion contract

The companion service exposes:

```http
POST <CAMPAIGN_ATTRIBUTION_ENDPOINT_URL>/v1/installs
Content-Type: application/json
Accept: application/json
Authorization: Bearer <optional-abuse-throttling-token>
```

```json
{
  "schemaVersion": 1,
  "eventId": "22222222-2222-4222-8222-222222222222",
  "installId": "11111111-1111-4111-8111-111111111111",
  "eventName": "campaign_install_attributed",
  "occurredAt": "2026-07-14T12:00:00Z",
  "platform": "android",
  "appVersion": "1.5.2",
  "buildNumber": "20",
  "campaignToken": "yt_csv_001",
  "source": "yt",
  "medium": "campaign_shortlink",
  "contentAngle": "csv",
  "referrerClickTimestampSeconds": 1234567890,
  "installBeginTimestampSeconds": 1234567900
}
```

The two Play timestamps are optional and are omitted when unavailable.

### Implemented backend behavior

- Allow only `POST` over HTTPS and apply a 4 KiB request-body limit.
- Validate the exact schema and reject unknown fields.
- Reapply the Android campaign validation rules server-side.
- Make `eventId` unique and use it as the idempotency key.
- Return a 2xx response for a previously accepted duplicate `eventId`; this lets a client recover if the original 2xx response was lost.
- Store only the allowlisted JSON fields needed for aggregate attribution.
- Do not add IP address, request User-Agent, Cloudflare request identifiers, cookies, fingerprinting inputs, or inferred device attributes to the attribution row. Configure request/log retention so those values are not retained in application logs.
- Never accept health data, export data, account data, file/folder paths, Android ID, Advertising ID, or a raw referrer.
- Restrict operational access and rotate the optional ingest token when abused.
- Apply a global D1 fixed-window limit of 300 authorized ingest attempts per minute without storing client identifiers.
- Delete ingest-rate windows after 24 hours and campaign click/install rows after 13 months using a daily Worker cron.
- Join installs to redirect clicks only in aggregate by the exact `campaignToken`/D1 `campaign_token` value through `campaign_attribution_summary`.

Client response handling:

| Result | Client behavior |
|---|---|
| Any 2xx | Mark delivered |
| 400, 409, 413, or another non-retryable response | Mark terminal rejection |
| 401 or 403 | Keep pending as an authorization/configuration failure |
| 408, 429, 5xx, or network failure | Retry with WorkManager exponential backoff |
| Endpoint missing or locally rejected | Keep event pending; do not fail startup |

Because the client treats HTTP 409 as permanent and marks delivery successful only after 2xx, the backend should return 2xx for an already-ingested `eventId` rather than 409.

## Data minimization and local state

The dedicated `campaign_attribution` DataStore contains:

- one random app-install UUID generated by Health.md;
- processing/delivery state;
- at most one sanitized campaign event with a stable random event UUID; and
- the delivery-success flag.

The store is excluded from Android cloud backup and device transfer. The random install UUID is a persistent pseudonymous app-install identifier, not an anonymous value or a device identifier. It does not use or derive values from Advertising ID, Android ID, hardware identifiers, account identifiers, health records, export settings, or paths.

## Google Play Console Data Safety review

The hosted policy and Console answers were updated on July 15, 2026 and submitted for review. Recheck the current Google definitions and obtain policy/legal review when the implementation or taxonomy changes.

- [x] Update the hosted privacy policy to describe first-party redirect click logging and Android install attribution.
- [x] Remove or qualify absolute “no analytics,” “no server,” “nothing transmitted,” and “all data stays on device” claims. State “no third-party analytics or attribution SDKs” and distinguish health data from limited campaign metadata.
- [x] In Data Safety, disclose that first-party campaign attribution can transmit data off-device when the app resulted from a campaign install.
- [x] Classify the random install/event UUIDs as **Device or other IDs** under the current Play taxonomy, while the policy clarifies that they are app-generated rather than hardware or advertising identifiers.
- [x] Classify campaign event delivery as **App activity / App interactions** with **Analytics** and **Advertising or marketing** purposes.
- [x] Declare both data types collected by the developer, not shared with third parties, not processed ephemerally, and required because affected users cannot disable collection.
- [x] Confirm attribution transport is encrypted in transit in release builds (HTTPS only).
- [x] Document that collection is conditional on a valid campaign install and that no deletion-request mechanism exists because there is no account-linked lookup key.
- [ ] Confirm the documented 13-month campaign retention and 24-hour aggregate rate-window retention meet policy/legal requirements; access-control and incident-response procedures remain operational tasks.
- [x] Verify that Health Connect/health-data disclosures remain separate: health records are never included in attribution.
- [x] Re-review screenshots, onboarding copy, store listing, in-app privacy rationale, support pages, and release notes for consistency.
- [x] Save dated evidence of the final Console answers and privacy-policy revision outside this repository.

## Manual verification notes

Install Referrer normally works only for installs delivered by Google Play. A sideloaded Debug APK may resolve as organic, unsupported, or unavailable. Version 1.5.2 (versionCode 20) was published to Internal Testing on July 15, 2026. Final end-to-end attribution verification still requires a fresh Play install from a campaign link on a Play-enabled test device, followed by a `campaign_attribution_summary` query for `yt_csv_001`. The Worker contract, authorization, idempotency, D1 persistence, and aggregate join were verified against production with temporary QA rows that were deleted afterward. Do not print the raw referrer while testing.
