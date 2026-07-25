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
| Generated-file destination commits | Yes | Yes | Android v2 only on Windows |
| Manual IP / Tailscale | Yes | Yes | Yes |
| Nearby / MultipeerConnectivity | No | No | No |

iOS protocol v1 encodes generated-file destinations as Unix absolute paths, so iOS generated-file
mode remains unavailable on Windows. Android protocol v2 uses an opaque logical destination binding
and supports generated-file commits on Windows, with a 4,096-file limit per Android generated job.
Android raw snapshots retain their provider-native
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

# Production-generated files (iOS v1 on macOS/Linux; Android v2 on every CLI OS)
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

See [the architecture](docs/architecture.md), [iOS protocol v1](../../packages/contracts/direct-protocol/v1/protocol.md),
[Android protocol v2](../../packages/contracts/direct-protocol/v2/protocol.md), [release QA](docs/qa.md), and
[release process](docs/releasing.md).

## Development

```bash
cargo fmt --all --check
cargo clippy --workspace --all-targets --all-features -- -D warnings
cargo test --workspace --all-features
cargo run -- --help
```

## License

AGPL-3.0-only. See [LICENSE](LICENSE).
