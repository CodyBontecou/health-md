# Cloud Providers

## Status

- **Docs status:** draft
- **Video priority:** medium
- **Primary screen:** Settings → Health sources
- **Source files:** `app/src/play/java/com/healthmd/presentation/oauth/OAuthCallbackActivity.kt`, `app/src/play/java/com/healthmd/rawexport/CloudRawHealthDataProvider.kt`, `app/src/play/java/com/healthmd/data/health/providers/cloud/` (adapters), `docs/health-provider-support.md`

## What it does

Health Connect is the default export source in both channels. The Google Play build can also connect Fitbit, Oura, WHOOP, and Withings accounts through their public cloud APIs. After a browser OAuth sign-in, both compatibility exports and Raw API Snapshots can read from the connected provider—snapshots capture each provider's exact response bytes. The F-Droid build contains only Health Connect; cloud-provider catalog entries, adapters, OAuth callbacks, credentials, and token state are absent.

## Who it is for

- People whose main tracker syncs to a provider cloud rather than Health Connect
- Anyone taking provider-native raw snapshots for archival
- Not needed when your devices already write to Health Connect — that path stays local and account-free

## Where to find it

1. Open **Settings → Health sources**.
2. Pick a provider and sign in through the browser OAuth flow.
3. Return to the app — the callback confirms the connection and selects the provider.

## Prerequisites

- A Fitbit, Oura, WHOOP, or Withings account
- Network access for cloud reads
- Android 9 / API 28+

## Setup

1. Open **Settings → Health sources** and choose the provider.
2. Complete the browser sign-in (PKCE OAuth; the app never holds client secrets).
3. Select the provider as your export source, or use "All connected" for multi-provider merges in compatibility exports.

## WHOOP physiological-cycle steps

Apple daily v10/WHOOP provider v2 now retains optional `Cycle.step_count` with exact zero and cycle provenance. Matching typed Android projection is **planned** in a separately reviewed provider profile, together with the independent cycles resource control described below; frozen v4/v5 output is unchanged. Existing selected WHOOP raw snapshots preserve upstream `step_count` without claiming it is a Health Connect civil-day step total. Missing/null means unavailable, and multiple physiological cycles must not be summed or copied into primary daily steps. Existing `read:cycles` covers this field. F-Droid remains Health Connect-only.

## WHOOP resource-selection parity

The iPhone Health Metrics view now has five independent WHOOP API-resource switches with stable IDs `cycles`, `recovery`, `sleep`, `workouts`, and `body`. Matching Android Play controls are **planned**, not available in this screen yet. The concrete target is to persist the same all-on default and explicit all-off/partial choices in export profiles and frozen jobs, expose them in Health Metrics, and apply them before WHOOP compatibility reads and Raw API Snapshot endpoint planning. F-Droid remains cloud-provider-free. This setting must not relabel WHOOP RMSSD as HealthKit SDNN or change the frozen v4/v5 export grammar.

Today, Raw API Snapshots already select WHOOP endpoints through their metric-to-endpoint plan (`WhoopCloudDataProvider.streamNativePages`); that is not equivalent to a separately saved WHOOP resource-selection control. Raw snapshots' explicitly unbounded body singleton and compatibility exports' today-only body policy remain distinct.

## Example output

Compatibility exports map provider records into the same `HealthData` shape as Health Connect. Raw snapshots instead emit `provider_payload` records: the exact successful API page, with pagination and server-side aggregation disclosed in the manifest.

## Tips

- Tokens are stored encrypted (Android Keystore-backed) and excluded from backup, logs, and export history.
- Endpoint behavior differs: Fitbit/Withings plans do not paginate; Oura/WHOOP next-tokens are capped and cycle-detected; some summary endpoints declare `serverAggregation=true`.
- A provider that is not supported shows up as **unsupported** in raw snapshots — it is never silently filled in with Health Connect data.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Sign-in failed | Callback URI missing or OAuth error | Retry sign-in from Health sources |
| Provider reads empty | Token expired mid-flow or account has no data | Reconnect and check the provider's app |
| Provider listed unsupported | Samsung/Huawei/Garmin/Polar need vendor SDK/partner approval | Use Health Connect sharing where available |

## Video outline

- **Suggested title:** Export Fitbit, Oura, WHOOP, and Withings Without Health Connect
- **Hook:** "Your tracker's cloud, your files."
- **Demo flow:** connect WHOOP → run a compatibility export → run a raw snapshot.
- **Key screenshot/recording moments:** OAuth browser round-trip, provider catalog, raw `provider_payload`.
- **CTA / next video:** Raw API Snapshots.

## Implementation notes

`OAuthCallbackActivity` receives the redirect, `OAuthAuthorizationManager` (PKCE, token exchange/refresh) completes it, and `EncryptedOAuthTokenStore` persists tokens. `CloudRawHealthDataProvider` wraps `CloudNativeRawPageProvider` adapters and requires declared `NATIVE_API_PAYLOAD` fidelity; per-type errors say e.g. "The selected category has no provider-native endpoint in …" or "… is not connected for native API reads." `HealthDataMerger` supports the internal `all_connected` id, preferring one source per daily aggregate to avoid double-counting. Samsung/Huawei/Garmin/Polar direct adapters are explicit unavailable scaffolds. Full catalog and verification notes: [Health provider support](../health-provider-support.md).
