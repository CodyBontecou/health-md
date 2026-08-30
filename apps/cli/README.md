# Health.md CLI

Standalone, cross-platform command-line access to health exports prepared by the Health.md iOS
or Android app.

> **Status:** `0.1.0-alpha.3` explicitly unqualified preview candidate. Deployed iOS export
> protocol v1, Android application protocol v2, and capability-gated iPhone query protocol v3 are
> implemented with automated Swift↔Rust and Kotlin↔Rust compatibility gates. Complete
> physical-device release QA is still required before the first qualified stable release.

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

## Mobile compatibility

| Mobile source | Protocol | Exact tag-SHA counterpart / unqualified compatibility floor | Portable Rust operations | Public status |
|---|---|---|---|---|
| Export-capable iPhone | selector 1 / v1 | iOS 3.2.1 (build 202608300209) / iOS 3.0.3 | Status, raw, extract, files, resume, cancel | Pending physical qualification |
| Query-capable iPhone | selector 1 / v1 + query v3 | iOS 3.2.1 (build 202608300209) / iOS 3.0.3 | V1 plus 19-tool local MCP/query | Pending physical qualification |
| Android | selector 2 / v2 | Android 1.8.1 (`versionCode 30`) / Android 1.5.4 (`versionCode 25`) | Status, native raw, files, resume, cancel | Pending physical qualification |
| Android typed MCP query | N/A | Not implemented | Query tools require iPhone v3 | Unsupported |

No public CLI/mobile pair is qualified yet. V3 does not replace v1 pairing, transport, exports, or
transfer frames, and Android never downgrades to v1. See the authoritative
[mobile compatibility ledger](docs/mobile-compatibility.md); every release records exact mobile
build IDs because matching marketing versions or protocol numbers alone is insufficient.

## Installation

The `0.1.0-alpha.3` workflow is configured to publish a checksummed, explicitly unqualified
preview. After the exact GitHub prerelease and tap formula are public, install it with:

```bash
brew install CodyBontecou/tap/healthmd
healthmd --version
```

The formula will install both `healthmd` and its `healthmd-mcp` compatibility launcher from the
same versioned release. This preview does not qualify a CLI/mobile pair; use the exact matching
mobile build named by release evidence. The tap tracks preview releases until the first qualified
stable release.

PowerShell installer and checksummed `.zip`/`.tar.xz` archives for Windows, Linux, and macOS are
attached to each release. After an exact version reaches crates.io, Rust users can install it with:

```bash
cargo install healthmd-cli --locked
# Or, after installing cargo-binstall:
cargo binstall healthmd-cli
```

For unreleased development source, clone the monorepo and install from the CLI workspace:

```bash
git clone https://github.com/CodyBontecou/health-md.git
cd health-md/apps/cli
cargo install --path crates/healthmd-cli
```

Prebuilt archives use `healthmd-cli/v<version>` tags. Do not use the repository-wide
`/releases/latest` URL because the Health.md monorepo reserves that release pointer for the Apple apps.
For a published version, download the installer and `sha256.sum` plus
`sha256.sum.sigstore.json` from that exact tag, verify the documented Sigstore workflow identity and
checksums, then run the shell installer on macOS/Linux. On Windows, run the PowerShell installer
when `release-identities.json` records a `qualified` Windows publisher, or — while the ledger
defers Authenticode — expect one SmartScreen prompt on first run and rely on the signed checksum
manifest for integrity. macOS users may also use the notarized, stapled DMG. Replace `VERSION`
with the complete version including any prerelease suffix:

```bash
VERSION='0.1.0-alpha.3'
TAG="healthmd-cli/v$VERSION"
BASE="https://github.com/CodyBontecou/health-md/releases/download/$TAG"
curl -fLO "$BASE/healthmd-cli-installer.sh"
curl -fLO "$BASE/sha256.sum"
curl -fLO "$BASE/sha256.sum.sigstore.json"
cosign verify-blob \
  --bundle sha256.sum.sigstore.json \
  --certificate-identity "https://github.com/CodyBontecou/health-md/.github/workflows/cli-release.yml@refs/tags/$TAG" \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  sha256.sum
expected="$(awk '$2 == "healthmd-cli-installer.sh" {print $1}' sha256.sum)"
if command -v sha256sum >/dev/null 2>&1; then
  actual="$(sha256sum healthmd-cli-installer.sh | awk '{print $1}')"
elif command -v shasum >/dev/null 2>&1; then
  actual="$(shasum -a 256 healthmd-cli-installer.sh | awk '{print $1}')"
else
  echo 'SHA-256 verifier is required' >&2; exit 1
fi
test -n "$expected" && test "$actual" = "$expected"
sh healthmd-cli-installer.sh
```

```powershell
$Version = '0.1.0-alpha.3'
$Tag = "healthmd-cli/v$Version"
$Base = "https://github.com/CodyBontecou/health-md/releases/download/$Tag"
Invoke-WebRequest "$Base/healthmd-cli-installer.ps1" -OutFile healthmd-cli-installer.ps1
Invoke-WebRequest "$Base/sha256.sum" -OutFile sha256.sum
Invoke-WebRequest "$Base/sha256.sum.sigstore.json" -OutFile sha256.sum.sigstore.json
Invoke-WebRequest "$Base/release-identities.json" -OutFile release-identities.json
cosign verify-blob --bundle sha256.sum.sigstore.json `
  --certificate-identity "https://github.com/CodyBontecou/health-md/.github/workflows/cli-release.yml@refs/tags/$Tag" `
  --certificate-oidc-issuer https://token.actions.githubusercontent.com sha256.sum
if ($LASTEXITCODE -ne 0) { throw 'checksum signature verification failed' }
$Line = (Select-String '^[0-9a-f]{64}  healthmd-cli-installer\.ps1$' sha256.sum).Line
$IdentityLine = (Select-String '^[0-9a-f]{64}  release-identities\.json$' sha256.sum).Line
if (!$Line -or !$IdentityLine -or
    (Get-FileHash .\healthmd-cli-installer.ps1 -Algorithm SHA256).Hash.ToLower() -ne $Line.Substring(0, 64) -or
    (Get-FileHash .\release-identities.json -Algorithm SHA256).Hash.ToLower() -ne $IdentityLine.Substring(0, 64)) { throw 'release asset checksum mismatch' }
$Identity = Get-Content .\release-identities.json -Raw | ConvertFrom-Json
$Signature = Get-AuthenticodeSignature .\healthmd-cli-installer.ps1
if ($Identity.windows.status -eq 'qualified') {
  if ($Signature.Status -ne 'Valid' -or
      $Signature.SignerCertificate.Subject -cne $Identity.windows.publisher_subject) { throw 'publisher verification failed' }
} elseif ($Identity.windows.status -eq 'pending_external_certificate_provisioning') {
  if ($Signature.Status -eq 'Valid') { throw 'installer is signed by an unrecorded publisher' }
  Write-Host 'Windows artifacts are Authenticode-unsigned in this release.' -ForegroundColor Yellow
  Write-Host 'Expect one SmartScreen prompt; integrity is verified by the signed sha256.sum above.' -ForegroundColor Yellow
} else { throw 'unrecognized Windows signing state in release-identities.json' }
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\healthmd-cli-installer.ps1
if ($LASTEXITCODE -ne 0) { throw 'installer failed' }
```

## Upgrade, uninstall, and support

Upgrade both `healthmd` and `healthmd-mcp` from one release; never mix archive versions. Use
`brew update && brew upgrade healthmd`, rerun the exact versioned installer, or run
`cargo install --locked --force healthmd-cli`. Normal signed upgrades preserve the installation
identity, durable jobs, and native trust. Moving from an ad-hoc/unsigned macOS build to the stable
Developer ID principal requires one explicit unpair/re-pair; the installer never resets trust.
Windows keeps the fixed Credential Manager target, and its compatibility launcher uses an
authenticated same-file helper.

Before uninstalling, finish or intentionally cancel durable jobs, run `healthmd direct unpair` for
each device, forget the CLI on each mobile source, and use `healthmd direct reset-trust --confirm`
only when all local trust should be erased. Then use `brew uninstall healthmd`, `cargo uninstall
healthmd-cli`, or remove both installed binaries. Binary removal deliberately does **not** delete
native credentials, the installation identity, job/spool state, or exported files. Remove state only
after recovery is no longer needed:

| Platform | Default durable state root | Native trust |
|---|---|---|
| macOS | `~/Library/Application Support/Health.md/CLI/Direct/v1` | Keychain service `com.codybontecou.obsidianhealth.direct-cli-trust` |
| Linux | `${XDG_DATA_HOME:-~/.local/share}/Health.md/CLI/Direct/v1` | Unlocked Secret Service collection |
| Windows | `%LOCALAPPDATA%\Health.md\CLI\Direct\v1` | Windows Credential Manager |

Never delete state while a job or credential mutation has an unknown outcome. Preserve the job ID
and inspect status first. For support, provide only the CLI version, OS/architecture, exact mobile
app version/build, health-free status/error code, job/request ID, counts, and artifact digest. Never
send raw health output, source records, credentials, user paths, or user-data dates. Portable direct
supports Manual IP/Tailscale on macOS, Linux, and Windows; Nearby belongs only to the bundled Swift
client. Source builds require Rust 1.85 or newer.

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

# Typed query through the same operation registry and evaluator as MCP (iOS query v3)
healthmd query healthmd_sleep_sessions \
  --arguments '{"dates":{"type":"all_available"},"all_pages":true}'

# Scoped canonical extraction (a separate iOS v1 projection)
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

## MCP for local and remote clients

Health.md has one transport-neutral operation layer with CLI and MCP adapters. The publishable
`healthmd-operations` crate owns backend contracts, fixed definitions, typed normalization,
validation, canonical receipts, and bounded traversal. `healthmd query` calls it directly, while
`healthmd-mcp` adds JSON-RPC, MCP Apps, images, stdio, and HTTP envelopes. A deterministic generator
writes the packaged MCP catalog from the shared registry and CI rejects stale output.

The default `healthmd` build includes only the local stdio MCP transport. It communicates directly
with the foreground Health.md iPhone app over the paired, authenticated, encrypted channel on port
`17647`; the Health.md Mac app, an OAuth service, and a health-data cloud are not required.
Release archives intentionally use this local-first default feature set. Pairing and MCP deliberately run through the same installed,
signed executable identity so native credentials never require a second application's Keychain ACL.

For Codex, one command configures the fixed stdio entry, prompts for iPhone pairing when needed, and
pins the paired device:

```bash
healthmd setup codex
```

Keep Health.md foreground on iPhone, open **Sync → Direct CLI Access**, tap **Scan Pairing QR**,
and scan the displayed image. The in-app camera scan is the explicit pairing action: Health.md
validates the bounded Manual IP endpoint and one-time code and starts the authenticated connection
automatically without a second **Pair** tap. External custom-URL opens are rejected. Manual entry
under **Sync → Direct CLI Access** remains the fallback.
Restart Codex after a changed configuration. The generated entry launches `healthmd mcp serve` and marks export, resume, and
cancel tools for approval. `healthmd-mcp` remains an installed compatibility launcher. On Unix it
replaces itself with the sibling `healthmd`; on Windows, which has no `exec(2)`, it serves in-process
and supervises its own same-file helper against the same fixed Credential Manager service/account.

The complete local server exposes 19 fixed operations for pairing, readiness, bounded typed
queries, charts, sleep, workouts, comparisons, coverage, evidence, and durable generated-file
exports. It has no shell, SQL, arbitrary URL, or arbitrary file-read tool. Approved generated
exports require an explicit existing destination.

For a least-privilege local host that should never receive pairing or filesystem-export authority,
pair outside MCP and use the separate read-only stdio entry:

```bash
healthmd direct pair
healthmd mcp serve-read-only
```

`serve-read-only` is part of the default local-first build. It exposes exactly the 13 readiness,
discovery, and typed-query tools; all six pairing/export-job tools are absent and guessed calls are
rejected. It starts no MCP HTTP listener, requires no OAuth or tunnel, and uses no Health.md or
third-party cloud service. The iPhone must already be paired and remain foreground for each query.

A complete local desktop MCP client can onboard without opening a separate terminal. Call
`healthmd_pairing_start`, render the returned `image/png`, and ask the user to open Health.md's
**Sync → Direct CLI Access → Scan Pairing QR** screen and scan it. Health.md starts pairing
immediately from that in-app scan; no second Pair tap is required. Poll `healthmd_pairing_status`
with the returned `pairing_session_id` until it reports
`paired`, `timed_out`, or `failed`. The listener defaults to 180
seconds and is bounded to 30–600 seconds. To prevent ambiguous device routing, pairing start is an
onboarding operation: it refuses when any mobile trust or an explicit MCP `--device` pin already
exists. Use `healthmd_doctor` for an existing pairing, or explicitly unpair/reconfigure before
onboarding another device. The image intentionally contains the short-lived pairing secret; the
JSON/text receipt does not contain the code, host address, or deep link. When a local host negotiates
MCP Apps, `healthmd_pairing_start` requests the dedicated `ui://healthmd/pairing-qr-v1` inline card,
which renders the existing native image block without copying the QR payload into text or
`structuredContent`. Other image-capable hosts retain the standard `image/png` fallback and may show
it inside a collapsible tool result. These two tools are available only through local stdio and are
absent from Streamable HTTP and OAuth catalogs; remote callers cannot list or read the pairing UI
resource.

An experimental, source-build-only read-only Streamable HTTP profile exposes the same application
for loopback development or a single-owner direct-backed endpoint. It is absent from default release
artifacts. Enable `streamable-http` for loopback-only development or `oauth-resource-server` for the
OAuth flags shown below. The Rust listener always binds loopback and must sit behind a co-resident TLS reverse
proxy; never expose its HTTP socket directly. OAuth mode requires one exact owner subject plus exact
issuer, audience/resource, expiry, algorithm, scope, and JWKS verification. Configure explicit Host
and browser Origin allowlists:

```bash
HEALTHMD_MCP_OAUTH_OWNER_SUBJECT='exact-owner-subject' \
cargo run --release --features oauth-resource-server -- mcp serve-http \
  --bind 127.0.0.1:8787 \
  --allowed-host mcp.example.com \
  --allowed-origin https://trusted-client.example \
  --oauth-resource https://mcp.example.com/mcp \
  --oauth-issuer https://auth.example.com/ \
  --oauth-jwks-uri https://auth.example.com/.well-known/jwks.json
```

The proxy terminates HTTPS and forwards only to that loopback listener, preserving an allowed Host.
Streamable HTTP supports MCP revisions `2025-06-18` and `2025-11-25`. Allowlisted browser origins receive exact-origin CORS preflight and actual-response headers; other origins fail closed. Every OAuth request is reverified and each tool call uses the current token's scopes, even within an existing MCP session. The remote profile excludes export/resume/cancel tools. JWKS fetches reject redirects and cleartext
non-loopback URLs, time out, and stop at 1 MiB; verified bearer headers are removed before MCP
dispatch. Omit all OAuth flags only for loopback development; unauthenticated mode rejects every
non-loopback Host or Origin, so it cannot be exposed through a public reverse proxy. Partial OAuth
configuration fails closed.

Health.md does not provide a synchronized remote health-data corpus. The optional HTTP mode remains
a live relay to the paired foreground iPhone: it has no synchronization API, health-data database,
retention store, or server-side fallback. ChatGPT, Claude, Codex, IDEs, and custom MCP clients are
distribution targets rather than special server modes. See [Remote MCP architecture](docs/remote-mcp.md)
for the direct-relay, OAuth, deployment, and threat-model contract.

Typed tool discovery is self-contained. `tools/list` expands every nested date, metric, source,
page, period, aggregation, and advanced request shape and includes concrete examples. For shell-side debugging, inspect the generated shared catalog without starting a listener or
contacting iPhone:

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

The identical operation can run without an MCP envelope:

```bash
healthmd query healthmd_sleep_sessions \
  --arguments '{"dates":{"type":"exact","range":{"start_date":"2026-07-22","end_date":"2026-07-28"}},"all_pages":true}'
```

The dates above illustrate the shape and must be resolved for the user's request. `healthmd extract`
returns a validated canonical `healthmd.health_data` projection; it is not the typed sleep-session
query API and should not be used merely to discover query arguments.

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
cargo test --workspace                         # local-first default
cargo test --workspace --all-features          # experimental remote profiles
cargo clippy --workspace --all-targets -- -D warnings
cargo clippy --workspace --all-targets --all-features -- -D warnings
cargo run -- --help
cargo run -- setup codex --help
cargo run -- query --help
cargo run -- mcp serve --help
cargo run -- mcp serve-read-only --help
cargo run --features streamable-http -- mcp serve-http --help
cargo run --features oauth-resource-server -- mcp serve-http --help
cargo run -- mcp schema healthmd_sleep_sessions
```

## License

AGPL-3.0-only. See [LICENSE](LICENSE).
