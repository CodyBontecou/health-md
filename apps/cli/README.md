# Health.md CLI

Standalone, cross-platform command-line access to Apple Health exports prepared by the Health.md
iPhone app.

> **Status:** `0.1.0-alpha.1`. Protocol-v1 compatibility and automated Swift↔Rust fixtures are
> implemented. Complete physical-iPhone release QA is still required before the first public
> release.

## How it works

The CLI never reads HealthKit. Keep Health.md open on an iPhone; the iPhone reads HealthKit and
connects to the CLI over an explicit LAN or Tailscale address.

```text
healthmd on macOS / Linux / Windows
  <- authenticated, encrypted Manual IP or Tailscale connection ->
open Health.md iPhone app -> HealthKit -> bounded protected export spool
```

Manual IP is portable. Apple's MultipeerConnectivity-based Nearby transport remains available only
in the legacy Swift client. No command silently falls back to another backend or transport.

## Platform support

| Capability | macOS | Linux | Windows |
|---|---:|---:|---:|
| Pair, devices, unpair, live status | Yes | Yes | Yes |
| Raw JSON export and canonical extract | Yes | Yes | Yes |
| Durable status, resume, cancellation | Yes | Yes | Yes |
| Generated-file destination commits | Yes | Yes | Not in protocol v1 |
| Manual IP / Tailscale | Yes | Yes | Yes |
| Nearby / MultipeerConnectivity | No | No | No |

Protocol v1 encodes generated-file destinations as Unix absolute paths. Windows users can use raw
exports and extracts now; generated-file mode requires the planned protocol-v2 logical destination
contract.

## Installation

Checksummed archives and direct installers become available when the first GitHub release is
published. Homebrew formula publishing begins with the first stable (non-prerelease) release:

```bash
# macOS or Linux with Homebrew/Linuxbrew, after the first stable release
brew install CodyBontecou/tap/healthmd

# macOS or Linux without Homebrew, including prereleases
curl --proto '=https' --tlsv1.2 -LsSf \
  https://github.com/CodyBontecou/healthmd-cli/releases/latest/download/healthmd-cli-installer.sh | sh
```

PowerShell installer and checksummed `.zip`/`.tar.xz` archives for Windows, Linux, and macOS are
attached to each release. Rust users can also install a published version from crates.io:

```bash
cargo install healthmd-cli --locked
# Or use the matching prebuilt GitHub archive after installing cargo-binstall:
cargo binstall healthmd-cli
```

Until the first release, build from source:

```bash
git clone https://github.com/CodyBontecou/healthmd-cli.git
cd healthmd-cli
cargo install --path crates/healthmd-cli
```

## Pair an iPhone

1. Run:

   ```bash
   healthmd direct pair
   ```

2. Keep the command running. Its one-time code, listener address, and port are printed to stderr.
3. In Health.md on iPhone, open **Settings → Mac Sync → Direct CLI Access**, select **Manual IP**,
   enter the computer's LAN/Tailscale address, port, and code, then pair.
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

# Strict raw export; omit --output to stream validated JSON to stdout
healthmd export --yesterday --raw --output yesterday.json
healthmd export --last 7 --raw --output week.json
healthmd export --from 2026-07-01 --to 2026-07-07 --raw
healthmd export --all --raw --output complete-health-corpus.json

# Scoped canonical extraction
healthmd extract --category Sleep --last 7 --output sleep.json
healthmd extract --metric workouts --last 14 --object records \
  --detail lossless --output workout-records.json
healthmd extract --category Sleep --last 7 --format jsonl --output sleep.jsonl

# Production-generated files (macOS/Linux in protocol v1)
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

The iPhone must remain open and foregrounded while serving a request. Manual IP listens on TCP
`17647` by default; use the global `--port` option when a different saved port is required.

Command results and errors are JSON on stdout. Pairing instructions and non-sensitive progress may
use stderr. Raw and extraction output is either streamed as JSON/JSONL or atomically committed to the
explicit `--output` path. JSONL file output writes its health-free receipt beside it as
`OUTPUT.receipt.json`. JSONL conversion bounds each daily item to 64 MiB; use JSON for an unusually
dense day. A validated partial result exits nonzero unless `--allow-partial` is set.

## Durability and security

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

See [the architecture](docs/architecture.md), [protocol v1](docs/protocol/v1.md),
[release QA](docs/qa.md), and [release process](docs/releasing.md).

## Development

```bash
cargo fmt --all --check
cargo clippy --workspace --all-targets --all-features -- -D warnings
cargo test --workspace --all-features
cargo run -- --help
```

## License

AGPL-3.0-only. See [LICENSE](LICENSE).
