# RFC-0003: Apple `healthmd.health_data` v8 typed provider sections

- Status: **Accepted — Apple-only v8**
- Decision date: 2026-08-12
- Owners: Apple, contracts, shared core, CLI, website, and Obsidian integration owners
- Supersedes only RFC-0002's prohibition on any v8 writer; RFC-0002's rejection of a unified cross-platform schema remains in force.

## Decision

Apple advances its existing daily profile from `healthmd.health_data` v7 to v8 to add optional, typed, provider-namespaced sections. Android frozen v4 and Android analytical v5 do not change and are not relabeled. This is not the unified cross-platform v8 considered and deferred by RFC-0002.

Apple v8 initially permits `providers.whoop` using `healthmd.provider.whoop_daily` v1. The typed section supplements Apple Health data for an already-retained Apple day and never creates provider-only exported days. It coexists with provider-native `healthmd.external_provider_daily` v1 sidecars.

The normative schema, mappings, omission rules, privacy rules, fixtures, and bounds are in `packages/contracts/proposals/provider-sections-v1/`. The historical directory name is retained for stable links; the contract is shipped rather than provisional.

## Compatibility boundaries

- Apple v5, v6, and v7 signatures and the frozen native Apple v7 renderer fixture remain immutable.
- Android v4/v5 public profiles, schemas, and fixture bytes remain independent.
- API v2 retains typed daily data in `records` and provider-native data in `external_records`.
- Strict CLI `--raw` remains canonical Apple Health only.
- Provider values never populate Apple summary keys. WHOOP RMSSD is never labeled as HealthKit SDNN.
- Provider-bearing render operations remain native-authoritative until the shared renderer has an explicit typed-provider contract.
- Existing provider-free Apple v8 daily and roll-up semantics may use the shared Rust profile.

## Ownership and boundedness

Provider capture uses the same frozen IANA calendar timezone and half-open owner-day window as the corresponding Apple Health capture. WHOOP collection pagination is capped at 100 pages, typed collections retain at most 10,000 records, and response bytes remain bounded. Limit failures retain successful sibling resources with safe errors and never expose credentials, URLs, headers, cursors, account identity, or raw response bodies.

## Producer and consumer review

The change covers Apple local/background exports, API Endpoint, Connected Mac jobs and streams, direct generated files, durable recovery, generated reference documentation, contracts, shared Rust profile metadata, website reference mirrors, and CLI canonical-raw isolation. The external Obsidian/visualization consumer must branch on the explicit daily and nested provider versions; flat projections are restricted to unambiguous `whoop_*` scalars.

## Follow-up

[RFC-0004](rfc-0004-unified-health-data-v9.md) now proposes a unified cross-platform successor as `healthmd.health_data` v9, with its language-neutral schema and fixtures under `packages/contracts/proposals/unified-health-data-v9/`. It is deliberately v9 because this RFC already assigns v8 to the Apple grammar. The proposal still requires RFC-0002's release evidence, dual-read/write, external-consumer, privacy, and owner-approval gates before any production writer is enabled. Apple v8 does not supply or imply semantic equivalence with Android v4/v5.
