---
title: "Direct phone CLI"
description: "Pair healthmd with an iPhone or Android phone over Manual IP or Tailscale, then export without running Health.md for Mac."
---

The direct backend connects `healthmd` to an open Health.md app on iPhone or Android without routing the command through Health.md for Mac. The phone reads its platform health store — HealthKit on iPhone, Health Connect on Android — stages the result in protected storage, and transfers validated partitions to the CLI.

```text
healthmd on the computer
  <-> authenticated encrypted Manual IP, Tailscale, or supported Nearby channel
Health.md on iPhone or Android -> HealthKit / Health Connect -> protected bounded spool
  -> raw snapshots, production-generated files, or (iPhone) canonical and typed query data
```

<div class="availability preview">
<strong>Preview · portable direct CLI</strong>
<p>The bundled Swift direct backend is available on macOS and pairs with iPhone. Android pairing (protocol v2) is part of the cross-platform Rust client, an alpha awaiting physical iPhone and Android release QA and its first public package; Linux and Windows commands describe the staged workflow.</p>
</div>

## What direct mode supports

- one-time pairing and trusted reconnect with iPhone (protocol v1) or Android (protocol v2) sources;
- local trusted-device inspection and unpairing;
- live phone readiness;
- strict raw export — schema-v7 `healthmd.health_data` on iPhone, provider-native Health Connect snapshots on Android;
- selected canonical extraction (iPhone only);
- production-generated file export on both phone platforms;
- durable local job status and resume;
- explicit cancellation;
- the same-executable `healthmd mcp serve` stdio server with direct typed queries, metric catalog, evidence, MCP Apps UI, and PNG fallback (iPhone only).

The `healthmd` command's direct backend does not emulate the Mac app's encrypted-context HTTP routes, so Mac-oriented `doctor`, query, evidence, and refresh subcommands still return `backend_unsupported` rather than switching backends. Use `healthmd mcp serve` for fresh direct-iPhone typed analysis, or run `healthmd setup codex` to configure and pair Codex automatically. `healthmd mcp schema [TOOL]` prints the exact nested MCP input schema and examples locally; use `healthmd_sleep_sessions` directly for sleep rather than treating canonical `extract` output as the typed query API.

## Requirements

- A direct-capable `healthmd` binary and a matching Health.md build: iPhone (protocol v1) or Android (protocol v2). Android pairing requires the portable Rust client; the bundled macOS helper pairs with iPhone only.
- Health.md open in the foreground on the phone for pairing and new commands.
- **Settings > Mac Sync > Direct CLI Access** enabled on iPhone, or **Settings → Direct CLI** on Android.
- Platform health permission (HealthKit or Health Connect), protected data, local network permission, and export quota available.
- A reachable computer address and TCP port `17647` for Manual IP. A Tailscale address works.
- An existing absolute destination for generated-file mode.

The CLI is the listener. The phone connects to the computer address entered in Direct CLI Access.

## Transport support

| Transport | Bundled Swift helper on macOS | Portable Rust client |
|---|---:|---:|
| Manual IP on a LAN | Yes | macOS, Linux, Windows |
| Tailscale address | Yes | macOS, Linux, Windows |
| Nearby / MultipeerConnectivity | Yes | No |

Nearby uses Apple's encrypted Multipeer session plus the same Health.md application authentication and encryption used by Manual IP. The portable client returns `transport_unsupported` for Nearby.

## Pair once with Manual IP

Start the listener on the computer:

```bash
healthmd direct pair --transport manual-ip
```

The portable Rust client writes a six-digit iPhone code, a separate 20-digit Android code, candidate computer addresses, and the listener port to stderr; the bundled macOS helper prints only the six-digit iPhone code. stdout stays reserved for the final JSON result.

On iPhone:

1. Open **Health.md > Settings > Mac Sync > Direct CLI Access**.
2. Enable Direct CLI Access.
3. Select **Manual IP**.
4. Enter the computer's LAN or Tailscale address.
5. Enter port `17647`, unless the CLI uses another global `--port`.
6. Enter the pairing code and tap Pair.
7. Keep the app open until both sides report success.

iPhone pairing codes expire after 10 minutes. They are never sent over the network or persisted.

## Pair an Android phone

Android pairing uses the portable Rust client and the separate 20-digit (~66-bit) one-time code printed by `healthmd direct pair`. Android never downgrades to the iPhone protocol.

1. Open **Health.md > Settings → Direct CLI** on the Android phone.
2. Enter the computer's LAN or Tailscale address and port `17647`.
3. Enter the 20-digit code and confirm pairing.
4. Keep the app open; Android runs a visible, user-started data-sync foreground service for an active direct session.

After the one-time code is consumed, reconnect trust is Keystore-backed.

Use a different port when needed:

```bash
healthmd --port 18000 direct pair --transport manual-ip
healthmd --backend direct --port 18000 status
```

Keep using the same explicit port for later status, export, resume, and cancel commands.

## Pair with Nearby

Nearby is available only in the bundled Swift helper:

```bash
healthmd direct pair --transport nearby
```

Select Nearby in Direct CLI Access on iPhone, enter the displayed code, and keep both devices open until pairing finishes. No failed Nearby operation switches to Manual IP.

## Trusted devices

Pairing creates trust separate from the Health.md Mac app's sync relationship.

```bash
healthmd direct devices
healthmd direct unpair DEVICE_UUID
```

These commands read or modify local trust and do not contact the phone. On iPhone, use **Forget Paired CLI** to remove the other side; on Android, remove the pairing from **Settings → Direct CLI**.

When more than one phone is trusted, select the intended installation explicitly:

```bash
healthmd --backend direct --device DEVICE_UUID status
```

Use `healthmd direct reset-trust --confirm` only when local trust is corrupt or belongs to a replaced installation. It removes all local direct pairings. Forget those pairings on the phone before starting over.

## Check live readiness

```bash
healthmd --backend direct --transport manual-ip status
```

A direct status response reports connection and safety state without health values. The portable client reports the source under `source` with a `platform` of `ios` or `android`; the bundled helper exposes the `iphone` fields below. Check these fields before starting work (iPhone source shown):

| Field | Ready state |
|---|---|
| `backend` | `direct` |
| `mac_app` | `bypassed` |
| `direct_cli.paired` | `true` |
| `iphone.connected` | `true` |
| `iphone.app_active` | `true` for new work |
| `iphone.protected_data_available` | `true` |
| `iphone.can_trigger_raw_exports` | `true` for raw and extract |
| `iphone.can_trigger_exports` | `true` for generated files |

The direct status destination remains unselected. File mode uses only the explicit `--destination` supplied to the command.

An Android source reports `platform: "android"` with `app_active`, `protected_data_available`, `export_in_progress`, and its available raw products instead of the iPhone trigger flags.

## Strict raw export (iPhone)

Choose one range selector:

```bash
healthmd --backend direct export --yesterday --raw --output yesterday.json
healthmd --backend direct export --last 7 --raw --output week.json
healthmd --backend direct export \
  --from 2026-07-01 --to 2026-07-07 --raw --output range.json
healthmd --backend direct export --all --raw --output complete-health-corpus.json
```

Omit `--output` to stream validated JSON to stdout. An output file is safer for sensitive or large responses.

iPhone strict raw returns `healthmd.raw_result` v1 containing ordinary schema-v7 `healthmd.health_data` days and their canonical source archives. It temporarily requests lossless detail without changing saved iPhone settings. The CLI validates the exact dates, profile, schema, archive, manifests, digest chain, final body digest, and completion state before exposing the result.

A complete-empty day is successful. Missing, partial, failed, cancelled, unsupported, or skipped requested data produces `partial_success` and a nonzero exit unless `--allow-partial` is explicit.

## Provider-native raw export (Android)

The portable Rust client is direct by default, so Android raw commands omit the `--backend` flag:

```bash
healthmd export --last 7 --raw --provider health_connect \
  --raw-format ndjson --output health-connect.ndjson
```

`--provider` names one explicit provider and defaults to `health_connect`. `--raw-format` defaults to NDJSON, the recommended shape for large snapshots; in-memory JSON validation is capped at 64 MiB. Metric selection supports `--metric` and `--all-metrics`, but not canonical or generated-file selectors — those remain iPhone capabilities.

Android raw snapshots keep their Health Connect provider-native contract. They are never converted into HealthKit-shaped `healthmd.health_data` days, and related-but-different statistics keep their own identities.

## Canonical extraction

Direct extraction uses the same durable raw transport but returns selected source-shaped data instead of the transport wrapper. It is an iPhone capability:

```bash
healthmd --backend direct extract \
  --category Sleep --last 7 --output sleep.json

healthmd --backend direct extract \
  --metric workouts --last 14 --object records \
  --detail lossless --output workout-records.json
```

Metric, category, source, and detail selection reaches iPhone before HealthKit reads. See [Canonical extraction](/docs/cli-extract/) for object selectors, JSON Pointers, JSONL, and receipts.

## Production-generated files

Direct file mode asks the phone to run Health.md's production exporters, then transfers the resulting files to an explicit computer destination.

```bash
mkdir -p "$HOME/Documents/HealthVault"

healthmd --backend direct export --yesterday \
  --destination "$HOME/Documents/HealthVault"

healthmd --backend direct export --last 7 \
  --category Sleep --detail summary \
  --destination "$HOME/Documents/HealthVault"

healthmd --backend direct export --yesterday --use-iphone-settings \
  --destination "$HOME/Documents/HealthVault"
```

The destination must already exist, be absolute, and not resolve through a symlink. Direct mode never guesses or uses a Mac app bookmark. `--output` is for raw or extraction output; `--destination` is for generated files.

By default, a request keeps saved formats, Health subfolder, filenames, templates, write mode, Daily Note Injection, and Daily Notes Only. It suppresses roll-ups and summary-only mode for that job. Repeatable `--metric` or `--category` options plus `--detail` replace only the job's metric and detail scope. `--use-iphone-settings` mirrors all saved settings and cannot combine with selectors.

The iPhone can stage JSON, CSV, Markdown, ZIP, data dictionaries, roll-ups, individual records, daily notes, and provider sidecars. The CLI validates each relative path, byte count, digest, file manifest, destination identity, and request fingerprint before committing. It rejects traversal, symlink ancestors, root mutation, path collisions, and digest changes. Overwrite is atomic. Append and Markdown merge use persisted plans so a replay does not duplicate content.

Generated-file destinations work on macOS and Linux for iPhone protocol v1, which rejects them on Windows. Android protocol v2 commits file destinations on every CLI operating system — macOS, Linux, and Windows — and caps each generated job at 4,096 files.

Android protocol v2 file jobs take their scope from the device's saved export selections or from `--profile PROFILE_ID`; the profile owns the frozen settings and destination. CLI metric, category, and detail selectors are rejected for Android file jobs.

## Foreground and background behavior

Pairing and new work require the phone app in the foreground. Direct CLI Access does not turn the phone into a headless export server and cannot wake the app on demand.

On iPhone, if an export is already connected when the app moves to the background, Health.md requests finite iOS background execution time. The export may finish during that allowance. If iOS expires the allowance, the connection closes and the durable job pauses. Reopen Health.md and resume the same job.

On Android, an active direct session runs a visible, user-started data-sync foreground service. Keep the app in the foreground for pairing and new work.

On iPhone, a global activity banner during direct work includes capture and transfer phase, completed days, byte progress, and paused or completed status without displaying health values.

## Durable resume and cancel

Direct jobs expire seven days after creation. Timeout, Ctrl-C, process death, disconnect, and background expiration do not cancel them.

```bash
healthmd --backend direct status --job JOB_UUID
healthmd --backend direct resume JOB_UUID --timeout 300 --output recovered.json
healthmd --backend direct cancel JOB_UUID
```

Resume keeps the original dates, settings, destination, request fingerprint, device, and partition frontier. You cannot point a file job at a different destination during resume.

Cancel records a durable request, but cancellation becomes terminal only after the iPhone acknowledges it. If the iPhone is unavailable, status remains `cancellation_pending`. Reopen the same iPhone and retry cancel.

## Security model

- Pairing uses ephemeral key agreement and transcript proofs bound to the platform pairing code — the six-digit iPhone flow or the separate high-entropy 20-digit (~66-bit) Android one-time code.
- Reconnect proves a random stored secret and both installation identities.
- Each connection derives fresh keys and nonces.
- Messages and binary frames use ChaCha20-Poly1305 with monotonic sequence checks.
- Partitions use SHA-256 manifests and a chained digest frontier.
- iPhone trust is stored in Keychain; Android reconnect trust is Keystore-backed.
- Portable trust uses Keychain, Secret Service, or Windows Credential Manager and never falls back to plaintext.
- Spools and journals use private application storage and exclude backups where the platform supports it.

Manual IP remains encrypted on a local network or Tailscale. Tailscale protects the network path too, but it does not replace Health.md's application authentication.

## Common errors

| Error | Action |
|---|---|
| `direct_not_paired` | Pair this CLI installation with iPhone. |
| `direct_device_selection_required` | Pass the intended trusted `--device`. |
| `direct_trust_invalid` | Preserve diagnostics. Reset trust only when recovery is impossible. |
| `direct_iphone_unavailable` | Check app foreground state, access toggle, address, port, permission, and LAN or Tailscale reachability. |
| `direct_export_paused` | Inspect the job, reopen iPhone, and resume it. |
| `direct_cancellation_pending` | Reopen the paired iPhone and retry cancel. |
| `transport_unsupported` | Use Manual IP or Tailscale in the portable client. |
| `backend_unsupported` | Use the Mac app backend for query, evidence, doctor, metrics, or MCP. |
| `invalid_direct_raw_response` | Do not consume the output. Keep validation diagnostics. |
| `invalid_direct_file_receipt` | Do not repair files manually. Inspect and resume the job. |
| `job_expired` | The seven-day state lifetime ended. Confirm before starting new work. |

## Related

<div class="related">
  <a href="/docs/cli/"><span>Overview</span>Health.md CLI: install the bundled helpers and choose the right backend.</a>
  <a href="/docs/android/"><span>Android</span>Health.md for Android: Health Connect sources, folder destinations, and on-device automation.</a>
  <a href="/docs/cli-extract/"><span>Data</span>Canonical extraction: select and emit source-shaped Health.md data (iPhone).</a>
  <a href="/docs/cli-jobs/"><span>Reliability</span>Durable jobs and automation: resume, cancel, partial results, and scripting.</a>
  <a href="/docs/reference/connected-mac-iphone-protocol/"><span>Protocol</span>Connected Mac and iPhone reference: capabilities, bounded transfer, and result states.</a>
</div>
