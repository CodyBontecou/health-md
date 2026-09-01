# Android Desktop Destination Strategy

## Decision

Android supports an explicit, encrypted connection to the standalone Health.md CLI as an additional
manual export path. The existing Storage Access Framework (SAF) folder and HTTPS API destinations
remain unchanged.

The topology is:

```text
healthmd CLI on macOS, Linux, or Windows
    listens on TCP 17647
          ↑ authenticated encrypted connection
open Health.md Android app
    reads the selected provider and streams validated artifacts
```

The CLI is not embedded in the APK. Android connects outbound after a visible user action.

## Products

The first Android application-protocol-v2 release supports:

- provider-native `healthmd.raw-snapshot` v1 JSON or NDJSON;
- production-generated Markdown, JSON, CSV, and Obsidian Bases files, capped at 4,096 destination files per job;
- pairing, reconnect, status, cancellation, seven-day durable jobs, and partition resume.

Fitbit raw snapshots require an explicit range of at most 366 days because its native intraday endpoints are day-scoped; larger ranges and `--all` are rejected before provider reads. Android raw snapshots retain the authoritative provider-native contract under
`docs/export-contract/raw-snapshot-v1.md`; they are never relabeled as the iOS canonical raw format.
The desktop CLI applies append and Markdown merge policies against the desktop destination.

Canonical `healthmd extract` projections remain an iOS application-protocol-v1 feature until the
separate Android daily-record product is enabled.

## User flow

1. Run `healthmd direct pair` on the computer.
2. Open **Settings → Direct CLI** in the Android app.
3. Enter the displayed computer address, port, and 20-digit Android pairing code.
4. For each command, start the CLI command first and tap **Connect** in Android.

Examples:

```bash
healthmd export --raw --yesterday --provider health_connect --raw-format ndjson \
  --output health-connect.ndjson

healthmd export --yesterday --destination "$HOME/Documents/HealthVault"
```

## Security and lifecycle

- The deployed X25519/HMAC/ChaCha20-Poly1305 pairing and transport are reused.
- The reconnect secret is encrypted by an Android Keystore AES-GCM key.
- Trust, jobs, and health artifacts live under `noBackupFilesDir/direct-cli/`.
- The absolute desktop path never leaves the CLI; Android receives an opaque destination binding.
- Raw and generated artifacts are locally validated before transfer and checked again by the CLI.
- A raw artifact is preserved for resume and never regenerated under the same accepted job ID.
- Health bytes are deleted on cancellation, forget, or seven-day expiry. A completed job retains its exact bounded artifact until expiry so a lost final confirmation can replay without rereading a non-transactional provider.
- The connection runs only in an explicit `dataSync` foreground service with a notification and
  Disconnect action.
- Direct CLI is not a WorkManager destination, schedule target, automation target, boot service, or
  always-on reconnect loop.
- No health values, credentials, provider payloads, or desktop paths are logged or placed in
  notifications.

## Automated UI and transport gate

`DirectCliScreenTest` provides hermetic Compose coverage for unpaired validation, paired endpoint
controls, connect/disconnect/forget actions, and health-free progress/error states. It runs as part
of `:app:connectedPlayDebugAndroidTest` and `:app:connectedFdroidDebugAndroidTest`.

The opt-in live gate uses a separate `com.healthmd.android.e2e` build so Android Keystore trust,
DataStore, jobs, and spools cannot collide with the installed app. From the repository root:

```bash
ANDROID_SERIAL=2C061FDH200CJN \
HEALTHMD_ANDROID_E2E_HOST=<reachable-computer-address> \
  apps/android/scripts/run-direct-cli-ui-e2e.sh
```

The script runs the ignored Rust listener
`accepts_android_ui_pair_reconnect_disconnect_status_and_repair` concurrently with
`DirectCliLiveE2ETest`. It verifies Settings navigation, wrong-code rejection, pairing, trusted
reconnect, the foreground notification and its Disconnect action, v2 status, forget, and code-based
re-pair. No export request or health payload is created. The isolated APK is uninstalled in cleanup
even when the test fails.

## Destination matrix

| Destination | Android status |
|---|---|
| Local device/provider folder | Supported via SAF |
| User-configured HTTPS endpoint | Supported |
| Standalone desktop CLI | Supported for manual encrypted sessions |
| Scheduled Direct CLI export | Not supported |
| mDNS/automatic LAN discovery | Not supported; manual IP/Tailscale only |
