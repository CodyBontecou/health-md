# Releasing

`dist` 0.31.0 generates checksummed archives and installers for:

- Apple silicon and Intel macOS signed archives plus notarized, stapled DMGs
- ARM64 and x86-64 Linux archives
- Authenticode-signed x86-64 Windows archives
- POSIX shell and PowerShell
- Homebrew/Linuxbrew formulae

Published crates support `cargo install`; cargo-binstall can consume the matching GitHub archives.
Cargo-dist's fallback source tarball is disabled because a single-workspace archive cannot contain
the independently locked shared-protocol path dependency. The four extracted and MSRV-tested
crates.io archives are the portable source distribution. Winget and Scoop publication are not configured. Do not advertise package IDs until their upstream
manifests have been accepted. crates.io publication is a separate staged process described below.

## One-time repository setup

1. Keep the CLI workspace under `apps/cli` and its shared `healthmd-protocol` dependency under the independently locked `packages/healthmd-core-rust` workspace in `CodyBontecou/health-md`.
2. Create and initialize `CodyBontecou/homebrew-tap`.
3. Add a fine-grained token with contents write permission for that tap as the
   `HOMEBREW_TAP_TOKEN` Actions secret in `health-md`.
4. Protect the `cli-release` GitHub environment with required reviewers. Approval is the final evidence gate after exact-candidate CI, native archive smoke tests, checksums, and SBOMs have passed.
5. Protect the `crates-io` environment. Configure crates.io Trusted Publishing for all four crates with workflow `cli-publish-crates.yml` and this environment. A short-lived `CARGO_REGISTRY_TOKEN` is allowed only for the first `bootstrap-token` publication; remove it afterward.
6. Create a protected `cli-signing` environment and configure the Apple and Azure identities in
   the next section. Signing is mandatory on release tags; missing or invalid credentials leave the
   release as a draft. Pull requests continue to build and smoke unsigned candidates without access
   to signing credentials.

Homebrew publishing is intentionally disabled for prereleases by dist. Stable release formulae are
installed with:

```bash
brew install CodyBontecou/tap/healthmd
```

## Signing, notarization, and checksum identity

The release workflow does not accept unsigned tag artifacts. It signs the two Mach-O executables,
submits an architecture-specific DMG to Apple's notary service, staples and validates that DMG,
and then reconstructs the matching tar archive from the byte-identical signed executables. Apple
publishes tickets for the nested standalone binaries, but Apple does not support stapling a ticket
directly to a standalone executable or tar/ZIP archive; the DMG is the offline-stapled
installation artifact. The workflow applies Azure Artifact Signing Authenticode signatures and an
RFC 3161 timestamp to both Windows executables before rebuilding the ZIP, then signs the generated
PowerShell installer before sealing the final checksum manifest.

Configure these **repository variables**:

| Variable | Value |
|---|---|
| `CLI_APPLE_TEAM_ID` | The Team ID on the Developer ID Application certificate. |
| `CLI_AZURE_SIGNING_ENDPOINT` | Regional Azure Artifact Signing endpoint. |
| `CLI_AZURE_SIGNING_ACCOUNT` | Artifact Signing account name. |
| `CLI_AZURE_SIGNING_PROFILE` | Public-trust certificate profile name. |
| `CLI_WINDOWS_SIGNER_SUBJECT` | Exact case-sensitive `SignerCertificate.Subject` expected from Authenticode verification. |

Configure these **`cli-signing` environment secrets**:

| Secret | Value |
|---|---|
| `APPLE_CLI_CERTIFICATE_P12` | Base64 PKCS#12 containing exactly one Developer ID Application identity for `CLI_APPLE_TEAM_ID`. |
| `APPLE_CLI_CERTIFICATE_PASSWORD` | PKCS#12 export password. |
| `APPLE_NOTARY_KEY_P8_BASE64` | Base64 App Store Connect API private key with notary access. |
| `APPLE_NOTARY_KEY_ID` | App Store Connect API key ID. |
| `APPLE_NOTARY_ISSUER_ID` | App Store Connect API issuer UUID. |
| `AZURE_CLIENT_ID` | Entra application/client ID used by GitHub OIDC. |
| `AZURE_TENANT_ID` | Entra tenant ID. |
| `AZURE_SUBSCRIPTION_ID` | Azure subscription containing the signing account. |

Give the Entra principal the **Artifact Signing Certificate Profile Signer** role only on the
selected profile. Add a federated credential for the GitHub environment subject
`repo:CodyBontecou/health-md:environment:cli-signing`; do not create a long-lived Azure client
secret. Protect `cli-signing` with required reviewers and restrict it to
`healthmd-cli/v*` tags. Before creating the first tag, commit the exact public certificate subject
as `windows.publisher_subject` in `release-identities.json`, set its status to `qualified`, and make
`CLI_WINDOWS_SIGNER_SUBJECT` match exactly. `verify-release.py` blocks tags while that public
identity remains pending, and native signing jobs compare the committed ledger with the certificate.
The separate `cli-release` environment remains the final publication approval after all signature
and artifact qualification jobs pass.

Both macOS executables use stable signing identifiers (`md.health.cli.healthmd` and
`md.health.cli.healthmd-mcp`). The signing job creates a synthetic health-free native-trust fixture,
grants its Keychain ACL to an independently signed previous copy, and proves the release copy reads
the exact fixed device identity through the real bounded same-executable credential helper without
a prompt. The Windows signing runner independently writes the same synthetic fixture under the deployed Credential Manager target
and proves the signed release reads it through its supervised helper. Together these verify normal
signed-binary upgrades and the legacy Swift service/account mapping. A user moving from an ad-hoc/unsigned development binary to the
Developer ID identity is crossing principals and must explicitly unpair/re-pair once; installers
must never delete or silently migrate trust.

`sha256.sum` covers all five binary archives, both notarized DMGs, both generated installers, the
Homebrew formula, the public signing-identity ledger, every per-artifact checksum, and the three
SBOM assets. The workflow signs it with a
keyless Sigstore identity and publishes `sha256.sum.sigstore.json`. Verify a downloaded release
with the exact tag identity before trusting its checksums:

```bash
tag='healthmd-cli/v0.1.0-alpha.1'
cosign verify-blob \
  --bundle sha256.sum.sigstore.json \
  --certificate-identity "https://github.com/CodyBontecou/health-md/.github/workflows/cli-release.yml@refs/tags/$tag" \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  sha256.sum
sha256sum --check sha256.sum  # after downloading every listed asset
```

For a single installer, first verify the same manifest signature, then compare that installer's
SHA-256 with its exact manifest row as shown in the README. On Windows, also require `Status=Valid`
and match `SignerCertificate.Subject` to the `qualified` subject in the checksum-covered
`release-identities.json`; never accept an undocumented publisher.

Native post-extraction gates independently require `codesign` plus Gatekeeper assessment on both
macOS binaries, `stapler validate` plus Gatekeeper assessment on each DMG, and a valid expected
Authenticode signer plus timestamp on both Windows executables and the PowerShell installer. A checksum, signing, notarization,
stapling, credential-upgrade, or post-extraction failure leaves the GitHub Release in draft state.

## Release checks

Run the shared-core workspace without touching the CLI lockfile:

```bash
cd packages/healthmd-core-rust
cargo fmt --all --check
cargo clippy --workspace --all-targets --all-features --locked -- -D warnings
cargo test --workspace --all-features --locked
rustup run 1.85.0 cargo check \
  -p healthmd-core -p healthmd-protocol -p healthmd-core-uniffi \
  --all-features --locked
```

Then run `make check-core-bindings` from the repository root and validate the independently locked CLI workspace:

```bash
cd apps/cli
cargo fmt --all --check
cargo clippy --workspace --all-targets --locked -- -D warnings
cargo test --workspace --locked
rustup run 1.85.0 cargo check --workspace --locked
cargo clippy --workspace --all-targets --all-features --locked -- -D warnings
cargo test --workspace --all-features --locked
rustup run 1.85.0 cargo check --workspace --all-features --locked
rustup run 1.85.0 cargo check -p healthmd-cli --all-targets \
  --no-default-features --features streamable-http --locked
python3 scripts/verify-release.py
version="$(cargo metadata --no-deps --format-version=1 | jq -r '.packages[] | select(.name == "healthmd-cli") | .version')"
python3 scripts/smoke-crate-packages.py --version "$version"
cargo deny --manifest-path Cargo.toml --config ../../deny.toml check
dist generate --check
dist plan --allow-dirty
dist build --allow-dirty --artifacts=local --target="$(rustc -vV | awk '/host:/ {print $2}')"
```

Distribution builds intentionally use the empty default feature set: shipped binaries expose local
stdio/direct-iPhone MCP but not `serve-http` or OAuth. The optional direct-backed HTTP transport is
source-build-only and is never added to release archives implicitly. Health.md has no synchronized
remote health-data corpus command.

Review generated artifacts and checksums under `apps/cli/target/distrib`, and review the
[mobile compatibility ledger](mobile-compatibility.md). The first public release remains blocked
until every supported row contains the exact machine-checked qualified record and evidence digest
documented there. `verify-release.py` rejects a `healthmd-cli/v<version>` tag while any row is
pending or malformed. The tag must point to the exact current `main` commit. It triggers
`.github/workflows/cli-release.yml`, which creates a draft, reruns CLI/core/Apple/Android gates at
the tag SHA, executes every packaged binary on its native runner, validates installers and
checksums, builds SBOMs, and then waits for approval on the protected `cli-release` environment.
Only that final job changes the draft to public, with `make_latest=false` so Apple remains the
repository-wide latest release. Never publish an artifact built from uncommitted source.

The root workflow is a path-adjusted version of cargo-dist's generated workflow. After changing
`dist-workspace.toml`, generate into a temporary checkout and port relevant changes into
`.github/workflows/cli-release.yml`; do not replace its monorepo working directories and tag filter.

## crates.io staging

After the GitHub release is public, run the protected **CLI Publish crates.io** workflow on the
exact `healthmd-cli/v<version>` tag and type its explicit confirmation. Use `trusted-publishing`
unless performing the one-time bootstrap. The workflow validates the tag, public release, `main`
ancestry, all eight package versions, both lockfiles, exact internal requirements, and publication
policy before testing both workspaces and their extracted `.crate` archives.

Publication is retry-safe. For each crate in protocol → operations → client → MCP → CLI order, the workflow
packages the local source, checks whether the exact version already exists, and compares the downloaded
registry archive byte-for-byte. An identical archive is accepted; a checksum mismatch fails
closed. If `cargo publish` returns an unknown outcome, the workflow polls and performs the same
checksum comparison before proceeding.

Internal path dependencies carry exact versions, so crates must be published in dependency order and allowed to propagate through the index before publishing the next crate. Run these from the repository root. `healthmd-protocol`
is published from the shared-core workspace before the four CLI-workspace crates:

```bash
cargo publish --manifest-path packages/healthmd-core-rust/crates/healthmd-protocol/Cargo.toml --locked --dry-run
cargo publish --manifest-path packages/healthmd-core-rust/crates/healthmd-protocol/Cargo.toml --locked
# Wait until: cargo search healthmd-protocol --limit 1

cargo publish --manifest-path apps/cli/crates/healthmd-operations/Cargo.toml --locked --dry-run
cargo publish --manifest-path apps/cli/crates/healthmd-operations/Cargo.toml --locked
# Wait until: cargo search healthmd-operations --limit 1

cargo publish --manifest-path apps/cli/crates/healthmd-client/Cargo.toml --locked --dry-run
cargo publish --manifest-path apps/cli/crates/healthmd-client/Cargo.toml --locked
# Wait until: cargo search healthmd-client --limit 1

cargo publish --manifest-path apps/cli/crates/healthmd-mcp/Cargo.toml --locked --dry-run
cargo publish --manifest-path apps/cli/crates/healthmd-mcp/Cargo.toml --locked
# Wait until: cargo search healthmd-mcp --limit 1

cargo publish --manifest-path apps/cli/crates/healthmd-cli/Cargo.toml --locked --dry-run
cargo publish --manifest-path apps/cli/crates/healthmd-cli/Cargo.toml --locked
```

A failed downstream `cargo package --workspace` before the first staged publication is expected:
Cargo verifies the exact internal version against crates.io after stripping local path hints.

## Release evidence

The release workflow embeds auditable dependency metadata and creates GitHub build-provenance
attestations with `id-token: write`. Before public finalization, its reusable `CLI Release SBOM`
gate verifies the captured tag/SHA identity, stages the CLI and shared-protocol source trees,
generates SPDX and CycloneDX source SBOMs, attests them, and adds both SBOMs plus their SHA-256
file to the draft. A failed SBOM or archive qualification leaves the release in draft state.

Pull-request candidates remain unsigned and must never be described as releases. Tag builds require
Developer ID/notarization, Authenticode, and a Sigstore-signed checksum closure. Do not call even an
alpha release complete until the protected signing identities are provisioned and the exact
candidate's native signature gates have executed successfully.

Use the [health-free release evidence template](release-evidence-template.md) for every candidate.
It records exact source/mobile/artifact identity, signatures, qualification, publication, and
recovery events without health values, user paths, credentials, or raw command payloads.

## Rollback and withdrawal

A draft that fails any gate stays draft: stop there, retain the run as evidence, and do not upload
hand-built replacements. If a release is already public:

1. Stop advertising the affected exact tag and identify the last known-good exact tag.
2. Do not move the Git tag or replace assets in place. Any changed bytes require a new version,
   checksums, signatures, attestations, qualification, and release.
3. Publish a corrected patch release. Preserve durable identity/job state and never reinterpret peer
   bindings, request fingerprints, destinations, manifests, or committed frontiers.
4. Resume old jobs only when the rollback binary is demonstrably wire- and state-compatible. Leave
   uncertain jobs paused and document the recovery decision; never delete unknown-outcome state.
5. Treat files already committed to a destination as immutable evidence. Remediation is an explicit
   re-export, not a silent rewrite.
6. Correct GitHub, crates.io, and Homebrew independently. Withdrawing a GitHub Release neither yanks
   crates nor repairs the tap.

Record the affected tag/assets, decision, replacement version, approver, and timestamps in the
release evidence. Preserve published history unless removal is required to protect users.

## Signing-key compromise

Treat suspected key access as an incident, not an ordinary failed release:

1. Disable or freeze the `cli-signing`, `cli-release`, `crates-io`, and Homebrew publication paths.
2. Revoke/rotate the Developer ID certificate and App Store Connect notary key. Disable the Azure
   Artifact Signing profile or compromised role/federated credential. Rotate the Homebrew token,
   bootstrap crates.io token if one exists, and affected GitHub credentials.
3. Audit GitHub Actions, Apple, Azure, Sigstore transparency, crates.io, and tap history for the
   exposure window. Inventory every tag, archive, DMG, installer, formula, checksum bundle, and crate
   version that may have been signed or published.
4. Quarantine or withdraw affected assets according to the incident decision, yank affected crates,
   and publish a new version with new signing identities. Never reuse or overwrite the old version.
5. Tell users the exact affected versions and require verification of both the exact tag and Cosign
   workflow identity. A plain SHA-256 digest or later key rotation does not retroactively validate an
   old binary.

Do not paste certificate private keys, API keys, tokens, health output, or unredacted notary/build
logs into issues or release evidence.

## crates.io yank and recovery

Yanking prevents new dependency resolution but does not erase the immutable crate archive or break
existing lockfiles. For a broken coordinated release, review and yank all four exact versions in
dependency order from a protected operator environment:

```bash
version='0.1.0-alpha.1'
cargo yank --vers "$version" healthmd-cli
cargo yank --vers "$version" healthmd-mcp
cargo yank --vers "$version" healthmd-client
cargo yank --vers "$version" healthmd-operations
cargo yank --vers "$version" healthmd-protocol
```

Publish a corrected patch version; crates.io does not permit overwriting. If a yank was mistaken,
restore only after review with `cargo yank --undo --vers "$version" CRATE`. Record each crate,
version, reason, registry/index observation, approver, and yank/undo timestamp. GitHub assets and the
Homebrew formula still require their own recovery decisions.

## Homebrew publication recovery

A GitHub Release can be public even if the final tap update fails. Inspect the failed
`publish-homebrew-formula` job, retrieve the sealed `healthmd.rb` workflow artifact, and verify its
versioned (never `/releases/latest`) URLs and archive hashes against the Sigstore-verified
`sha256.sum`. Run `brew style`, applicable `brew audit`, and clean install/upgrade tests on macOS and
Linux before committing the formula idempotently to `CodyBontecou/homebrew-tap`.

If the formula is wrong, revert its tap commit or publish a reviewed correction; never mutate the
release archives. User recovery is `brew update`, `brew upgrade healthmd`, or `brew uninstall
healthmd` followed by a verified reinstall. Remove the tap only when intended with `brew untap
CodyBontecou/tap`. Homebrew is not a Windows recovery path; use the exact versioned signed ZIP or
PowerShell installer there. Record the tap commit and install/upgrade results in release evidence.
