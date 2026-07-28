# Health.md CLI

Standalone, cross-platform command-line access to health exports prepared by the Health.md iOS
or Android app.

> **Status:** `0.1.0-alpha.1`. Deployed iOS application protocol v1 and Android application
> protocol v2 are implemented with automated Swift↔Rust and Kotlin↔Rust compatibility gates.
> Complete physical-device release QA is still required before the first public release.

## How it works

The CLI never reads HealthKit or Health Connect. Keep Health.md open on the source device; the app
reads platform health data and connects outbound to the CLI over an explicit LAN or Tailscale
address.

```text
healthmd on macOS / Linux / Windows
  <- authenticated, encrypted Manual IP or Tailscale connection ->
open Health.md iOS or Android app -> platform health provider -> private bounded export spool
```

Manual IP is portable. Apple's MultipeerConnectivity-based Nearby transport remains available only
in the legacy Swift client. No command silently falls back to another backend or transport.

## Platform support

| Capability | macOS | Linux | Windows |
|---|---:|---:|---:|
| Pair, devices, unpair, live status | Yes | Yes | Yes |
| iOS canonical raw export and extract | Yes | Yes | Yes |
| Android provider-native JSON/NDJSON raw export | Yes | Yes | Yes |
| Durable status, resume, cancellation | Yes | Yes | Yes |
| Generated-file destination commits | Yes | Yes | Yes |
| Manual IP / Tailscale | Yes | Yes | Yes |
| Nearby / MultipeerConnectivity | No | No | No |

iOS protocol v1 and Android protocol v2 bind the destination path as opaque request state while the
receiving CLI validates it as an existing absolute non-symlink directory under the host OS. Android
v2 has a 4,096-file limit per generated job. Android raw snapshots retain their provider-native
contract rather than being converted to HealthKit-shaped data. Use NDJSON for large snapshots;
in-memory JSON validation is capped at 64 MiB.

## Installation

Checksummed archives and direct installers become available when the first GitHub release is
published. Homebrew formula publishing begins with the first stable (non-prerelease) release:

```bash
# macOS or Linux with Homebrew/Linuxbrew, after the first stable release
brew install CodyBontecou/tap/healthmd

# Rust users on macOS, Linux, or Windows
cargo install healthmd-cli --locked
```

PowerShell installer and checksummed `.zip`/`.tar.xz` archives for Windows, Linux, and macOS are
attached to each release. Rust users can also install a published version from crates.io:

```bash
cargo install healthmd-cli --locked
# Or use the matching prebuilt GitHub archive after installing cargo-binstall:
cargo binstall healthmd-cli
```

Until the first release, build from the monorepo source:

```bash
git clone https://github.com/CodyBontecou/health-md.git
cd health-md/apps/cli
cargo install --path crates/healthmd-cli
```

Prebuilt archives use `healthmd-cli/v<version>` tags. Do not use the repository-wide
`/releases/latest` URL because the Health.md monorepo reserves that release pointer for the Apple apps.

## Pair a mobile source

1. Run:

   ```bash
   healthmd direct pair
   ```

2. Keep the command running. Its iOS code, high-entropy 20-digit Android code, listener addresses,
   and port are printed to stderr.
3. On iOS, open **Direct CLI Access** in the Mac destination settings. On Android, open
   **Settings → Direct CLI**. Enter the computer's LAN/Tailscale address, port, and matching
   platform code, then pair.
4. The final machine-readable pairing result is written to stdout.

Trust is stored in Keychain, Secret Service, or Windows Credential Manager. Pairing is distinct from
the Health.md Mac app's sync trust. Linux requires an unlocked freedesktop Secret Service provider
such as GNOME Keyring or KWallet; configure one explicitly on headless hosts. The CLI fails closed
instead of storing reconnect credentials in plaintext when that service is unavailable.

On macOS, credential operations never wait indefinitely for authorization UI from a background
worker. An inaccessible item returns `direct_storage_unavailable` promptly. Use Keychain Access to
allow the installed, stably signed `healthmd` binary. If a development/legacy item cannot be repaired,
delete only the `com.codybontecou.obsidianhealth.direct-cli-trust` item, forget that pairing on the
mobile source, and pair again; never copy the secret into a file or shell command.

## Commands

```bash
# Readiness and local trust
healthmd status
healthmd direct devices

# Platform-native raw export; omit --output to stream validated JSON/NDJSON to stdout
healthmd export --yesterday --raw --output yesterday.json
healthmd export --last 7 --raw --output week.json
healthmd export --from 2026-07-01 --to 2026-07-07 --raw
healthmd export --all --raw --output complete-health-corpus.json

# Android raw options
healthmd export --last 7 --raw --provider health_connect --raw-format ndjson \
  --output health-connect.ndjson

# Scoped canonical extraction (iOS v1)
healthmd extract --category Sleep --last 7 --output sleep.json
healthmd extract --metric workouts --last 14 --object records \
  --detail lossless --output workout-records.json
healthmd extract --category Sleep --last 7 --format jsonl --output sleep.jsonl

# Production-generated files (iOS v1 and Android v2 on every CLI OS)
mkdir -p "$HOME/Documents/HealthVault"
healthmd export --yesterday --destination "$HOME/Documents/HealthVault"

# Durable operations
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --output resumed.json
healthmd cancel JOB_UUID

# Remove one pairing, or explicitly recover an unusable local trust record
healthmd direct unpair DEVICE_UUID
healthmd direct reset-trust --confirm
```

The source app must remain open while pairing or starting a request. Android uses a visible,
user-started data-sync foreground service for an active direct session. Manual IP listens on TCP
`17647` by default; use the global `--port` option when a different saved port is required.

Command results and errors are JSON on stdout. Pairing instructions and non-sensitive progress may
use stderr. Raw and extraction output is either streamed as JSON/JSONL or atomically committed to the
explicit `--output` path. JSONL file output writes its health-free receipt beside it as
`OUTPUT.receipt.json`. JSONL conversion bounds each daily item to 64 MiB; use JSON for an unusually
dense day. A validated partial result exits nonzero unless `--allow-partial` is set.

## Durability and security

- iOS keeps its deployed six-digit pairing flow; Android pairing uses a separate 20-digit (~66-bit) one-time code before Keystore-backed reconnect trust.
- TCP packets, binary chunks, partitions, Markdown merges, and extraction projections are bounded.
- Requests, peer bindings, destination identity, manifests, and request fingerprints are immutable
  across resume.
- Partition and response SHA-256 digests are checked before acknowledgement.
- Generated paths reject traversal and symlink destinations; destination changes fail closed.
- Health payloads are assembled on private disk spools and are never written to logs.
- Durable jobs expire after seven days.

State follows platform conventions (`~/Library/Application Support`, XDG data directories, or
Windows known folders). `HEALTHMD_CLI_DATA_DIR` changes file state but deliberately does not
namespace native OS credentials; use it only in clean isolated automation. An owner mismatch fails
closed and never silently erases the existing credential.

## MCP for Codex and Claude

The `healthmd` executable includes a local stdio MCP server that communicates directly with the
foreground Health.md iPhone app over the paired, authenticated, encrypted channel on port `17647`;
the Health.md Mac app is not required. Pairing and MCP deliberately run through the same installed,
signed executable identity so native credentials never require a second application's Keychain ACL.

For Codex, one command configures the fixed stdio entry, prompts for iPhone pairing when needed, and
pins the paired device:

```bash
healthmd setup codex
```

Keep Health.md foreground on iPhone and scan the displayed QR with the iPhone Camera; it opens
Health.md, selects the Sync tab, applies the bounded Manual IP endpoint and one-time code, then asks the user to approve
**Pair with healthmd**. Manual entry under **Settings → Mac Sync → Direct CLI Access** remains the fallback. Restart Codex after a changed
configuration. The generated entry launches `healthmd mcp serve` and marks export, resume, and
cancel tools for approval. `healthmd-mcp` remains an installed compatibility launcher, but it simply
delegates to the sibling `healthmd` executable to preserve the same credential identity.

The server exposes 17 fixed operations for
readiness, bounded typed queries, charts, sleep, workouts, comparisons, coverage, evidence, and
durable generated-file exports. It has no shell, SQL, arbitrary URL, or arbitrary file-read tool.
Approved generated exports require an explicit existing destination.

Typed tool discovery is self-contained. `tools/list` expands every nested date, metric, source,
page, period, aggregation, and advanced request shape and includes concrete examples. For shell-side
debugging, inspect the identical catalog without starting a listener or contacting iPhone:

```bash
healthmd mcp schema healthmd_sleep_sessions
healthmd mcp schema healthmd_metric_chart
healthmd mcp schema # all fixed tools
```

For a seven-night sleep question, call `healthmd_sleep_sessions` directly with concrete inclusive
dates; the tool supplies canonical sleep metrics and lossless session detail:

```json
{"dates":{"type":"exact","range":{"start_date":"2026-07-22","end_date":"2026-07-28"}},"all_pages":true}
```

The dates above illustrate the shape and must be resolved for the user's request. `healthmd extract`
returns a validated canonical `healthmd.health_data` projection; it is not the typed sleep-session
query API and should not be used merely to discover MCP arguments.

Hosts that negotiate `io.modelcontextprotocol/ui` with `text/html;profile=mcp-app` receive the
self-contained interactive Health.md view. Other hosts retain authoritative JSON/text; metric charts
also include a portable PNG fallback. Keep Health.md foreground on the iPhone while starting a query
or export. Query pages preserve explicit coverage/truncation receipts; if one request exceeds the
366,000-day / 64 MiB compact-context guard, partition dates or metric IDs across calls rather than treating the
logical corpus as unavailable.

See [the architecture](docs/architecture.md), [iOS export protocol v1](../../packages/contracts/direct-protocol/v1/protocol.md),
[iPhone query protocol v3](../../packages/contracts/direct-protocol/v3/protocol.md),
[Android protocol v2](../../packages/contracts/direct-protocol/v2/protocol.md), [release QA](docs/qa.md), and
[release process](docs/releasing.md).

## Development

```bash
cargo fmt --all --check
cargo clippy --workspace --all-targets --all-features -- -D warnings
cargo test --workspace --all-features
cargo run -- --help
cargo run -- setup codex --help
cargo run -- mcp serve --help
cargo run -- mcp schema healthmd_sleep_sessions
```

## License

AGPL-3.0-only. See [LICENSE](LICENSE).
