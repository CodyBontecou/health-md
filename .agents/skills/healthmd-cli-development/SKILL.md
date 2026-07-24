---
name: healthmd-cli-development
description: Develop, debug, or extend Health.md's Mac CLI, direct-iPhone backend, and Mac-initiated iPhone export pipelines. Use whenever the user asks to change scripts/healthmd, add CLI flags/backend behavior, modify the localhost control server or direct pairing/transport, alter Mac↔iOS export messages, fix CLI export builds, or reason about how the CLI triggers iOS HealthKit exports with or without the Mac app.
compatibility: Requires the Health.md Xcode project and Swift/iOS/macOS build tools. Relevant files live under HealthMdCLI, Packages/HealthMdConnectivity, HealthMd/Shared/Sync, HealthMd/iOS, HealthMd/macOS/Managers, scripts/healthmd, docs/features/cli-mac-iphone-export.md, and docs/features/cli-direct-iphone.md.
---

# Health.md CLI Development

Use this skill when changing the CLI, loopback control server, direct-iPhone backend, query API, or Mac-initiated iPhone export path. Keep `mac-app` as the compatible default and make `direct` explicit. iPhone always owns HealthKit, quota, and production export generation. The Mac app owns encrypted query context and bookmark-based file writes; direct CLI owns only its explicit authenticated connection, durable receiver, raw output, and user-supplied destination writes.

## Development rules

- Preserve machine-readable CLI behavior. Executed command outcomes remain JSON; argument/help text may remain plain text.
- Keep `scripts/healthmd` a thin development wrapper; substantial behavior belongs in `HealthMdCLI/` or app layers.
- Keep fresh HealthKit reads on iPhone. The Mac app and CLI must never imply that macOS reads Apple Health directly.
- Treat `healthmd.health_data` as the sole public source-data shape. Typed query/MCP responses are bounded derived protocol views over a disposable encrypted index.
- Preserve explicit backend and transport selection. Never silently fall back between `mac-app`/`direct` or `manual-ip`/`nearby`.
- Keep direct query, evidence, refresh, metrics-catalog, doctor, and MCP unsupported until direct mode has an equivalent encrypted-context/catalog design; return deterministic `backend_unsupported` errors. Canonical `extract` is supported through direct durable raw transport.
- Keep Direct CLI Access opt-in and foreground-scoped. Keep direct trust separate from Mac-app sync trust.
- Direct file export requires an existing absolute `--destination`; preserve path/symlink/digest/mutation checks and restart-safe overwrite/append/Markdown merge receipts.
- Never log HealthKit contents. Return health values only through explicit extract, raw, query, or evidence operations.
- Before changing an exporter, metric/unit mapping, JSON/CSV/Markdown shape, frontmatter, or schema signature, read `docs/features/export-schema.md` and follow the repository export-schema contract.

## Architecture

```text
default mac-app backend
  healthmd → loopback :17645 → HealthMdControlServer
    export → MacIPhoneExportRequestCoordinator → connected iPhone
    query  → HealthMdAgentAPIService → encrypted Mac context

direct backend
  healthmd listener ← explicit Manual IP :17647/Tailscale or Nearby → open iPhone
    DirectMessage + encrypted channel
    iPhone protected raw spool or VaultManager production-file staging
    bounded partitions → CLI durable receiver → --output or --destination
```

There are no Mac-app CLI credentials, registrations, access grants, or Health Context Profiles; loopback is that backend's complete access boundary. Direct mode has an explicit pairing credential, persistent reconnect trust, mutual peer/install binding, encrypted sessions, and a distinct authorization boundary. Query and refresh requests remain Mac-app-only and carry metrics, sources, dates, detail, and operation directly.

## Core files

| Area | Files |
|---|---|
| CLI | `HealthMdCLI/Sources/healthmd/main.swift` |
| Direct shared protocol/transport | `Packages/HealthMdConnectivity/Sources/HealthMdConnectionCore` |
| Direct durable client/receivers | `Packages/HealthMdConnectivity/Sources/HealthMdDirectClientCore` |
| Direct iOS service/export | `HealthMd/iOS/IPhoneDirectCLIService.swift`, `HealthMd/iOS/IPhoneDirectExportCoordinator.swift`, `HealthMd/iOS/IPhoneDirectFileExportProducer.swift` |
| MCP | `HealthMdCLI/Sources/HealthMdMCPCore/HealthMdMCPServer.swift`, `HealthMdCLI/Sources/healthmd-mcp/main.swift` |
| Dev wrapper | `scripts/healthmd` |
| Control API | `HealthMd/macOS/Managers/HealthMdControlServer.swift` |
| Query API | `HealthMd/macOS/Managers/HealthMdAgentAPIService.swift` |
| Mac request lifecycle | `HealthMd/macOS/Managers/MacIPhoneExportRequestCoordinator.swift` |
| iOS request handling | `HealthMd/iOS/IPhoneExportRequestHandler.swift` |
| Sync protocol | `HealthMd/Shared/Sync/SyncPayload.swift` |
| Request selection | `HealthMd/Shared/Sync/CanonicalRawCLIModels.swift` |
| Query contracts | `HealthMd/Shared/Query/QueryContracts.swift` |
| Bounded transfer | `HealthMd/Shared/Sync/ConnectedTransfer.swift` |
| Mac/iOS wiring | `HealthMd/macOS/HealthMdApp+macOS.swift`, `HealthMd/iOS/HealthMdApp.swift` |
| Tests | `HealthMdTests/Sync`, `HealthMdTests/macOS`, `HealthMdCLI/Tests` |
| Docs | `docs/features/agent-local-api.md`, `docs/features/cli-mac-iphone-export.md`, `docs/features/cli-direct-iphone.md`, `docs/features/local-mcp.md` |

## Direct backend invariants

`DirectServerListener` selects Manual IP or Nearby with no fallback. Pairing uses a short-lived code plus ephemeral Curve25519/HMAC proofs, then persists a random reconnect credential under the direct trust namespace. Every reconnect binds both installation IDs and fresh nonces/keys and establishes an encrypted `DirectSecureChannel`. Nearby must require Multipeer encryption in addition to the application layer.

Direct transfers use 512 KiB frames, negotiated 32–64 MiB physical partitions, SHA-256 partition/digest chains, durable checkpoints, immutable request fingerprints, seven-day jobs, and disk-only corpus assembly. A logical day or file may cross partitions. Never raise a memory/partition cap to solve aggregate size.

Direct file generation must continue using `VaultManager` in protected iPhone app-container staging. Any exporter/mapping/frontmatter/CSV/JSON shape change follows `docs/features/export-schema.md`. Keep the public schema synchronized rather than duplicating exporter behavior in the CLI.

## Loopback API contracts

Export routes:

```text
GET  /v1/status
POST /v1/exports
```

Query routes:

```text
GET  /v1/agent/capabilities
GET  /v1/agent/metrics
GET  /v1/agent/readiness
POST /v1/agent/query
POST /v1/agent/evidence
POST /v1/agent/refresh
GET  /v1/agent/jobs/{id}
POST /v1/agent/jobs/{id}/resume
POST /v1/agent/jobs/{id}/cancel
```

Removed profile and activity routes return `410 removed_endpoint`. Do not restore silent compatibility or credential handling.

A query wrapper contains `detail_level: summary | lossless` and a versioned `healthmd.query_request` carrying dates, metrics, sources, operation, and page bounds. A refresh carries explicit date, metric, source/provider, detail, and wait-time scope. Validate all selectors against current catalogs. Missing selection must fail rather than inheriting saved iPhone metrics.

Fresh query acquisition uses `CanonicalHealthDataSelection` on a cloned settings object. Persist the exact immutable selection and owner-date labels in durable Mac/iPhone recovery state so resume cannot widen or change scope. Apple Health and selected providers are both supported; a provider-only request skips HealthKit.

Query responses remain bounded by page item/byte limits and opaque cursors. Complete traversal may span multiple pages; do not introduce total history, metric, provider, or result caps. Preserve missing, unsupported, skipped, failed, and complete-empty distinctions.

## Export control contract

Typical file request:

```json
{
  "source": "connected_iphone",
  "date_range": {"start": "2026-06-01", "end": "2026-06-07"},
  "settings_policy": "requested_dates_only",
  "response_mode": "write_files",
  "wait_timeout_seconds": 120
}
```

`requested_dates_only` keeps saved iPhone output formats/path/write behavior but disables roll-ups and summary-only mode for the request. An optional `canonical_selection` replaces metric/detail scope without persisting it. `current_iphone_settings` mirrors saved settings exactly.

Use `response_mode: raw_json` with:

- `raw_profile: canonical_source_records_v1` for strict complete archival transport;
- `raw_profile: health_data_projection` plus `canonical_selection` for scoped extraction;
- no `raw_profile` only for legacy internal-Codable compatibility.

Raw transport writes no destination files. Summary extraction must not fetch an archive. Archive object selection implies lossless. Keep strict response validation, checksum/range headers, bounded-memory streaming, and atomic output behavior.

Response status values are `success`, `partial_success`, `failure`, `cancelled`, `unavailable`, and `timed_out`. Prefer additive optional fields when extending ordinary export contracts.

## Sync protocol checklist

When changing messages in `HealthMd/Shared/Sync/SyncPayload.swift`:

1. Add/update the Codable `SyncMessage` case and nearby payload types.
2. Add a capability/version field when old peers must reject cleanly. Direct context acquisition uses `supportsRequestScopedContextAcquisition`.
3. Update both app switch statements in `HealthMd/iOS/HealthMdApp.swift` and `HealthMd/macOS/HealthMdApp+macOS.swift`.
4. Persist exact durable scope before transfer starts.
5. Update `HealthMdTests/Sync/SyncV2ProtocolTests.swift` round-trip coverage.
6. Build both app targets.

Current peers prefer partitioned connected exports with negotiated 32–64 MiB partitions. Strict raw additionally requires strict streaming and exact archive/raw-result versions. Mixed-version peers retain the bounded single-payload fallback. Never raise a cap to solve corpus-scale work; use partition sessions and disk-backed final output.

## Common changes

### Add CLI flags

1. Parse and validate in `HealthMdCLI/Sources/healthmd/main.swift`.
2. Encode the direct request fields; do not add token/profile/grant flags.
3. Decode them in the relevant control or query body.
4. Decide whether Mac can satisfy the request or iPhone must receive it.
5. Update CLI/MCP tests, help text, docs, and generated references.

### Add a query or MCP operation

1. Define an explicit bounded operation in `QueryContracts.swift`.
2. Derive required canonical metrics/detail in code and include them in direct request scope.
3. Use `CanonicalHealthDataSelection`; never mutate saved iPhone settings.
4. Derive ordinary HealthKit authorization descriptors only from selected metrics. Preserve special-domain skip/partial diagnostics.
5. Query encrypted Mac context after fresh acquisition, or support explicit cached mode.
6. Keep evidence factual and preserve units, sources, coverage, limitations, and missingness.
7. Add API, CLI, and MCP contract tests.

Read denial can look empty under HealthKit privacy. Do not infer permission from values or trigger an unexpected authorization sheet from an automated request.

### Add settings-policy support

Clone through `ExportSettingsSnapshot.from(saved).makeAdvancedExportSettings()` before applying request overrides. Constructing/mutating a default `AdvancedExportSettings()` can affect persisted user settings.

### Add UI affordances

Use `MacIPhoneExportRequestCoordinator` and existing query service state rather than duplicating request lifecycles. Do not add profile, credential, registration, grant, or access-activity management UI.

## Build and test

Use bounded commands where needed:

```bash
xcodebuild -project HealthMd.xcodeproj -scheme HealthMd-macOS -configuration Debug -destination 'platform=macOS' build

xcodebuild -project HealthMd.xcodeproj -scheme HealthMd -configuration Debug -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO

xcodebuild test -project HealthMd.xcodeproj -scheme HealthMd-Tests-macOS -destination 'platform=macOS' \
  -only-testing:HealthMdTests/SyncV2ProtocolTests \
  -only-testing:HealthMdTests/CLIRawControlSafetyTests \
  -only-testing:HealthMdTests/HealthMdAgentAPIServiceTests \
  -only-testing:HealthMdTests/ConnectedTransferTests

swift test --package-path Packages/HealthMdConnectivity
swift test --package-path HealthMdCLI
swift build --package-path HealthMdCLI -c release
NO_COLOR=1 TERM=dumb timeout 15 scripts/healthmd --help </dev/null
```

Before finishing, verify both app targets build; relevant protocol, API, CLI, and MCP tests pass; docs and generated references match the contract; and no health values are logged or returned by status/readiness.
