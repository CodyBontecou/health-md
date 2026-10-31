# Cloud Providers

## Status

- **Docs status:** draft
- **Video priority:** medium
- **Primary screen:** Settings → Health sources
- **Source files:** `app/src/play/java/com/healthmd/presentation/oauth/OAuthCallbackActivity.kt`, `app/src/play/java/com/healthmd/rawexport/CloudRawHealthDataProvider.kt`, `app/src/play/java/com/healthmd/data/health/providers/cloud/` (adapters), `docs/health-provider-support.md`

## What it does

Health Connect is the default export source in both channels. The Google Play build enables WHOOP as its only direct third-party integration. Fitbit, Oura, Withings, Polar, Samsung, Huawei, and Garmin remain disabled in the catalog, OAuth configuration, normalized export registry, and raw export registry. Their adapter code and synthetic fixtures are retained for future work. After a browser OAuth sign-in, both compatibility exports and Raw API Snapshots can read from the connected provider—snapshots capture each provider's exact response bytes. The F-Droid build contains only Health Connect; cloud-provider catalog entries, adapters, OAuth callbacks, credentials, and token state are absent.

## Who it is for

- People whose main tracker syncs to a provider cloud rather than Health Connect
- Anyone taking provider-native raw snapshots for archival
- Not needed when your devices already write to Health Connect — that path stays local and account-free

## Where to find it

1. Open **Settings → Health sources**.
2. Pick a provider and sign in through the browser OAuth flow.
3. Return to the app — the callback confirms the connection and selects the provider.

## Prerequisites

- A WHOOP account and a Play build configured for WHOOP OAuth. See [provider prerequisites](../health-provider-support.md#direct-provider-prerequisites).
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
- Endpoint behavior and supported pagination are documented in the [raw-provider ledger](../export-contract/cloud-raw-provider-ledger.md); page caps, cycle detection, and server aggregation vary by endpoint.
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


Credential storage assigns a private connection ID to each new OAuth grant. Token rotation keeps that ID only when the exact pre-refresh credential still matches; a delayed refresh cannot overwrite a replacement account or reconnect a disconnected source. Legacy encrypted token records migrate once without changing the token fields understood by older decoders. Writes check synchronous persistence, and failed writes invalidate affected generations across store instances in the current process. A cloud page rechecks its accepted connection after transport and before/after raw observers; replacement or disconnect prevents later observation and return.

Repository capture views now bind selected cloud adapters to accepted grant IDs before source callbacks. Each view keeps independent adapters and clients; rotation within the same grant remains usable, while replacement, disconnect or a later repair cannot join an accepted operation. All connected retains the attempted source and reports permission failure instead of reading a replacement account. Availability and permissions remain live. Adapter copies preserve endpoint configuration, clocks and native-page interfaces. Health Connect keeps its existing on-device view and live permission checks.

These checks cover successful store reload, same-process mutation, refresh races, per-page authority and repository capture lifetimes. Standalone clients and raw snapshot entry points still need to opt into an operation binding explicitly. New default-schedule Morning occurrences persist accepted provider selection and opaque grant IDs in private settings snapshot v3. Folder, API and gateway capture restore that authority before health reads; token rotation under the same grant is permitted, while replacement, reconnect and a login after accepted unavailability cannot join the saved capture. Historical v1/v2 snapshot bytes remain readable without acquiring missing provider authority; an old Morning snapshot cannot start additional capture from today's account selection. Already-staged immutable artifact/body transfer retains its existing recovery path. A pending durable API operation requires its existing journal; missing spool state cannot trigger health recapture. Profile Morning occurrences now publish a private acceptance before permission checks or capture: frozen profile output choices are retained while each new occurrence accepts its current context and source. Pending retries restore that saved snapshot; advancing or explicitly starting another occurrence accepts a new source. Accepted Today Refresh scope and clock survive a later timezone edit. Profile definitions and portable setup exclude grant authority. Host tests cover competing DataStore admission, reopen, discard races, preference/profile/account changes and prepared-body retry without a new source read. Cross-process preferences mutation, OS process-loss or disk-failure recovery remain unqualified. The IDs stay in private credential/job storage and do not enter health exports, raw provider responses or diagnostics. These source-identity checks do not qualify cloud-provider sleep attribution semantics.
