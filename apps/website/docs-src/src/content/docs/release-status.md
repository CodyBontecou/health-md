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

- The bundled Mac endpoint reports app/helper version, production-component status, running macOS, macOS 27 qualification state, encrypted owner-day/byte totals, connected iPhone version/protocol, and the history-authorization contract.
- The standalone preview reports its exact package version, `preview_unqualified`, `cli_1_0_qualified: false`, negotiated source version/build/OS when supplied, and OS 27 history authorization state.
- `limited_history` means earlier Apple Health data is unknown, not absent. `api_unavailable` means the runtime cannot verify the boundary. Neither should be rewritten as “complete history.”

Machine-readable status is evidence about the running components. It does not replace retained release qualification.

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

Until then, readiness reports `certified_for_macos_27: false`.

## Choosing a topology

Use the bundled Mac MCP for routine local analysis and offline/repeated queries from encrypted context. Use the standalone preview only when you need direct cross-platform scripting, fresh foreground-phone reads, canonical extraction, or durable archival jobs and accept its preview qualification state. The two can coexist, but they do not share trust, credentials, jobs, or cached health data.
