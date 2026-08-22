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
3. Enter the **Computer address**, **Port**, and the **20-digit Android pairing code** the CLI prints, then tap **Pair with CLI**.

## Prerequisites

- The `healthmd` CLI installed on the computer (listens on TCP 17647 by default)
- Phone and computer on the same network, or reach each other via Tailscale
- Android 9 / API 28+

## Setup

1. Run `healthmd direct pair` on the computer and note the code + address.
2. Enter them in the app and pair.
3. For each transfer, start the CLI command first, then tap **Connect** in the app. Save addresses you reuse with **Save address**.

## Example output

```bash
healthmd export --raw --yesterday --provider health_connect --raw-format ndjson
healthmd export --yesterday --destination "$HOME/Documents/HealthVault"
```

A visible data-sync notification ("Waiting for Health.md CLI" → transfer progress) runs during the session.

## Tips

- **Connect** is per-command: the CLI must be waiting before you tap Connect.
- Transfers are resumable for up to seven days; artifacts spool in private no-backup storage and are deleted sooner if you cancel, disconnect, or **Forget paired CLI**.
- Fitbit raw snapshots are capped at a 366-day explicit range (day-scoped intraday endpoints); `--all` is rejected before reads.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Connection failed | Wrong address/port or different network | Verify the CLI's printed address; check LAN/Tailscale reachability |
| Pairing rejected | Wrong or expired 20-digit code | Re-run `healthmd direct pair` and re-enter |
| Device locked error | Phone locked mid-session | Unlock and reconnect |
| Quota exhausted | Transfer quota for the pairing used up | Cancel/resume or re-pair |

## Video outline

- **Suggested title:** Your Android Health Data, Straight to Your Desktop
- **Hook:** "The CLI listens. Your phone knocks. No cloud."
- **Demo flow:** run pair → enter code → `healthmd export` → files land in the destination folder.
- **Key screenshot/recording moments:** pairing form, foreground-service notification, CLI output.
- **CTA / next video:** Raw API Snapshots.

## Implementation notes

`DirectConnection` normalizes the pairing code to 20 digits (`require(normalizedCode.length == 20 || reconnect != null)`). The session uses authenticated encryption with Android Keystore-backed trust, a `dataSync` foreground service (`FOREGROUND_SERVICE_DATA_SYNC`), private no-backup spools, partitioned resumable seven-day jobs, and exact artifact checksums (protocol v2: `direct-protocol/` Kotlin + `packages/contracts/direct-protocol/v2/`). Failure states map to user copy (`CONNECTION_FAILED`, `SESSION_TIMEOUT`, `QUOTA_EXHAUSTED`, `DEVICE_LOCKED`, …). Destination strategy and topology: [Android desktop destination strategy](../android-desktop-destination.md).
