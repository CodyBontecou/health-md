# Direct CLI

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** Settings → Direct CLI
- **Source files:** `app/src/main/java/com/healthmd/presentation/directcli/DirectCliScreen.kt`, `direct-protocol/src/main/kotlin/com/healthmd/direct/protocol/`, `docs/android-desktop-destination.md`

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
| Device locked error | Phone locked mid-session | Unlock and reconnect |
| Quota exhausted | Transfer quota for the pairing used up | Cancel/resume or re-pair |

## Video outline

- **Suggested title:** Your Android Health Data, Straight to Your Desktop
- **Hook:** "The CLI listens. Your phone knocks. No cloud."
- **Demo flow:** run pair → scan QR → `healthmd export` → files land in the destination folder.
- **Key screenshot/recording moments:** universal QR, in-app scanner, manual fallback, foreground-service notification, CLI output.
- **CTA / next video:** Raw API Snapshots.

## Implementation notes

The gated Android-v6 successor store verifies retained artifact and partition SHA-256 digests before recovery or accepted-lease admission and before terminal accounting/completion. It streams each artifact through a fixed 128 KiB buffer, including zero-length artifacts, and rejects same-length corruption or contradictory stored digests. Invalid expired successor spools remain intact for inspection; unexpired spools are not fully read during unrelated expiry scans. Lightweight per-frame ownership checks remain unchanged. This does not qualify complete production successor admission, OS-kill/power-loss recovery or mutation after a lease was admitted; the receiver still validates transferred bytes. Historical stores, public export profiles and protocol/journal grammar are unchanged.

The portable CLI's RFC-0005 P1 wake window keeps an unavailable export/resume/cancel request open
for 120 seconds while the user opens this screen and restarts the direct session. It is host-only,
uses no new protocol bytes, and can be disabled with `--wake-timeout 0`. The deployed P2 APNs
doorbell is Apple-only. Android FCM enrollment remains the explicit RFC-0005 P3 target, so Android
sends no new wake notification yet; the existing foreground-service notification is unchanged.

New pairing uses shared selector 3 and its domain-separated 20-digit transcript (`packages/contracts/direct-protocol/pairing-v3/`). Selector 2 remains as a high-entropy fallback for older CLIs; trusted reconnect keeps selector 2. The strict QR parser accepts only the exact in-app handoff, canonical private-LAN/Tailscale IPv4, a valid port, and exactly 20 ASCII digits. The session uses authenticated encryption with Android Keystore-backed trust, a `dataSync` foreground service (`FOREGROUND_SERVICE_DATA_SYNC`), private no-backup spools, partitioned resumable seven-day jobs, and exact artifact checksums (application protocol v2: `direct-protocol/` Kotlin + `packages/contracts/direct-protocol/v2/`). Failure states map to user copy (`CONNECTION_FAILED`, `SESSION_TIMEOUT`, `QUOTA_EXHAUSTED`, `DEVICE_LOCKED`, …). Destination strategy and topology: [Android desktop destination strategy](../android-desktop-destination.md).

### Versioned recovery storage

Recognized historical v4/v5 jobs retain the existing private `direct-cli/jobs` location. Explicit, complete Android-v6 authority selects the sibling `jobs-sleep-attribution-v6` store. A shared coordination lock remains outside both purge roots, and live preparation/accepted leases retain their namespace. Duplicate IDs, misplaced authority and incomplete successor pins cannot select or migrate an operation. Looking up a missing job creates no job directories or ownership state. Current **Forget paired CLI** cleanup covers both stores.

Successor expiry requires recognized current metadata and ownership, the existing generated-files v1 transfer envelope, matching peer/request/session identity, complete partition coverage and contained regular artifact files. Unknown, unreadable, misplaced or incomplete recovery state is retained rather than deleted using its filesystem age; **Forget paired CLI** explicitly removes that state. Expiry synchronizes directory changes before inspection and after removal; a retry also synchronizes an empty root after an uncertain removal. Recursive cleanup unlinks symlinks without following their targets.

This storage support does not enable Morning ends capture or advertise new Direct products. The setting remains unavailable in production pending Issue #104 acceptance. Journal/protocol grammars and historical profile meanings are unchanged. Full process-death, power-loss, downgrade, provider, live CLI and user-flow acceptance remain required.
