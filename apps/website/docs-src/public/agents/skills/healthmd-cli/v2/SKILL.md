---
name: healthmd-cli
description: Install and operate the standalone Health.md CLI and portable healthmd-mcp server on macOS, Linux, or Windows. Use when a user wants to pair an iPhone, configure Codex/Claude MCP, check direct readiness, query or chart typed health data, export Apple Health data, extract canonical JSON, manage durable jobs, automate safe runs, or troubleshoot machine-readable errors. This skill is for users, not Health.md developers.
compatibility: Requires the standalone `healthmd`/`healthmd-mcp` package and a current Health.md iPhone app. Fresh work requires Health.md foreground with Direct CLI Access enabled. Manual IP/Tailscale and validated generated-file destinations work on macOS, Linux, and Windows.
---

# Health.md CLI User Guide

The standalone CLI connects directly to iPhone. The Health.md macOS app is not required.

```text
healthmd on macOS / Linux / Windows
  ← authenticated encrypted Manual IP or Tailscale connection →
open Health.md iPhone app → HealthKit → protected spool
  → validated canonical JSON or production-generated files
```

The CLI listens on the computer; iPhone connects to the address entered in Direct CLI Access. HealthKit reads always happen on iPhone. The CLI cannot wake iOS reliably or bypass app activity, protected-data, permission, local-network, or quota controls.

Direct is the portable default. Do not add `--backend mac-app`: that adapter is reserved but unimplemented. The portable client supports Manual IP, including Tailscale addresses. Nearby is unsupported.

No public CLI/mobile pair is qualified yet. The source snapshot tagged for the `0.1.0-alpha.2`
preview contains iOS 3.2.1 (build 202608300209) and Android 1.8.1 (`versionCode 30`) as its exact
mobile counterparts. The unqualified compatibility floors remain iOS 3.0.3 for v1 exports and v3
typed queries and Android 1.5.4 (`versionCode 25`) for v2 exports. Android typed queries are not
implemented. Treat protocol implementation and those floors as distinct from release qualification;
do not claim store-build compatibility until the checked-in ledger names an exact tested pair.

## Bounded commands

On macOS/Linux, run the unfamiliar CLI non-interactively:

```bash
NO_COLOR=1 TERM=dumb timeout 15 healthmd --version </dev/null
NO_COLOR=1 TERM=dumb timeout 30 healthmd direct devices </dev/null
NO_COLOR=1 TERM=dumb timeout 30 healthmd status </dev/null
NO_COLOR=1 TERM=dumb timeout 300 healthmd export --last 7 --raw --output week.json </dev/null
```

On Windows, use the automation host's process timeout. Pairing needs enough time for the user to scan the QR with Health.md's in-app Direct CLI scanner or enter the fallback code on iPhone.

## Install or verify

The checksummed `0.1.0-alpha.2` public preview is available from the project Homebrew/Linuxbrew
tap. It remains an explicitly unqualified preview: publishing the CLI does **not** qualify a
portable CLI/mobile pair, and users must use the exact matching mobile build named by release
evidence.

```bash
brew install CodyBontecou/tap/healthmd
healthmd --version
healthmd --help
```

The formula installs `healthmd` and the matching `healthmd-mcp` compatibility launcher together.
Do not mix versions. Authorized preview testers who cannot use Homebrew may build the exact release
tag from source:

```bash
git clone https://github.com/CodyBontecou/health-md.git
cd health-md
git checkout healthmd-cli/v0.1.0-alpha.2
cd apps/cli
cargo install --locked --path crates/healthmd-cli
```

Do not install the old helper from the Mac app or use the monorepo's `apps/apple/scripts/healthmd`
wrapper for portable operation; those target the Swift compatibility client. Linux requires an
unlocked freedesktop Secret Service provider such as GNOME Keyring or KWallet. The CLI never falls
back to plaintext credentials.

## Pair once

```bash
NO_COLOR=1 TERM=dumb timeout 180 healthmd direct pair </dev/null
```

While it waits:

1. In foreground Health.md, open **Sync → Direct CLI Access**, tap **Scan Pairing QR**, and scan the displayed image. That in-app scan starts pairing automatically; do not ask for a second Pair tap or open the QR as a custom URL.
2. Keep Health.md foregrounded until stdout returns `healthmd.direct_pairing_result` with `status: success` for the intended iPhone.
3. If in-app scanning is unavailable, open **Sync → Direct CLI Access**, enable **Manual IP**, and enter the printed LAN/Tailscale address, port, and six-digit code.

The default port is `17647`. If another port is saved on iPhone, pass it globally on every network command:

```bash
healthmd --port 18000 status
healthmd --port 18000 export --yesterday --raw --output yesterday.json
```

Pairing is one-time. Leave Direct CLI Access enabled and Health.md open for later commands. Use `--device DEVICE_UUID` when multiple iPhones are trusted.

Local trust commands do not contact iPhone:

```bash
healthmd direct devices
healthmd direct unpair DEVICE_UUID
```

Use `healthmd direct reset-trust --confirm` only to recover unusable local trust. It removes every local pairing; forget the paired CLI on each iPhone too.

## Check readiness

```bash
NO_COLOR=1 TERM=dumb timeout 30 healthmd status </dev/null
```

Read the JSON:

- `backend == "direct"` and `mac_app == "bypassed"`: standalone path is active.
- `iphone.connected == true`: the intended iPhone authenticated.
- `iphone.app_active == true`: new work can begin.
- `iphone.protected_data_available == true`: protected export data is accessible.
- `iphone.can_trigger_raw_exports == true`: raw and extract are ready.
- `iphone.can_trigger_exports == true`: generated files are ready.
- `iphone.active_job_id`: another job may already own the service.
- `direct_cli.paired == true`: direct trust exists.

The direct status `destination` is intentionally unselected. File mode uses the explicit `--destination`; it never uses a Mac app bookmark.

## Strict raw export

Choose exactly one range: `--yesterday`, `--last N`, `--from/--to`, or `--all`.

```bash
healthmd export --yesterday --raw --output yesterday.json
healthmd export --last 7 --raw --output week.json
healthmd export --from 2026-07-01 --to 2026-07-07 --raw --output range.json
healthmd export --all --raw --output complete-health-corpus.json
```

Without `--output`, validated health JSON streams to stdout. Prefer a protected output file. Strict raw returns `healthmd.raw_result` v1 with public schema-v7 `healthmd.health_data` documents and temporarily requests lossless records without changing saved iPhone settings.

Complete-empty is success. Missing, failed, cancelled, unsupported, skipped, or partial capture yields `partial_success` and a nonzero exit unless `--allow-partial` is explicit. That flag changes only exit status; diagnostics remain.

## Canonical extraction

Use `extract` for selected health objects:

```bash
healthmd extract --category Sleep --last 7 --output sleep.json
healthmd extract --metric workouts --last 14 --object workouts --output workouts.json
healthmd extract --metric workouts --last 14 \
  --object records --detail lossless --output workout-records.json
healthmd extract --category Sleep --last 7 --format jsonl --output sleep.jsonl
```

Extraction requires `--metric`, `--category`, a category-implying `--object`, or `--all-metrics`. Repeatable `--object` and `--field /JSON/POINTER` narrow output. Summary is default; archive/record selectors imply lossless. The canonical source is currently `apple_health` only.

JSON returns canonical documents or honest projections plus a receipt. JSONL writes its receipt to stderr, or `OUTPUT.receipt.json` with `--output`. Never interpret omitted fields as zero. Incomplete extraction emits no retained data unless `--allow-partial` is explicit.

## Production-generated files

On macOS, Linux, or Windows, use an existing absolute non-symlink destination:

```bash
mkdir -p "$HOME/Documents/HealthVault"
healthmd export --yesterday --destination "$HOME/Documents/HealthVault"
healthmd export --last 7 --category Sleep --detail summary \
  --destination "$HOME/Documents/HealthVault"
healthmd export --yesterday --use-iphone-settings \
  --destination "$HOME/Documents/HealthVault"
```

The iPhone uses production JSON/CSV/Markdown/ZIP/data-dictionary/roll-up/individual-record/Daily Note/provider exporters. The CLI validates manifests, digests, paths, symlinks, destination identity, and restart-safe overwrite/append/Markdown merge commits.

Default requested-date jobs keep saved formats, subfolder, templates, filenames, write mode, and Daily Note behavior while suppressing roll-ups and summary-only mode. Metric/category/detail selectors replace only that job's acquisition scope. `--use-iphone-settings` mirrors all saved behavior and cannot combine with selectors.

`--profile PROFILE_ID` runs a saved iPhone export profile by its stable UUID: the profile's frozen settings and destination replace both live settings and per-job selectors. It cannot combine with `--use-iphone-settings` or metric/category selectors; an unknown UUID fails with a typed `profile_not_found` error and never falls back to live settings. Read the UUID from the app's Export tab profile picker (`healthmd profiles list` is planned, not shipped):

```bash
healthmd export --last 7 --profile 11111111-2222-4333-8444-555555555555 \
  --destination "$HOME/Documents/HealthVault"
```

The equivalent MCP generated-file export arguments are `settings_policy: "profile"` plus `profile_reference: { "profileID": UUID }` under the same scope-exclusivity rules.

Protocol v1 treats the destination as an opaque immutable label on iPhone. The receiving host validates and durably binds the native absolute path before sending the request.

## Codex and Claude MCP

For Codex, run `healthmd setup codex`. It safely preserves unrelated Codex settings, configures the absolute `healthmd` executable with arguments `mcp serve`, applies approval prompts to export mutations, and opens iPhone pairing when needed. Pairing and MCP deliberately use the same installed executable identity so native credentials never require a second Keychain ACL. `healthmd-mcp` remains a compatibility launcher that delegates to the sibling `healthmd`. Do not run MCP serve mode as an interactive shell command.

The complete server exposes 19 fixed tools for local pairing, direct readiness, Apple metric catalog, bounded typed queries, charts, sleep, workouts, comparison, coverage, evidence, and durable generated-file exports. Every query runs against the paired foreground iPhone; Health.md for Mac is not involved. Export, resume, and cancel calls require explicit user approval and an export needs an existing `destination`.

For a local host that should receive no pairing or filesystem-export authority, pair first with `healthmd direct pair`, then configure its absolute `healthmd` executable with arguments `mcp serve-read-only`. This cloud-free stdio entry exposes only the 13 readiness/query tools, omits the pairing resource, and rejects guessed pairing/export-job calls. Keep using `healthmd mcp serve` when in-host QR pairing or generated-file export tools are intentionally required.

MCP Apps hosts negotiate `io.modelcontextprotocol/ui` and `text/html;profile=mcp-app` for self-contained query views and the local-only inline pairing QR card. Text/image hosts retain authoritative JSON and native PNG fallbacks; they may place pairing images inside a collapsible tool result. Call `healthmd_doctor` first. Use `all_pages: true` for bounded automatic cursor traversal, or continue opaque cursors manually.

Use the fixed typed operation directly for analysis: `healthmd_sleep_sessions` for sleep, `healthmd_workouts` for workouts, and `healthmd_metric_chart` for metric series. `tools/list` supplies complete nested selectors and examples. The shell can run the identical operation as `healthmd query TOOL_NAME --arguments 'JSON_OBJECT'`; its canonical payload matches MCP before the MCP content envelope is added. Never substitute `healthmd extract`, which returns a different canonical source-data projection. `healthmd mcp schema TOOL_NAME` prints the generated shared schema without credentials, a listener, or iPhone access.

## Durable jobs

Jobs persist for seven days. Timeout, Ctrl-C, process exit, network loss, or exhausted iOS background time does not cancel them.

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300 --output recovered.json
healthmd resume JOB_UUID --format jsonl --output recovered.jsonl
healthmd cancel JOB_UUID
```

Job status is local. Resume reconnects the same paired iPhone and exact immutable request. Never start a duplicate after an unknown outcome; inspect the job first. Only iPhone acknowledgement makes cancellation terminal. If cancellation is pending, reopen the same iPhone and retry cancel.

## Report results safely

Commands and failures use JSON on stdout except explicit health streams/output artifacts. Pairing instructions and health-free progress may use stderr. Parse JSON/artifacts, not prose or exit status alone.

Report only status, job ID, requested/retained days, file count and explicit destination, schema/selection, missing or partial diagnostics, and error/message. Do not paste health values, routes, clinical content, or raw records unless explicitly requested. With `--output`, inspect only minimal receipt/count fields.

## Troubleshooting

| Error | Next action |
|---|---|
| `direct_not_paired` | Run `healthmd direct pair`; no Mac app is involved. |
| `direct_device_selection_required` | Select the intended trusted iPhone with `--device`. |
| `direct_device_not_paired` | List devices or pair the selected installation. |
| `direct_trust_invalid` | Preserve diagnostics; reset trust only explicitly, then forget it on iPhone. |
| `direct_storage_unavailable` | Restore native credential/state storage. On macOS authorize the installed signed binary in Keychain Access or explicitly remove stale Health.md direct trust on both sides and re-pair; the CLI fails promptly instead of waiting on hidden authorization UI. On Linux unlock Secret Service. |
| `direct_iphone_unavailable` | Check foreground app, Direct CLI Access, address/port, local-network permission, and LAN/Tailscale reachability. |
| `direct_export_paused` | Run `status --job`, reopen iPhone, and resume the same job. |
| `query_scope_too_large` | Partition dates or metric IDs across MCP calls; do not treat it as missing health data. |
| `direct_cancellation_pending` | Reopen iPhone and retry cancel until acknowledged. |
| `job_not_found` / `job_expired` | Local state is absent or past the fixed seven-day lifetime. Confirm before starting anew. |
| `invalid_direct_raw_response` | Do not consume output; retain validation diagnostics. |
| `invalid_direct_file_receipt` | Do not manually append/merge; inspect and resume the durable job if allowed. |
| `partial_canonical_extraction` | Review diagnostics; use `--allow-partial` only if incomplete data is accepted. |
| `transport_unsupported` | Use Manual IP with LAN/Tailscale, not Nearby. |
| `not_implemented` with `mac-app` | Remove the backend option; direct is default. |
| `invalid_request` | Correct date, selector, output, destination, or option combinations before retrying. |

## Privacy

- The Health.md Mac app does not need to be installed or running.
- Keep iPhone Health.md open to pair or start work. An active export may continue during finite iOS background time, then pause for resume.
- Treat paired trust as export authority and remove it when no longer needed.
- Do not call this fully headless cron automation; iOS availability still matters.
- Protect CLI state, outputs, receipts, and destinations as health data.
- Never log payloads or edit generated files to repair failed exports; resume or rerun through Health.md.
