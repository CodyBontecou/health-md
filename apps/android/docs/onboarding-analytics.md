# First-party onboarding and pricing analytics

Health.md uses a small first-party Android client to understand whether onboarding steps and the onboarding paywall are usable. It does not use Firebase Analytics, Google Analytics, AppsFlyer, or another third-party analytics SDK. This client is independent from the Google Play campaign-attribution subsystem and does not read or alter campaign attribution state.

## Event and property allowlist

The client can send only these events:

- `pricing_onboarding_started`
- `pricing_onboarding_step_viewed`
- `pricing_onboarding_health_skipped`
- `pricing_onboarding_folder_selected`
- `pricing_onboarding_folder_skipped`
- `pricing_onboarding_continue_free_tapped`
- `pricing_onboarding_purchase_tapped`
- `pricing_onboarding_completed`

Android step values are limited to `welcome`, `health_access`, `folder_setup`, `unlock`, and `ready`. Every event contains app version, build number, `platform=android`, the coarse onboarding step, and `paywallContext=onboarding`. When the existing local freemium counters can be read safely, the event also includes bounded `freeExportsUsed` and `freeExportsRemaining` integers. The purchase-tap event can additionally contain the allowlisted product ID `health_md_premium_lifetime`.

The welcome screen discloses this limited first-party collection before setup begins. The payload never contains health records, selected health types, permission status or permission details, a folder URI/name/path, Android ID, Advertising ID, hardware identifiers, account or user text, prices, timestamps, campaign/referrer values, exports, or raw errors. Folder selection records only that a selection milestone occurred. Health access records only a coarse page view or an explicit skip.

## Delivery and local state

The dedicated `onboarding_analytics` DataStore contains a random app-install UUID, stable random event UUIDs, a milestone-deduplication set, and a maximum of 50 pending allowlisted events. The oldest pending event is discarded if the cap is reached. This DataStore is excluded from Android cloud backup and device transfer.

A network-constrained unique WorkManager job posts batches to:

```http
POST https://health-md-pricing-analytics.costream.workers.dev/v1/events
Content-Type: application/json
Accept: application/json
```

```json
{
  "installId": "11111111-1111-4111-8111-111111111111",
  "events": [
    {
      "eventId": "22222222-2222-4222-8222-222222222222",
      "eventName": "pricing_onboarding_step_viewed",
      "properties": {
        "appVersion": "1.5.4",
        "buildNumber": "25",
        "platform": "android",
        "onboardingStep": "unlock",
        "paywallContext": "onboarding",
        "freeExportsUsed": 2,
        "freeExportsRemaining": 8
      }
    }
  ]
}
```

HTTP 408, 425, 429, 5xx responses, I/O failures, and timeouts retry with WorkManager exponential backoff. Other non-2xx responses permanently discard the rejected batch. Event UUIDs remain unchanged across retries. Delivery and persistence run off the UI path, and analytics failure never blocks onboarding.

Validated D1 event rows are retained for no more than 13 months and removed by the Worker’s daily cleanup. Analytics rows do not store raw IP addresses, full User-Agents, request URLs, headers, or unvalidated request bodies; Cloudflare still processes ordinary network connection information under its own terms.

Maintainers can override the HTTPS base or full `/v1/events` URL with the `ONBOARDING_ANALYTICS_ENDPOINT_URL` Gradle property or environment variable. Debug builds additionally permit HTTP only on localhost. Redirects, URL credentials, query parameters, and fragments are rejected. The client strips the generic OkHttp User-Agent and sends no authentication, cookies, device headers, or campaign headers.

## Google Play Data Safety

Review Google Play's current definitions and obtain policy/legal review before release. Under the current project classification:

- random app-generated install/event UUIDs are **Device or other IDs**;
- coarse onboarding milestones are **App activity → App interactions**;
- onboarding collection is for **Analytics**, is collected by the developer, is not shared with third parties, is not ephemeral, and is not user-disableable;
- transport is encrypted in release builds; and
- Health Connect data remains a separate disclosure because no health data enters these analytics events.

Keep the hosted privacy policy and Play Console answers synchronized with this implementation before publishing the Android update.
