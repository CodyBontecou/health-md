# Standalone CLI release evidence

Copy this template for one exact `healthmd-cli/v<version>` candidate. Store only health-free release
metadata. Do not attach command stdout that may contain health payloads.

## Identity

- Tag:
- Version:
- Candidate commit SHA:
- Captured `origin/main` SHA:
- Tag peeled to candidate SHA: pass/fail
- Candidate equals captured main: pass/fail
- Seven package versions and internal exact requirements aligned: pass/fail
- `apps/cli/Cargo.lock` verified: pass/fail
- `packages/healthmd-core-rust/Cargo.lock` verified: pass/fail
- Draft release target SHA/prerelease state verified: pass/fail

## Source and contract gates

- CLI fmt/test/strict Clippy/Rust 1.85: run URL + pass/fail
- Shared-core fmt/test/strict Clippy/Rust 1.85: run URL + pass/fail
- Contract validator: fixture count + mirror count + pass/fail
- Swift v1 vectors: pass/fail
- Kotlin v2 vectors and live loopback interop: pass/fail
- Swift v3 query vectors: pass/fail
- `HealthMdConnectivity` Swift package: test count + pass/fail
- Android counterpart gate: run URL + pass/fail
- Apple counterpart gate: run URL + pass/fail

## Exact mobile candidates

- [`mobile-compatibility.md`](mobile-compatibility.md) has machine-checked qualified records for all three supported rows: pass/fail
- Each ledger `evidence_sha256` matches this retained health-free evidence record: pass/fail
- Exact qualified records are copied to the release notes without weakening or substituting marketing versions: pass/fail

| Source | App version | Build ID/commit | Device/OS | LAN | Tailscale | Result |
|---|---|---|---|---|---|---|
| iPhone v1/v3 | | | | | | |
| Android v2 | | | | | | |

Protocol numbers are not substitutes for exact mobile build IDs.

## Desktop artifacts

| Runner/OS/architecture | Filename | SHA-256 | Native execution | Result |
|---|---|---|---|---|
| macOS arm64 | | | | |
| macOS x86_64 | | | | |
| Linux arm64 | | | | |
| Linux x86_64 | | | | |
| Windows x86_64 | | | | |
| macOS arm64 DMG | | | N/A | |
| macOS x86_64 DMG | | | N/A | |
| Shell installer | | | | |
| PowerShell installer | | | | |
| Homebrew formula | | | N/A | |
| SPDX SBOM | | | N/A | |
| CycloneDX SBOM | | | N/A | |

- `sha256.sum` verified against every listed payload and sidecar: pass/fail
- Sigstore bundle filename:
- Expected certificate identity:
- OIDC issuer:
- `cosign verify-blob` result: pass/fail
- Signed candidate provenance attestations verified: pass/fail
- SBOM attestations verified: pass/fail
- Remote draft filename set equals workflow artifact set: pass/fail
- Remote draft bytes equal workflow artifacts: pass/fail
- Post-approval remote byte revalidation: pass/fail

## Native signature gates

- Developer ID Team ID and fixed identifiers verified: pass/fail
- Both Mach-O signatures use hardened runtime and secure timestamp: pass/fail
- Notary submission IDs/statuses (no logs containing user data):
- Both DMGs stapled and Gatekeeper-assessed: pass/fail
- Both extracted Mach-O binaries Gatekeeper-assessed: pass/fail
- Keychain signed-upgrade synthetic device probe: pass/fail
- Windows expected publisher subject (or `pending_external_certificate_provisioning` deferred):
- Both PE signatures and RFC 3161 timestamps (skip when deferred): pass/fail/deferred
- PowerShell installer signature and RFC 3161 timestamp (skip when deferred): pass/fail/deferred
- Credential Manager legacy-target synthetic device probe: pass/fail/deferred (signing-gated)

## CLI/MCP smoke

- `healthmd --version` / `--help`: pass/fail
- `healthmd-mcp --help`: pass/fail
- `healthmd setup codex --skip-pairing` idempotent isolated run: pass/fail
- MCP initialize/tools/resources: pass/fail
- Fixed tool count (`17`): pass/fail
- Same-executable/Windows same-file helper path: pass/fail
- `direct devices` or readiness result (code/count only):
- UI resource and PNG dimensions/format: pass/fail

## Physical direct matrix

Record statuses, counts, job/request IDs, durations, and artifact digests only.

- iPhone LAN pair/reconnect/status/raw/extract/files: pass/fail
- iPhone interruption/resume/cancel/background/protected-data negatives: pass/fail
- iPhone MCP typed queries/paging/cancel/UI/PNG/export controls: pass/fail
- iPhone Tailscale: pass/fail
- Android LAN pair/reconnect/status/raw/generated files: pass/fail
- Android interruption/resume/cancel: pass/fail
- Android Tailscale: pass/fail
- Windows NTFS drive-root/UNC/reparse/replacement race matrix: pass/fail
- Disposable outputs securely removed: pass/fail

## Publication

- `cli-signing` approver and timestamp:
- `cli-release` approver and timestamp:
- GitHub Release publication timestamp and asset count:
- Repository-wide latest remained Apple release: pass/fail
- crates.io `healthmd-protocol` checksum/index-visible timestamp:
- crates.io `healthmd-operations` checksum/index-visible timestamp:
- crates.io `healthmd-client` checksum/index-visible timestamp:
- crates.io `healthmd-mcp` checksum/index-visible timestamp:
- crates.io `healthmd-cli` checksum/index-visible timestamp:
- Homebrew tap commit:
- Homebrew macOS install/upgrade result:
- Linuxbrew install/upgrade result:

## Recovery actions

- Yank/unyank operations, exact crate/version, reason, approver, timestamp:
- Formula revert/correction commit and reason:
- Release withdrawal/replacement version and reason:
- Signing credential rotation/revocation references:

## Prohibited evidence

Do **not** record health values, samples, source records, clinical content, routes, credentials,
private keys, user filesystem paths, device owner names, raw payloads, or dates derived from a
user's health data. Redact command output rather than trying to review payloads after upload.
