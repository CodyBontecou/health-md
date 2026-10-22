# Direct CLI

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** Settings → Direct CLI
- **Source files:** `app/src/main/java/com/healthmd/presentation/directcli/DirectCliScreen.kt`, `direct-protocol/src/main/kotlin/com/healthmd/direct/protocol/`, `docs/android-desktop-destination.md`

## Source and qualification

This page describes current development source, not installed/release qualification. The public alpha.7 preview has 19 tools; the current development catalog declares 23, the read-only profile 13, and the frozen CLI 1.0 scope 21. These are different release/profile facts, not 23 qualified Android operations. See [CLI production readiness](../../../cli/docs/production-readiness.md) and [mobile compatibility](../../../cli/docs/mobile-compatibility.md) for exact app/build, CLI artifact, distribution/provider, SDK/OS, transport and operation results; the complete exact-build matrix is still pending.

Development declarations `healthmd_export_plan` and `healthmd_export_approval` do not enable the mobile agent bridge. Private stored-planning/exact-decision services exist, but app/TCP routes for the [independently negotiated extension 4](../../../../packages/contracts/direct-protocol/v4/protocol.md) remain unwired/unadvertised. Wired native consent/configuration/session adapters and qualified send boundaries are still required. Agent-bridge bound execution, verified bridge receipts, host-owned recipes and the full CLI/MCP × iOS/Android journey are not delivered. Existing application v2 exports are a separate path, not evidence of this new journey; pairing or a plan is not permission. Read-only MCP cannot enroll, approve, execute or mutate bridge controls. Android typed direct queries and extraction remain planned in the [bridge roadmap](../../../../docs/architecture/agent-bridge-parity-roadmap.md); query DTOs and supplied-context codec checks are not an Android query service.

## What it does

Pair the Android app with the standalone cross-platform `healthmd` CLI on your Mac, Linux, or Windows computer over a LAN or Tailscale address. The CLI listens; Android connects outbound and streams either a validated provider-native Raw API Snapshot or the same generated Markdown/JSON/CSV/Bases files used by folder exports — with no cloud relay.

## Who it is for

- Desktop-first vaults: land exports directly in a computer folder
- Scripted/CI workflows running `healthmd export` against the phone
- Not an automation or schedule target — pairing and every command are explicit user actions

## Where to find it

1. On the computer: `healthmd direct pair`.
2. On the phone: **Settings → Direct CLI** ("Encrypted desktop exports").
3. Tap **Scan pairing QR** and scan the universal code shown by the CLI. Pairing starts immediately after a valid in-app scan.
4. If the camera is unavailable or denied, enter the **Computer address**, **Port**, and shared **20-digit pairing code**, then tap **Pair with CLI**.

## Prerequisites

- The `healthmd` CLI installed on the computer (listens on TCP 17647 by default)
- Phone and computer on the same network, or reach each other via Tailscale
- Android 9 / API 28+

## Setup

1. Run `healthmd direct pair` on the computer and leave it open.
2. Scan its QR from the Direct CLI screen, or enter the same address, port, and 20-digit code manually.
3. For each transfer, start the CLI command first, then tap **Connect** in the app. Save addresses you reuse with **Save address**.

The QR scanner is implemented with CameraX and ZXing Core in both Play and F-Droid builds. Camera access is optional and requested only after **Scan pairing QR** is tapped. Health.md does not register the `healthmd://direct-cli` handoff as an external app link; only an explicit scan inside this screen can authorize pairing.

## Session lifecycle and native admission

A session uses an explicitly user-started foreground service with a visible data-sync notification. An already-active service may continue while the app UI is backgrounded or during ordinary screen locking; this is not iPhone's foreground-only admission for new health reads. Health Connect remains unavailable before the first unlock after reboot, and reconnect still requires a surviving direct session and reachable CLI. A stopped, killed or force-stopped app is not an active service: reopen Health.md and explicitly start the session rather than treating pairing as unattended permission.

New Health Connect capture requires current record permissions and, for older dates, historical-read permission. The default 30-day history window is relative to the first permission grant when that date is known, not a rolling window before today. The boundary day requires historical-read permission because daily reads begin at midnight, potentially before the grant time. If the grant date is unknown, the current resolver uses today's date as a fallback; that is not a newly verified grant. `--all`/`all_available` does not bypass these checks or establish complete provider access. This native Health Connect grant model is distinct from Apple's unavailable per-type history-boundary API.

New-capture admission also checks app-level export entitlement/quota under the distribution's policy. The coordinator's purchase/entitlement `isUnlocked()` is not Android's device first-unlock state. Durable spool recovery follows its existing immutable job; cancelling, resuming or pairing does not reset the app's consumed quota or manufacture provider permissions. Review the app's export allowance/access and native permissions instead of re-pairing to work around an admission error.

## Example output

```bash
healthmd export --raw --yesterday --provider health_connect --raw-format ndjson
healthmd export --all --raw --full-corpus --provider health_connect --raw-format ndjson \
  --output "$HOME/Documents/HealthVault/health-connect.ndjson"
healthmd export --yesterday --destination "$HOME/Documents/HealthVault"
```

`--full-corpus` maps to `all_authorized_supported_data` and includes exercise routes when they are readable; per-session consent can still report a route unavailable. It means all public record types supported by the provider integration and authorized by the user, never a private Health Connect/provider database. The provider-native snapshot manifest and issue inventory preserve authorization, unsupported, skipped, partial, and read-error evidence. Complete local `healthmd mcp serve` can start the same approval-gated job and read only bounded, base64 chunks from its exact validated job artifact; read-only and remote MCP profiles cannot access it.

A visible data-sync notification ("Waiting for Health.md CLI" → transfer progress) runs during the session. If the CLI closes a connection without a terminal outcome — including the wake window's readiness probe, which rebinds its listener for the real request — the session automatically reconnects with 250 ms to 2 s backoff and keeps waiting; it finishes only after a completed export, an explicit disconnect, or repeated unreachable CLI attempts.

## Tips

- **Connect** is per-command: the CLI must be waiting before you tap Connect.
- Transfers are resumable for up to seven days; artifacts spool in private no-backup storage and are deleted sooner if you cancel, disconnect, or **Forget paired CLI**.
- Fitbit raw snapshots are capped at a 366-day explicit range (day-scoped intraday endpoints); `--all` is rejected before reads.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Connection failed | Wrong address/port or different network | Verify the CLI's printed address; check LAN/Tailscale reachability |
| Pairing rejected | Wrong or expired 20-digit code | Re-run `healthmd direct pair` and scan or re-enter the new code |
| Camera unavailable or denied | No camera hardware or permission | Close the scanner and use manual address, port, and code entry |
| QR rejected | Payload is malformed, public-addressed, or not a current Direct CLI QR | Scan the QR printed by the active `healthmd direct pair` command |
| Device locked error | Health Connect is unavailable before first unlock after reboot | Unlock once, reopen Health.md if needed, and start the direct session |
| Quota exhausted | New-capture app-level export entitlement/quota does not allow this export | Review the app's export allowance/access; pairing and cancellation do not reset it |

## Video outline

- **Suggested title:** Your Android Health Data, Straight to Your Desktop
- **Hook:** "The CLI listens. Your phone knocks. No cloud."
- **Demo flow:** run pair → scan QR → `healthmd export` → files land in the destination folder.
- **Key screenshot/recording moments:** universal QR, in-app scanner, manual fallback, foreground-service notification, CLI output.
- **CTA / next video:** Raw API Snapshots.

## Implementation notes

The portable CLI's RFC-0005 P1 wake window keeps an unavailable export/resume/cancel request open
for 120 seconds while the user opens this screen and restarts the direct session. It is host-only,
uses no new protocol bytes, and can be disabled with `--wake-timeout 0`. The deployed P2 APNs
doorbell is Apple-only. Android FCM enrollment remains the explicit RFC-0005 P3 target, so Android
sends no new wake notification yet; the existing foreground-service notification is unchanged.
Current Play and F-Droid direct wake behavior remains wait-only until native enrollment and tap
handling are implemented and qualified. Future FCM depends on Play services; F-Droid/no-Play-services
must retain visible unavailable/wait-only degradation. Neither a doorbell nor a notification can
restart a force-stop, perform the first unlock, grant health access, approve an export, or start
unattended work. A human must reopen the app and explicitly restart a stopped direct session.

New pairing uses shared selector 3 and its domain-separated 20-digit transcript (`packages/contracts/direct-protocol/pairing-v3/`). Selector 2 remains as a high-entropy fallback for older CLIs; trusted reconnect keeps selector 2. The strict QR parser accepts only the exact in-app handoff, canonical private-LAN/Tailscale IPv4, a valid port, and exactly 20 ASCII digits. The session uses authenticated encryption with Android Keystore-backed trust, a `dataSync` foreground service (`FOREGROUND_SERVICE_DATA_SYNC`), private no-backup spools, partitioned resumable seven-day jobs, and exact artifact checksums (application protocol v2: `direct-protocol/` Kotlin + `packages/contracts/direct-protocol/v2/`). Failure states map to user copy (`CONNECTION_FAILED`, `SESSION_TIMEOUT`, `QUOTA_EXHAUSTED`, `DEVICE_LOCKED`, …). Destination strategy and topology: [Android desktop destination strategy](../android-desktop-destination.md).
