# Cloud Providers

## Status

- **Docs status:** draft
- **Video priority:** medium
- **Primary screen:** Settings → Health sources
- **Source files:** `app/src/main/java/com/healthmd/presentation/oauth/OAuthCallbackActivity.kt`, `app/src/main/java/com/healthmd/rawexport/CloudRawHealthDataProvider.kt`, `app/src/main/java/com/healthmd/data/health/providers/cloud/` (adapters), `docs/health-provider-support.md`

## What it does

Health Connect is the default export source, but Health.md can also connect Fitbit, Oura, WHOOP, and Withings accounts through their public cloud APIs. After a browser OAuth sign-in, both compatibility exports and Raw API Snapshots can read from the connected provider — snapshots capture each provider's exact response bytes.

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
