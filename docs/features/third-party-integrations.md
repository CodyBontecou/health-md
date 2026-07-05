# Third-Party Provider Integrations

## Status

- **Docs status:** draft
- **Primary screen:** Settings → Connected Apps
- **Source files:** `HealthMd/Shared/Integrations/*`, `HealthMd/iOS/Managers/ExternalIntegrationManager.swift`, `HealthMd/iOS/Views/ExternalIntegrationsView.swift`, `HealthMd/Shared/Managers/APIExportClient.swift`, `HealthMd/Shared/Sync/MacExportJobBuilder.swift`, `HealthMd/macOS/Managers/MacExportJobExecutor.swift`, `worker/oauth-broker/*`

## What it does

Health.md can connect third-party provider accounts and export provider-native data as sidecar JSON files next to the normal Apple Health export.

The first supported providers are:

- Fitbit
- Oura
- WHOOP
- Withings
- Strava

Partner-gated providers are intentionally not implemented in this phase:

- Garmin — business/enterprise approval required.
- TrainingPeaks — approved partner access required.
- Dexcom direct API — partner review, server-side token storage, HIPAA/privacy/regulatory review required. Apple Health blood glucose remains the recommended path first.

## Privacy model

Apple Health remains the core Health.md source. Third-party provider data is optional.

For providers whose OAuth docs require a client secret, Health.md uses a minimal Cloudflare Worker OAuth broker. The broker only builds authorization URLs, exchanges authorization codes, and refreshes tokens. It does not store provider tokens or health data.

Provider access tokens are stored on-device in Keychain. Provider API calls are made directly from the iPhone app to the provider API. Exported provider records are written to the selected local folder, sent inside the user's configured API Endpoint payload, or transferred to the connected Mac for Mac-side file writing.

## Output shape

Provider exports use a separate sidecar schema so the stable daily `healthmd.health_data` contract is not changed.

Local iPhone and Connected Mac file exports write provider sidecars with this folder layout:

```text
Health/
  2026-07-03.md
  2026-07-03.json
  integrations/
    oura/
      2026-07-03.json
    strava/
      2026-07-03.json
```

Example sidecar record:

```json
{
  "schema": "healthmd.external_provider_daily",
  "schema_version": 1,
  "provider": "oura",
  "provider_display_name": "Oura",
  "date": "2026-07-03",
  "fetched_at": "2026-07-03T18:00:00Z",
  "payloads": [
    {
      "name": "daily_readiness",
      "endpoint": "https://api.ouraring.com/v2/usercollection/daily_readiness?start_date=2026-07-03&end_date=2026-07-03",
      "status_code": 200,
      "fetched_at": "2026-07-03T18:00:00Z",
      "data": { "data": [] }
    }
  ],
  "warnings": []
}
```

## API Endpoint and Mac exports

- API Endpoint export includes provider sidecars in the `healthmd.api_export` v2 envelope under `external_records`.
- Connected Mac exports include provider sidecars in `MacExportJob.externalDailyRecords`; the Mac writes them to `Health/integrations/{provider}/{yyyy-MM-dd}.json` with the same local file shape.
- Mac-initiated raw JSON requests include provider sidecars in `raw_data.externalDailyRecords` when connected apps are available on the iPhone.

## Current limitations

- Provider records are fetched for requested days that produced a canonical Health.md daily record. Provider-only days do not yet make an otherwise empty export count as successful.
- Provider payloads are preserved as raw JSON. Normalized provider-specific keys can be promoted later behind a schema versioned contract.
- Scope denial or unavailable provider endpoints appear as per-payload errors in the sidecar file instead of failing the whole Health.md export.

## Schema policy

This phase does **not** bump `HealthMdExportSchema.version` because canonical Markdown, Bases, JSON, CSV, and data dictionary output are unchanged. The third-party sidecar has its own schema identifier and version.

If provider fields are later merged into daily Markdown/frontmatter/JSON/CSV or the data dictionary, follow `docs/features/export-schema.md` and bump the Health.md export schema version.
