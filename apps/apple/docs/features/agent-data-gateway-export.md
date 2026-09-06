# Agent Data Gateway Export

## Status

- **Docs status:** draft
- **Video priority:** medium
- **Primary screen:** Export → Export Target → Agent Data gateway
- **Source files:** `HealthMd/Shared/Models/AgentDataIngestProtocol.swift`, `HealthMd/Shared/Models/AgentDataGatewaySettings.swift`, `HealthMd/Shared/Managers/AgentDataIngestClient.swift`, `HealthMd/Shared/Managers/AgentDataGatewayExportRunner.swift`, `HealthMd/Shared/Models/ProfileDestinationStore.swift`

## What it does

Agent Data gateway export uploads the **exact exported artifact files** from a profile's export to a user-configured gateway endpoint, following the Agent Data ingestion protocol v1 defined in [`packages/contracts/agent-data/v1/contract.md`](../../../../packages/contracts/agent-data/v1/contract.md). The platform-neutral outcome is identical on Android: a user configures one gateway endpoint URL on a profile, and when that profile's export runs, each eligible artifact file is uploaded unchanged — the same bytes a folder destination would write, never re-encoded, re-rendered, or wrapped in an envelope.

The export runs the standard folder-destination engine unchanged over an ephemeral staging root, then uploads each ingest-eligible artifact individually:

- `health_data_daily` — the per-day `healthmd.health_data` JSON document (`artifact_schema_version` tracks the current Apple export schema version).
- `external_provider_daily` — the `healthmd.external_provider_daily` sidecar for connected providers.

Other generated outputs (markdown, CSV, roll-ups, archives, the data dictionary) have no Agent Data v1 upload kind. They are staged by the engine but never uploaded and never fabricated under a wrong kind; the run summary reports them as ineligible. The JSON format must be part of the profile's output before a gateway export can run.

Apple never emits the Android raw families (`raw_snapshot`, `raw_changes`).

## Protocol (v1)

One artifact per request:

- `POST {endpoint}/v1/ingest` — the frozen path appended to the user's base URL.
- `Content-Type: application/x-healthmd-agent-data-ingest`, exact `Content-Length`.
- Body: one `\n`-terminated `healthmd.agent_data_ingest` v1 manifest line, followed immediately by exactly `byte_count` artifact bytes. No compression, multipart, or chunked upload sessions.
- The manifest's `sha256` and `byte_count` are computed over the exact uploaded bytes. `record_count` is omitted (optional and informational in v1).
- Apple daily artifacts are complete, finalized snapshots of their exported day, so `completeness` is always `{"type":"complete"}`; the phone never emits an unfinalized partial on this surface.

Every answered upload is HTTP 2xx with a health-free `healthmd.agent_ingest_response` v1 receipt. Rejections use exactly the four stable codes: `accepted`; `truncated` / `checksum_invalid` / `manifest_incomplete` (fix-and-reupload — Health.md never auto-retries these and surfaces them to the user); `transient` (retry).

## Retry posture

Bounded retries with exponential backoff for transport failures (connection refused/reset/timeout, non-2xx transport-level rejections) and `transient` receipts. The three fix-and-reupload codes are never auto-retried. An export always completes with per-artifact outcomes even when uploads fail: a failed upload does not lose the staged artifact and never blocks the remaining artifacts.

## Setup

1. Open **Export → Export Target → Agent Data gateway**.
2. Enter a base URL such as `https://gateway.example.com` (HTTP or HTTPS; no token in v1).
3. Make sure the **JSON** export format is selected.
4. Export one day before sending a long range.

Gateways carry no credential in ingestion protocol v1, so configuration is exactly one endpoint URL. The URL must be non-empty, contain no line breaks, use the `http` or `https` scheme, and have a host; user info and fragments are rejected. Errors, labels, and history are health-free.

## Where it runs

The destination participates in every trigger surface the existing destinations use: manual export from the Export tab, scheduled exports, and profile-bound runs (the profile editor binds a saved gateway like a saved API endpoint). Shared Setup v2 bundles never include Agent Data gateway profiles: the v2 destination grammar has no gateway kind, and gateway configuration is excluded rather than approximated as another destination.

## Results and history

Export results and history surface per-artifact outcomes with health-free labels: accepted count, rejected count (with the stable rejection code), and upload-failed count, plus the ineligible staged-file count. A day counts as exported only when every eligible artifact for that day was accepted; upload failures surface as failed-date details so residual scheduled retries keep the day retryable.

The self-hosted reference gateway is `healthmd data ingest-serve`; see [`apps/cli/docs/agent-data.md`](../../../../apps/cli/docs/agent-data.md).
