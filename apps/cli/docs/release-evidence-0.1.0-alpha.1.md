# Standalone CLI release evidence — 0.1.0-alpha.1 (working copy)

Working evidence record for the first `healthmd-cli/v0.1.0-alpha.1` candidate. Windows release
artifacts are deferred: `x86_64-pc-windows-msvc` and the PowerShell installer are absent from this
candidate, the Windows rows below stay deferred until the Authenticode identity is provisioned, and
the physical Windows matrix is out of scope for this release. Store only health-free release
metadata. Do not attach command stdout that may contain health payloads.

## Identity

- Tag: `healthmd-cli/v0.1.0-alpha.1`
- Version: `0.1.0-alpha.1`
- Candidate commit SHA: pending (capture at tag time; tag must point to exact current `main`)
- Captured `origin/main` SHA: pending
- Tag peeled to candidate SHA: pending
- Candidate equals captured main: pending
- Seven package versions and internal exact requirements aligned: pass (`scripts/verify-release.py` no-tag mode, all packages at `0.1.0-alpha.1`)
- `apps/cli/Cargo.lock` verified: pending tag-time `verify-release.py --tag` run
- `packages/healthmd-core-rust/Cargo.lock` verified: pending tag-time `verify-release.py --tag` run
- Draft release target SHA/prerelease state verified: pending

## Source and contract gates

- CLI fmt/test/strict Clippy/Rust 1.85: run URL + pass/fail: pending
- Shared-core fmt/test/strict Clippy/Rust 1.85: run URL + pass/fail: pending
- Contract validator: fixture count + mirror count + pass/fail: pending
- Swift v1 vectors: pending
- Kotlin v2 vectors and live loopback interop: pending
- Swift v3 query vectors: pending
- `HealthMdConnectivity` Swift package: test count + pass/fail: pending
- Android counterpart gate: run URL + pass/fail: pending
- Apple counterpart gate: run URL + pass/fail: pending

## Exact mobile candidates

- [`mobile-compatibility.md`](mobile-compatibility.md) has machine-checked qualified records for all three supported rows: pending
- Each ledger `evidence_sha256` matches this retained health-free evidence record: pending
- Exact qualified records are copied to the release notes without weakening or substituting marketing versions: pending

| Source | App version | Build ID/commit | Device/OS | LAN | Tailscale | Result |
|---|---|---|---|---|---|---|
| iPhone v1/v3 | | | | | | |
| Android v2 | | | | | | |

Protocol numbers are not substitutes for exact mobile build IDs. Known candidate floors from the
ledger: iPhone 3.0.3, Android 1.5.4 (`versionCode 25`), each built from the exact candidate SHA;
the qualified store builds may be later — record what was actually tested.

## Desktop artifacts

macOS and Linux only for this candidate (4 archives, 2 DMGs, shell installer, formula, 18 sealed
payloads).

| Runner/OS/architecture | Filename | SHA-256 | Native execution | Result |
|---|---|---|---|---|
| macOS arm64 | `healthmd-cli-aarch64-apple-darwin.tar.xz` | | | |
| macOS x86_64 | `healthmd-cli-x86_64-apple-darwin.tar.xz` | | | |
| Linux arm64 | `healthmd-cli-aarch64-unknown-linux-gnu.tar.xz` | | | |
| Linux x86_64 | `healthmd-cli-x86_64-unknown-linux-gnu.tar.xz` | | | |
| Windows x86_64 | deferred | N/A | N/A | deferred |
| macOS arm64 DMG | `healthmd-cli-aarch64-apple-darwin.dmg` | | N/A | |
| macOS x86_64 DMG | `healthmd-cli-x86_64-apple-darwin.dmg` | | N/A | |
| Shell installer | `healthmd-cli-installer.sh` | | | |
| PowerShell installer | deferred | N/A | N/A | deferred |
| Homebrew formula | `healthmd.rb` (not published for prerelease) | | N/A | |
| SPDX SBOM | `healthmd-cli-0.1.0-alpha.1.spdx.json` | | N/A | |
| CycloneDX SBOM | `healthmd-cli-0.1.0-alpha.1.cdx.json` | | N/A | |

- `sha256.sum` verified against every listed payload and sidecar (18 payloads): pending
- Sigstore bundle filename: `sha256.sum.sigstore.json`
- Expected certificate identity: `https://github.com/CodyBontecou/health-md/.github/workflows/cli-release.yml@refs/tags/healthmd-cli/v0.1.0-alpha.1`
- OIDC issuer: `https://token.actions.githubusercontent.com`
- `cosign verify-blob` result: pending
- Signed candidate provenance attestations verified: pending
- SBOM attestations verified: pending
- Remote draft filename set equals workflow artifact set: pending
- Remote draft bytes equal workflow artifacts: pending
- Post-approval remote byte revalidation: pending

## Native signature gates

- Developer ID Team ID (`67KC823C9A`) and fixed identifiers (`md.health.cli.healthmd`, `md.health.cli.healthmd-mcp`) verified: pending
- Both Mach-O signatures use hardened runtime and secure timestamp: pending
- Notary submission IDs/statuses (no logs containing user data): pending
- Both DMGs stapled and Gatekeeper-assessed: pending
- Both extracted Mach-O binaries Gatekeeper-assessed: pending
- Keychain signed-upgrade synthetic device probe: pending
- Windows expected publisher subject: deferred
- Both PE signatures and RFC 3161 timestamps: deferred
- PowerShell installer signature and RFC 3161 timestamp: deferred
- Credential Manager legacy-target synthetic device probe: deferred

## CLI/MCP smoke

- `healthmd --version` / `--help`: pending
- `healthmd-mcp --help`: pending
- `healthmd setup codex --skip-pairing` idempotent isolated run: pending
- `healthmd setup claude --skip-pairing` desktop and `--project DIR` idempotent isolated runs: pending
- MCP initialize/tools/resources: pending
- Fixed tool count (complete mode `19`, read-only mode `13`): pending
- Same-executable compatibility-launcher path: pending (Windows same-file helper deferred)
- `direct devices` or readiness result (code/count only): pending
- UI resource and PNG dimensions/format: pending

## Physical direct matrix

Record statuses, counts, job/request IDs, durations, and artifact digests only.

- iPhone LAN pair/reconnect/status/raw/extract/files: pending
- iPhone interruption/resume/cancel/background/protected-data negatives: pending
- iPhone MCP typed queries/paging/cancel/UI/PNG/export controls: pending
- iPhone Tailscale: pending
- Android LAN pair/reconnect/status/raw/generated files: pending
- Android interruption/resume/cancel: pending
- Android Tailscale: pending
- Windows NTFS drive-root/UNC/reparse/replacement race matrix: deferred
- Disposable outputs securely removed: pending

## Publication

- `cli-signing` approver and timestamp: pending
- `cli-release` approver and timestamp: pending
- GitHub Release publication timestamp and asset count: pending
- Repository-wide latest remained Apple release: pending
- crates.io `healthmd-protocol` checksum/index-visible timestamp: pending
- crates.io `healthmd-operations` checksum/index-visible timestamp: pending
- crates.io `healthmd-client` checksum/index-visible timestamp: pending
- crates.io `healthmd-mcp` checksum/index-visible timestamp: pending
- crates.io `healthmd-cli` checksum/index-visible timestamp: pending
- Homebrew tap commit: not published for prerelease (dist skips prerelease formula publication)
- Homebrew macOS install/upgrade result: not published for prerelease
- Linuxbrew install/upgrade result: not published for prerelease

## Recovery actions

- Yank/unyank operations, exact crate/version, reason, approver, timestamp:
- Formula revert/correction commit and reason:
- Release withdrawal/replacement version and reason:
- Signing credential rotation/revocation references:

## Prohibited evidence

Do **not** record health values, samples, source records, clinical content, routes, credentials,
private keys, user filesystem paths, device owner names, raw payloads, or dates derived from a
user's health data. Redact command output rather than trying to review payloads after upload.
