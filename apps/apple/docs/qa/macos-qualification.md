# macOS release qualification

## Status

- **Current macOS 27 certification:** `false`
- **Reason:** final certification requires retained evidence from both Apple's exact macOS 27 RC and public build.
- **Applies to:** Health.md Mac app, its bundled `healthmd` and `healthmd-mcp` helpers, encrypted context, connected-iPhone transports, automation, upgrade, signing, and notarization.

An automated preflight, a beta build, or a successful launch is not certification. Do not turn preparation into a customer compatibility promise.

## Run the harness

The harness is health-free and standard-library-only:

```bash
# Inspect the check inventory on any host.
apps/apple/scripts/qualify-macos-release.py --plan

# On macOS, inspect the exact distributed app bundle.
apps/apple/scripts/qualify-macos-release.py --run \
  --app /Applications/Health.md.app \
  --expected-version 3.4.2 \
  --output artifacts/macos-qualification/3.4.2-<build>-preflight.json
```

`--run` verifies bundle identity, strict nested signing, Gatekeeper acceptance, helper presence/version, and the bounded bundled-MCP `initialize`/`tools/list` handshake with exactly 21 tools. It creates pending entries for runtime and physical checks. It deliberately always emits `certified_for_macos_27: false`; automated tooling cannot attest that a human ran the required devices, transports, RC, and public-build matrix.

Run against the staged/notarized artifact that customers install, not an Xcode development bundle. Preserve the immutable installer/archive digest next to the generated record. The harness records the main executable digest as an additional identity check, not as a substitute for the distribution-artifact digest.

## Required phases

### 1. Automated candidate gate

From committed, pushed source and a clean worktree:

1. Run Apple unit/integration/UI suites and shared-contract gates.
2. Archive, export, sign, notarize, and staple the candidate.
3. Run the harness on every retained Mac architecture.
4. Verify the helper version equals the app version and the bundled catalog contains 21 tools.
5. Confirm no evidence/log artifact includes health records, authorization payloads, routes, credentials, or user-selected paths.

Any failure requires a new candidate. Never replace bytes under an existing tag.

### 2. Runtime matrix

With the exact distributed app installed:

- fresh install and upgrade from the last public version;
- login-item/menu-bar lifecycle, ordinary relaunch, sleep/wake, and explicit closed-lid limitations;
- Keychain access from the signed app and nested helpers;
- encrypted context create/query/refresh/delete plus exact owner-day and encrypted-byte accounting;
- security-scoped destination bookmark across relaunch, volume removal, and remount;
- fixed loopback HTTP/MCP boundary and 21-tool catalog;
- scheduled work while the phone is foreground, locked, disconnected, and reconnected;
- cancellation acknowledgement, partition interruption/resume, and seven-day job expiry;
- limited Apple Health history, denied types, no-data types, API-unavailable runtimes, and protected-data denial.

Never use customer health data. Synthetic accounts/records must not be copied into the evidence record.

### 3. Physical transport matrix

Use the exact mobile app version/build and record it:

| Transport | Required checks |
|---|---|
| Nearby | authenticated reconnect, bounded context refresh, direct generated-file export, disconnect/recovery |
| LAN | refresh/query/export, durable resume, acknowledged cancel, address change |
| Tailscale | Manual IP pairing, fresh read/export, network transition, no silent LAN/Nearby fallback |
| Offline Mac context | typed query while phone is absent; refresh correctly reports phone requirement |

The Mac must remain awake to serve MCP. Closed-lid sleep is not a supported availability guarantee.

### 4. OS 27 RC and public build

Run the complete critical matrix first on the exact RC, then repeat it on Apple's public macOS 27 build. Record:

- exact `sw_vers` product/build values;
- app version/build and source commit;
- archive/DMG digest and notarization identity;
- iPhone/iPad version/build/OS and negotiated protocols;
- each check's pass/fail/pending result and health-free failure code;
- reviewer and timestamp in the retained release system.

Only after both records pass may customer-facing notes state that the exact Health.md release is certified for macOS 27. Update the machine-readable readiness response and release notes in the same candidate; do not retrofit the claim onto an older artifact.

## Evidence acceptance

A qualifying record has:

- no pending or failed required check;
- one immutable candidate identity across automation and physical runs;
- both RC and public-build records for a macOS 27 claim;
- all required Mac architectures and supported upgrade paths;
- explicit iPhone protocol/app/build evidence;
- no health data or secrets;
- a reviewer who did not infer results from unrelated tests.

If an environment, device, signing identity, RC, or public build is unavailable, stop with the gathered evidence and mark the candidate pending. The correct report remains `certified_for_macos_27: false`.
