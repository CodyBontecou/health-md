# Health provider support

Health.md uses Health Connect as the default Android export path because it keeps reads local to the device and matches the app's no-account, no-cloud workflow.

The Play build has a provider catalog and export-provider abstraction so additional ecosystems can be surfaced in the UI and wired into the same `HealthData` export pipeline without changing exporters. The F-Droid catalog intentionally contains only Health Connect; direct cloud-provider definitions, package queries, OAuth callback components, token stores, credentials, and adapters are not part of that variant.

## Supported catalog

| Provider | Current path | Channel / direct-import status |
|---|---|---|
| Health Connect | Android system/on-device API | Export-ready in Play and F-Droid |
| Samsung Health | Prefer Samsung Health → Health Connect sharing | Play catalog guidance only; direct SDK requires vendor approval/configuration |
| Huawei Health | HMS Health Kit / Huawei ecosystem | Play catalog guidance only; requires HMS setup |
| Fitbit | Fitbit Web API | Play only; OAuth adapter uses public PKCE with `FITBIT_CLIENT_ID` or `FITBIT_TOKEN_BROKER_URL` |
| Garmin Connect | Garmin Health API | Play catalog only; partner approval/backend sync required |
| Withings | Withings public API | Play only; OAuth adapter uses public PKCE with `WITHINGS_CLIENT_ID` or `WITHINGS_TOKEN_BROKER_URL` |
| Oura | Oura Cloud API | Play only; OAuth adapter uses public PKCE with `OURA_CLIENT_ID` or `OURA_TOKEN_BROKER_URL` |
| Polar Flow | Polar AccessLink | Play catalog only; AccessLink transaction cache still required |
| WHOOP | WHOOP API | Play only; OAuth adapter uses public PKCE with `WHOOP_CLIENT_ID` or `WHOOP_TOKEN_BROKER_URL` |

Google Fit is intentionally excluded because Google Fit APIs are legacy/deprecated and Health Connect is the preferred Android path.

## Implementation notes

- `HealthDataProvider` is the normalized export contract.
- `HealthConnectDataProvider` wraps the existing `HealthConnectManager`.
- `HealthProviderRegistry` keeps Health Connect as the primary export provider by default and can route exports to selected direct providers.
- `HealthProviderCatalog` powers Settings → Health sources. `PlayHealthProviderDefinitions` and the Play manifest own direct definitions and vendor package queries; F-Droid constructs the catalog from the shared Health Connect definition only.
- `OAuthAuthorizationManager` implements browser OAuth, PKCE, token exchange/refresh, and encrypted token storage via `EncryptedOAuthTokenStore`.
- OAuth client secrets are intentionally not exposed through `BuildConfig`; mobile builds use public PKCE client IDs or a provider-specific token broker URL.
- Compatibility exports still let `FitbitCloudDataProvider`, `WithingsCloudDataProvider`, `OuraCloudDataProvider`, and `WhoopCloudDataProvider` map cloud responses into normalized `HealthData`.
- Raw API Snapshots use separate provider-native page methods on those same adapters and the same protected OAuth client. Each exact successful page is exported as `provider_payload`; normalized `HealthData` is never used as raw.
- Fitbit/Withings endpoint plans explicitly do not paginate; Oura/WHOOP next tokens are capped and cycle-detected, and WHOOP recovery fan-out IDs come from captured cycle pages. Summary endpoints declare `serverAggregation=true`.
- `PolarCloudDataProvider` is raw `unsupported` until an AccessLink transaction cache/native adapter exists. Direct Samsung, Huawei, and Garmin are also raw `unsupported`; no provider falls back to Health Connect.
- Samsung, Huawei, and Garmin direct providers are explicit unavailable adapters until their SDK/HMS/partner prerequisites are satisfied.
- Health Connect metadata now annotates known provider package names with `data_origin_provider` when exported granular/workout metadata includes a data origin.
- Exporters continue consuming `HealthData`, so additional providers map records into the existing domain model rather than changing Markdown/JSON/CSV exporters.
- `HealthDataMerger` provides conservative multi-provider merge support for the internal `all_connected` provider id, preferring one source per daily aggregate to avoid double-counting.

## Verification without every device/account

The in-app diagnostics and JVM test harness verify the pieces that do not require vendor accounts:

- `OAuthAuthorizationManagerTest` uses MockWebServer to validate PKCE authorization URL generation, callback token exchange, Basic/request-body client auth, refresh-token handling, and unknown-state rejection.
- `CloudProviderFixtureMappingTest` serves fixture API responses for Fitbit, Withings, Oura, and WHOOP through MockWebServer and asserts they map into `HealthData` correctly.
- The same fixture suite includes a partial-failure check so one cloud endpoint error does not wipe otherwise readable sections for the day.
- `HealthProviderCatalogTest` guards the provider catalog and keeps Google Fit package/scopes out of the supported-provider surface.
- Settings → Health diagnostics can share a redacted provider report for beta testers without exposing health measurements or token values.
- `OAuthCredentialSafetyTest` guards against adding provider client-secret fields to the Android APK.
- `HealthProviderDiagnosticsReportTest` guards the redacted share-text format.

Run Play provider tests with:

```bash
./gradlew :app:testPlayDebugUnitTest --tests com.healthmd.data.health.oauth.OAuthAuthorizationManagerTest --tests com.healthmd.data.health.oauth.OAuthCredentialSafetyTest --tests com.healthmd.data.health.HealthProviderDiagnosticsReportTest --tests com.healthmd.data.health.providers.cloud.CloudProviderFixtureMappingTest --tests com.healthmd.data.health.providers.HealthProviderCatalogTest
```

Run the F-Droid catalog/absence contract with `./gradlew :app:testFdroidDebugUnitTest --tests com.healthmd.distribution.FdroidDistributionPolicyTest`.

## Direct-provider prerequisites

Before enabling live cloud/direct reads in the Play build:

1. Register OAuth public clients or complete SDK/partner setup.
2. Add the relevant client-id Gradle properties (`OURA_CLIENT_ID`, `WITHINGS_CLIENT_ID`, etc.) and matching redirect URI: `healthmd://oauth2redirect`.
3. Do not add provider client secrets to Gradle properties or `BuildConfig`. If a provider requires a confidential client, configure a provider-specific token broker URL (`OURA_TOKEN_BROKER_URL`, `WITHINGS_TOKEN_BROKER_URL`, etc.) that performs token exchange/refresh server-side and returns the provider token JSON shape to the app.
4. Add provider-specific fixture tests for API response mapping.
5. Confirm privacy policy / Play Data Safety coverage for cloud token exchange and outbound API calls.
6. For Polar and Garmin, add the required transaction/backend sync layers before presenting them as fully live import sources.
