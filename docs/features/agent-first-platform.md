# Agent-First Health Platform

## Status

- **Implementation branch:** `ax`
- **Contract status:** active development
- **Platforms:** iPhone/iPad as the Apple Health source; Mac as the local query and agent service

## Product invariant

Health.md must let a user authorize every Health.md metric, every source record exposed by the public Apple Health and connected-provider APIs, lossless detail, and the complete available historical range.

The implementation must not use arbitrary metric-count, date-window, total-record, or total-byte product caps to make agent access easier to build. Resource safety comes from:

- bounded in-memory pages and transfer frames;
- opaque deterministic cursors whose complete traversal reaches every authorized result;
- disk-backed spools for large responses;
- checksum-validated resumable corpus jobs;
- explicit progress, cancellation, and retention controls;
- user-selected Health Context Profiles and per-client grants.

A page-size or transfer-frame bound is not a data-access limit. A client must be able to continue until the authorized result set is exhausted.

## Trust and execution boundaries

```text
agent client
  -> authenticated Mac registration and grant
  -> Health Context Profile policy
  -> compact local query/evidence service
  -> encrypted Mac context store

explicit fresh acquisition
  -> user confirmation when required
  -> connected/open iPhone
  -> HealthKit / connected providers
  -> bounded resumable transfer
  -> encrypted Mac context store
```

The Mac never claims to read HealthKit directly. Cached queries may work while the iPhone is disconnected. Fresh acquisition still depends on iOS availability, Apple authorization, device lock state, and the public APIs.

## Independent contracts

Agent-first contracts advance independently from the daily export schema:

| Contract | Initial schema | Purpose |
|---|---|---|
| Health Context Profile | `healthmd.health_context_profile` v1 | User-reviewed reusable data policy |
| Query request | `healthmd.query_request` v1 | Metric, workout, coverage, comparison, and evidence requests |
| Compact context day | `healthmd.query_context_day` v1 | Encrypted local query projection and diagnostics |
| Evidence packet | `healthmd.evidence_packet` v1 | Deterministic facts, evidence, coverage, missingness, and limitations |
| Query error | `healthmd.query_error` v1 | Stable machine-readable failures |
| Agent access store | `healthmd.agent_access_store` v1 | Client registrations and grants |
| Agent activity store | `healthmd.agent_activity_store` v1 | Local PHI-minimized access history |

Adding these contracts does not change `healthmd.health_data` v7, `healthmd.healthkit_records` v1, or `healthmd.raw_result` v1. If an agent contract later becomes a new filesystem export or changes an existing exporter, follow `docs/features/export-schema.md` and version that public export intentionally.

## Health Context Profiles

A profile is distinct from Apple Health authorization and saved export formatting. It defines:

- explicit metric IDs or `all_available`;
- explicit providers or `all_available`;
- summary or lossless detail;
- exact/relative date policy or `all_available_history`;
- caller and delivery surfaces;
- destination binding where data leaves the local query service;
- confirmation behavior and optional expiration;
- immutable revision and policy digest.

`all_available` is an explicit dynamic choice and includes newly supported metrics. A selected-ID profile remains frozen until the user edits it. Invalid or stale profiles fail closed and never fall back to current iPhone settings.

The iPhone authoritatively validates fresh acquisition. The Mac keeps the exact pinned policy required to enforce offline access to data already present in its encrypted context store.

## Query and evidence behavior

The local query service supports:

- typed series for every stored metric;
- complete-history queries;
- deterministic period comparisons using documented aggregation rules;
- complete workout/event/source-record traversal;
- capture coverage and diagnostics;
- factual Daily Wellness, Training, and Doctor Visit evidence packets;
- summary and lossless evidence when authorized.

Missing values are never converted to zero. Complete-empty, partial, unsupported, skipped, cancelled, not-requested, legacy-unavailable, redacted, and not-synchronized states remain distinct.

Every fact identifies its unit, owner date/time bounds, derivation, and evidence reference. Arithmetic direction may be described as an increase or decrease, but Health.md does not label a change better/worse, diagnose, triage, recommend treatment, infer causation, or judge medication adherence.

## Agent registration and audit

Loopback is a network boundary, not a caller identity. Agent access uses per-client registration, Keychain-backed credentials, grants pinned to a profile revision, job ownership, immediate pause/revoke, and local activity history.

A grant can explicitly authorize all metrics, all available history, lossless records, all operations, and every destination class. Narrow grants remain supported. Authorization never silently narrows a request; an out-of-scope request returns a stable denial.

Activity history may retain the exact requested date range/all-history marker, metric IDs/all-metrics marker, detail level, destination class, aggregate counts/bytes, outcome, and correlation ID in protected local storage. It must not retain health values, prompts, filenames, vault paths, peer names, endpoint URLs, credentials, response bodies, or source payloads.

Existing unauthenticated CLI requests are honestly identified as an unattributed legacy local process during migration. An API Endpoint is an outbound destination, not an agent identity.

## MCP topology

The first MCP release is a signed sandboxed `healthmd-mcp` stdio helper. It is an adapter over the same profile, query, evidence, grant, and audit services used by the CLI and local HTTP API.

The helper does not read HealthKit, exported files, security-scoped bookmarks, or arbitrary local files. It exposes no shell, SQL, URL-fetch, HealthKit-write, prompt, roots, or model-sampling capability.

Initial tools cover status, capabilities, profiles, metric queries, comparisons, workouts, day/source-record access, diagnostics, evidence packets, and explicit fresh acquisition. Large result sets use complete cursor traversal or disk-backed output rather than being unavailable.

Streamable HTTP MCP is deferred until Health.md has a generic-client authentication and server-identity design that resists port squatting and DNS rebinding.

## Delivery order

1. Shared profile, query, evidence, grant, and audit contracts.
2. Deterministic evaluator plus encrypted Mac context store.
3. Query/profile HTTP routes and `healthmd` CLI commands.
4. Registered-client enforcement and durable job ownership.
5. Signed stdio MCP helper and onboarding UI.
6. Profile-scoped all-history iPhone acquisition and resumable ingestion.
7. Schedule, provider, and external-delivery integration.
8. Cross-platform completion audit and generated contract documentation.

## Completion evidence

The agent-first platform is not complete until tests and runtime evidence prove:

- an explicit all-data profile contains every current metric and dynamically includes a newly added catalog metric;
- an all-history query traverses every stored day and item without an inaccessible tail;
- lossless access returns canonical source identities, diagnostics, provider records, and binary references when authorized;
- arbitrary-size results remain bounded in memory and resumable on disk/wire;
- unauthorized, expired, paused, revoked, stale-revision, and cross-client job requests fail closed;
- every query fact has resolvable evidence and honest missingness;
- Mac queries never invoke HealthKit;
- fresh acquisition remains on iPhone and survives disconnect/relaunch through the existing durable corpus protocol;
- existing v7 export signatures remain byte-identical unless an intentional separately reviewed export-schema change is made;
- iOS, macOS, CLI, MCP, protocol, security, generated-contract, and UI suites pass.
