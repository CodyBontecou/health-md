# Releasing

`dist` 0.31.0 generates checksummed archives and installers for:

- Apple silicon and Intel macOS
- ARM64 and x86-64 Linux
- x86-64 Windows
- POSIX shell and PowerShell
- Homebrew/Linuxbrew formulae

Published crates support `cargo install`; cargo-binstall can consume the matching GitHub archives.
Winget and Scoop publication are not configured. Do not advertise package IDs until their upstream
manifests have been accepted. crates.io publication is a separate staged process described below.

## One-time repository setup

1. Keep the CLI workspace under `apps/cli` in `CodyBontecou/health-md`.
2. Create and initialize `CodyBontecou/homebrew-tap`.
3. Add a fine-grained token with contents write permission for that tap as the
   `HOMEBREW_TAP_TOKEN` Actions secret in `health-md`.
4. For the first publication, add a short-lived crates.io API token with new-crate publishing scope as `CARGO_REGISTRY_TOKEN` in the protected `crates-io` GitHub environment. After all three crates exist, configure crates.io Trusted Publishing for `cli-publish-crates.yml` and remove the bootstrap token.
5. Configure macOS signing/notarization and Windows Authenticode secrets before declaring stable
   artifacts. Unsigned alpha artifacts must be labeled as such.

Homebrew publishing is intentionally disabled for prereleases by dist. Stable release formulae are
installed with:

```bash
brew install CodyBontecou/tap/healthmd
```

## Release checks

```bash
cargo fmt --all --check
cargo clippy --workspace --all-targets --all-features -- -D warnings
cargo test --workspace --all-features
rustup run 1.85.0 cargo check --workspace --all-features --locked
dist generate --check
dist plan --allow-dirty
dist build --allow-dirty --artifacts=local --target="$(rustc -vV | awk '/host:/ {print $2}')"
```

Review generated artifacts and checksums under `target/distrib`. A
`healthmd-cli/v<version>` tag triggers `.github/workflows/cli-release.yml` at the monorepo root.
Never publish an artifact built from uncommitted source.

The root workflow is a path-adjusted version of cargo-dist's generated workflow. After changing
`dist-workspace.toml`, generate into a temporary checkout and port relevant changes into
`.github/workflows/cli-release.yml`; do not replace its monorepo working directories and tag filter.

## crates.io staging

Run the protected **CLI Publish crates.io** workflow on the exact `healthmd-cli/v<version>` tag and type its explicit
confirmation. The workflow validates the ref/version, tests the workspace, and waits for index
propagation between packages.

Internal path dependencies carry exact versions, so crates must be published in dependency order
and allowed to propagate through the index before publishing the next crate:

```bash
cargo publish -p healthmd-protocol --dry-run
cargo publish -p healthmd-protocol
# Wait until: cargo search healthmd-protocol --limit 1

cargo publish -p healthmd-client --dry-run
cargo publish -p healthmd-client
# Wait until: cargo search healthmd-client --limit 1

cargo publish -p healthmd-cli --dry-run
cargo publish -p healthmd-cli
```

A failed downstream `cargo package --workspace` before the first staged publication is expected:
Cargo verifies the exact internal version against crates.io after stripping local path hints.

## Release evidence

The generated workflow embeds auditable dependency metadata and creates GitHub build-provenance
attestations with `id-token: write`. After a successful tag release, `Release SBOM` verifies that the
tag, workspace version, commit, and GitHub Release agree; generates SPDX and CycloneDX source SBOMs;
attests them; and uploads both SBOMs plus their SHA-256 file to that release.

Alpha archives remain unsigned and must be labeled accordingly. Do not call a stable release complete
until macOS signing/notarization, Windows Authenticode, and signed checksums are configured and
verified.
