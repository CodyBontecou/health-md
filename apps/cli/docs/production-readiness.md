# Standalone CLI production readiness

## Current decision

The latest public standalone release, `healthmd-cli/v0.1.0-alpha.7`, is an explicitly unqualified preview. It is not Health.md CLI 1.0 and no 1.0 date is committed. The bundled Mac MCP helper is a separate production component versioned with the Health.md Mac app; installing or qualifying one topology does not qualify the other.

Published alpha.7 exposes 19 MCP tools. Current development source exposes 23: the 21-tool export/query set plus agent-bridge `healthmd_export_plan` and `healthmd_export_approval`. These two planning/approval-relay tools are not additions to the frozen 1.0 scope below; native bridge setup/routes and bound execution remain incomplete. Documentation, support, and release evidence must name the exact version rather than assigning development tools to alpha.7.

`healthmd_capabilities` reports `support_status: preview_unqualified` and `cli_1_0_qualified: false`. `healthmd_doctor` adds the exact CLI version, negotiated application protocol, source app/build/OS when the mobile peer supplies them, and history-authorization evidence on OS 27+. These fields are evidence, not a self-certification switch.

## Frozen 1.0 scope

The first stable release retains only the already bounded local-first product:

- one installed `healthmd` identity plus its same-version `healthmd-mcp` compatibility launcher;
- macOS, Linux, and Windows Manual IP/Tailscale operation without the Mac app;
- native credential storage with no plaintext fallback;
- iPhone status, typed query/evidence, canonical raw/extract, production-generated files, durable resume, and acknowledged cancellation;
- Android status, provider-native raw/generated files, durable resume, and acknowledged cancellation;
- the 21-tool local stdio MCP catalog and the 13-tool read-only catalog;
- bounded, job-bound full-corpus artifact reads (never arbitrary paths);
- exact scope, coverage, missingness, unsupported, skipped, partial, and history-authorization semantics;
- the health-free bounded wake window and enrolled iPhone notification nudge.

Not required for 1.0: Android typed MCP queries, Android FCM wake, remote HTTP/OAuth distribution, Nearby/Multipeer transport, a Health.md cloud corpus, arbitrary file/URL/shell tools, or unattended background HealthKit capture.

## Qualification matrix

A candidate is stable only when one immutable tag SHA has retained health-free evidence for every required row below. “Pairs successfully” is a smoke check, not qualification.

| Area | Required evidence |
|---|---|
| macOS Apple silicon | Signed/notarized archive and DMG; install/upgrade; Keychain continuity; LAN and Tailscale; iPhone typed/raw/file/resume/cancel; MCP 21/13 catalogs and PNG/App fallback |
| macOS Intel | Same native artifact, credential, transport, job, and MCP checks |
| Linux ARM64 | Archive/install; Secret Service locked/unlocked/failure behavior; LAN and Tailscale; iPhone and Android retained paths |
| Linux x86-64 | Same Linux checks and systemd/session-environment edge cases |
| Windows x86-64 | Archive/PowerShell install; checksum/signing-ledger posture; Credential Manager continuity; LAN and Tailscale; iPhone and Android retained paths |
| iPhone | Exact app version/build/OS; foreground start; protected-data denial; permission denial/empty ambiguity; OS 27 limited history; partition interruption/resume; cancellation acknowledgement; seven-day expiry |
| Android | Exact app version/versionCode/OS/Health Connect; provider permission/history boundary; native snapshot/file limits; interruption/resume/cancel; unsupported typed-query behavior |
| Security/integrity | Swift↔Rust and Kotlin↔Rust fixtures; peer/install binding; replay rejection; immutable request/destination; digest/partition validation; no health payloads in diagnostics/evidence |
| Distribution | Exact-SHA CI, MSRV, all features, crate packages, SBOMs, signed checksum closure, native archive execution, Homebrew install/upgrade, repository latest-release pointer preserved for Apple |

The authoritative exact mobile rows and evidence digests remain in [`mobile-compatibility.md`](mobile-compatibility.md). The executable release gate remains [`verify-release.py`](../scripts/verify-release.py). A stable tag must fail while any required ledger row is pending.

## Iteration and stop rules

For each candidate:

1. Build once from the immutable tag SHA.
2. Run automated cross-language, workspace, packaging, security, and native smoke gates.
3. Run the full physical matrix against the exact retained artifacts and exact mobile builds.
4. Record only health-free identifiers, outcomes, digests, and failure codes.
5. Fix source and cut a new candidate when evidence fails; never replace bytes under an existing tag.
6. Stop and retain the candidate as unqualified if a required OS/device/credential/signing environment is unavailable. Do not infer a pass or announce 1.0.

## Release and support communication

- CLI releases use `healthmd-cli/v<version>` and `make_latest=false`.
- Apple releases use `v<version>` and retain the repository-wide latest-release role.
- Preview notes must say “unqualified preview,” name exact compatible mobile builds, and identify pending rows.
- Stable notes must link the completed evidence record and state the exact OS/architecture matrix.
- App Store notes and versioned GitHub Releases are the notification sources; source-tree capability counts are never attributed to an older binary release.
