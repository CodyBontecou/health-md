---
title: Release status and compatibility
description: Check which Health.md automation components are production, preview, OS-qualified, and where to subscribe for exact version notifications.
---

Health.md has independently versioned products. A version number or successful connection does not qualify every topology.

## Current status

| Component | Release identity | Current support state | Qualification boundary |
|---|---|---|---|
| iPhone, iPad, Mac, and Apple Watch apps | `v<version>` | App Store product | Each release note must name tested Apple OS versions. macOS 27 remains **not certified** until the RC and public-build physical matrix is retained. |
| Bundled Mac `healthmd-mcp` | Same `v<version>` as the Mac app | Production component | Uses encrypted Mac context and the Mac app's authenticated iPhone connection. It is not the standalone CLI and has no separate 1.0 milestone. |
| Standalone `healthmd` and `healthmd mcp serve` | `healthmd-cli/v<version>` | `0.1.0-alpha.7` is an explicitly unqualified preview | No CLI/mobile pair is qualified for stable 1.0 yet. Published alpha.7 has 19 MCP tools; current development has 21. |
| Website | Commit deployment | Documentation | Describes released behavior separately from development behavior. |

There is no committed date for standalone CLI 1.0. Stable status requires the exact retained macOS, Linux, Windows, iPhone, Android, LAN, and Tailscale matrix—not just automated tests or a pairing smoke check.

## Machine-readable checks

Call `healthmd_doctor` before automation and `healthmd_capabilities` when choosing tools.

These tools report operational readiness and supported operations, **not release qualification**. The following JSON blocks are illustrative, health-free **excerpts**, not complete responses or device captures. Fields and values vary with connection, cache, pairing, and caller permissions.

### Bundled Mac

`healthmd_doctor` calls `/v1/agent/readiness` (`healthmd.local_readiness/1`). It returns `status`, `query_store`, `iphone`, `checks`, and `next_actions`. When the encrypted query store is available, `query_store` contains its revision, owner-date count, and first/last owner dates (dates can be null). When unavailable, it reports `available: false` and may include an error instead of cache counts.

For example, cached owner days can make queries ready even without a connected iPhone:

```json
{
  "schema": "healthmd.local_readiness",
  "schema_version": 1,
  "status": "ready",
  "query_store": {
    "available": true,
    "revision": "revision-1",
    "owner_date_count": 2,
    "first_owner_date": "2026-07-20",
    "last_owner_date": "2026-07-21"
  },
  "iphone": {
    "connected": false,
    "name": null,
    "supports_request_scoped_context_acquisition": false,
    "can_trigger_fresh_acquisition": false
  }
}
```

Inspect blocking `checks` and `next_actions` before proceeding. `ready` does not prove that cached data is fresh or that all historical health data was authorized.

`healthmd_capabilities` calls `/v1/agent/capabilities` (`healthmd.local_capabilities/1`). It describes versioned query/evidence contracts, query operations, pagination limits, and whether a refresh executor is configured:

```json
{
  "schema": "healthmd.local_capabilities",
  "schema_version": 1,
  "readiness": "healthmd.local_readiness/1",
  "request_scoped": true,
  "request_scoped_context_acquisition": true,
  "fresh_acquisition": false
}
```

`fresh_acquisition` describes executor availability, not current iPhone connectivity. Likewise, `all_available_history` is a scope capability, not proof of complete history authorization. The separate control status response reports `mac_app`, `iphone`, `destination`, and an optional `active_export`; it is not a qualification record.

### Standalone preview

`healthmd_doctor` returns `healthmd.direct_readiness/1`. An unpaired configuration reports `status: "not_paired"` and `ready: false` with guidance. An authenticated status response reports `ready`, `query_ready`, `raw_export_ready`, device name, application protocol version, port, foreground/protected-data state, export state, and wake status. The iPhone branch additionally reports query/file-export flags, active query ID, and query capabilities; the Android branch reports available products. Transport failures can return a structured tool error rather than a readiness object.

For example, a ready Android raw-export service does not imply typed-query support:

```json
{
  "schema": "healthmd.direct_readiness",
  "schema_version": 1,
  "status": "ready",
  "ready": true,
  "query_ready": false,
  "raw_export_ready": true,
  "device_name": "Android fixture",
  "application_protocol_version": 2,
  "port": 17647,
  "app_active": true,
  "protected_data_available": true,
  "export_in_progress": false
}
```

Portable `healthmd_capabilities` instead returns `healthmd.mcp_capabilities/1`: surface profile, source kind/transport, foreground requirements, supported operations, caller-scoped pairing/export availability, query guidance/limits, and result fallbacks. For the local direct surface:

```json
{
  "schema": "healthmd.mcp_capabilities",
  "schema_version": 1,
  "surface_profile": "local_direct",
  "source_kind": "paired_mobile",
  "transport": "authenticated_encrypted_mobile_direct",
  "requires_foreground_source": true
}
```

Use direct readiness to check the connected mobile source; a tool catalog alone does not establish that source's query support. MCP initialization `serverInfo.version` identifies the helper/package version separately from these tool responses. It is not a channel, OS, source-build, history-authorization, or qualification field.

### Not currently returned

Neither readiness/capabilities surface returns release-channel/qualification fields such as `preview_unqualified`, `cli_1_0_qualified`, or `certified_for_macos_27`, running/source OS and build metadata, OS 27 history-authorization state such as `limited_history` or `api_unavailable`, or encrypted-store byte totals. Their absence means **not reported**, not explicit false qualification, zero bytes, or complete history. Future machine-readable qualification/history/footprint fields require separately scoped, versioned implementation and tests; consumers must not rely on them today.

Mac Settings exposes encrypted context owner-day count/range and deletion controls, not an encrypted-byte footprint. Durable-job `committed_bytes` (for example in `active_export` or job status) measures transfer progress; it is **not the encrypted context store's on-disk size**.

The standalone CLI remains explicitly **unqualified for stable 1.0**, and macOS 27 remains **not certified**. These are release-status statements, not runtime fields. Machine-readable operational status does not replace retained release qualification.

## Notifications

Use the versioned sources that match the product:

- **Apple apps:** [GitHub releases tagged `v<version>`](https://github.com/CodyBontecou/health-md/releases?q=v) and App Store update notes. Apple releases retain the repository-wide “Latest” release.
- **Standalone CLI:** [GitHub releases tagged `healthmd-cli/v<version>`](https://github.com/CodyBontecou/health-md/releases?q=healthmd-cli%2Fv). CLI releases deliberately use `make_latest=false`; do not use `/releases/latest` to discover them.
- **All repository releases:** [GitHub Releases Atom feed](https://github.com/CodyBontecou/health-md/releases.atom). Filter by tag prefix if you only want Apple or CLI updates.
- **Source changes:** [repository commits](https://github.com/CodyBontecou/health-md/commits/main/) are development evidence, not release availability.

Every automation/OS release note must state: exact app/helper/CLI version, release channel, supported/qualified OS builds, compatible mobile build/protocol, history-boundary behavior, tool count, and known pending physical gates.

## macOS 27

Preparation and automated checks may run before release, but “certified for macOS 27” is allowed only after:

1. the candidate is built from committed, pushed source;
2. signing, nested helpers, notarization, Keychain, encrypted context, bookmarks, loopback MCP, iPhone LAN/Nearby/Tailscale, durable jobs, sleep/wake, and upgrade paths pass on the RC;
3. the critical matrix is repeated on Apple's public macOS 27 build;
4. a health-free evidence record identifies exact OS/app/build/artifact hashes.

Until then, macOS 27 is **not certified**. Readiness does not currently return a `certified_for_macos_27` field; a successful connection or `status: "ready"` must not be interpreted as certification.

## Choosing a topology

Use the bundled Mac MCP for routine local analysis and offline/repeated queries from encrypted context. Use the standalone preview only when you need direct cross-platform scripting, fresh foreground-phone reads, canonical extraction, or durable archival jobs and accept its preview qualification state. The two can coexist, but they do not share trust, credentials, jobs, or cached health data.
