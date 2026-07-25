# Health.md CLI distribution

## Status

- **Docs status:** active migration
- **Primary surfaces:** portable Rust `healthmd`, Health.md iPhone direct service, bundled macOS Swift `healthmd`/`healthmd-mcp`, and the Mac app loopback API

The portable CLI now lives in the separate
standalone Rust workspace at [`apps/cli`](../../../cli). It is
the cross-platform Manual IP/Tailscale client and uses `direct` by default. The bundled Swift helper
remains the macOS compatibility client for the Mac-app HTTP backend, MCP, and Apple-only Nearby
transport. Both clients speak the same direct protocol-v1 contract and must pass shared
Swift↔Rust fixtures before release.

## Packaging model

The compatible default remains a thin localhost client owned by the macOS app:

```text
healthmd CLI / healthmd-mcp stdio → 127.0.0.1:17645 → Health.md Mac app → connected/open iPhone app
```

The explicit `healthmd --backend direct` path instead owns an authenticated Manual IP/Tailscale or Nearby listener and connects to an opt-in, foreground iPhone service. It can receive strict raw data or commit production-generated files to an existing absolute `--destination` without opening the SwiftUI Mac app. It never reads HealthKit itself or silently falls back between backends/transports. Query/context/MCP remain Mac-app-only. See [Direct iPhone CLI backend](./cli-direct-iphone.md).

## Where the code lives

- `apps/cli`: standalone Rust workspace that builds portable `healthmd` archives,
  shell/PowerShell installers, and Homebrew formulae.
- `HealthMdCLI/`: macOS SwiftPM compatibility package that builds the bundled `healthmd` binary.
- `scripts/healthmd`: development wrapper that runs the Swift package from a repo checkout.
- `HealthMd/macOS/Managers/HealthMdControlServer.swift`: localhost HTTP server inside the Mac app.
- `HealthMd/macOS/Managers/MacIPhoneExportRequestCoordinator.swift`: Mac-side request coordinator.
- `HealthMd/iOS/IPhoneExportRequestHandler.swift`: iPhone HealthKit fetch/raw/file-export request handler.
- `HealthMd/Shared/Sync/CanonicalRawCLIModels.swift`: strict `healthmd.raw_result` v1 contract.
- `HealthMd/Shared/Sync/ConnectedTransfer.swift`: bounded, checksum-validated iPhone/Mac-app transport.
- `Packages/HealthMdConnectivity/`: shared direct pairing, transport, transfer, durable receiver, and safe file-commit package.
- `HealthMd/iOS/IPhoneDirectCLIService.swift`: opt-in foreground direct listener and trusted reconnect lifecycle.
- `HealthMd/iOS/IPhoneDirectExportCoordinator.swift`: protected direct raw capture and partition spool.
- `HealthMd/iOS/IPhoneDirectFileExportProducer.swift`: production-exporter staging for direct file mode.

## App bundle distribution

The Xcode project has first-class macOS command-line tool targets named `healthmd` and `healthmd-mcp`. They compile the same CLI, MCP core, and MCP entry-point sources used by the standalone SwiftPM package.

The `HealthMd-macOS` app target depends on both and embeds them with a signed-on-copy **Embed CLI Helper** copy phase at:

```text
Health.md.app/Contents/Helpers/healthmd
Health.md.app/Contents/Helpers/healthmd-mcp
```

Both targets use hardened runtime. `healthmd` is intentionally not App-Sandboxed because direct file mode must commit to an explicit user-supplied absolute destination; destination traversal, symlink, mutation, and digest protections are enforced in the receiver. `healthmd-mcp` remains App-Sandboxed with network-client-only entitlements. Its protocol surface additionally has no shell, arbitrary filesystem, arbitrary URL, resources, prompts, roots, sampling, or direct-iPhone capability.

The Mac app includes a dedicated **CLI** tab that shows the bundled path and provides:

- copyable aliases for both bundled helpers;
- a copyable agent prompt for installing `~/.local/bin/healthmd` and `~/.local/bin/healthmd-mcp` symlinks safely.
- an **Agent Skill** installer that copies bundled user-facing Health.md CLI guidance into a user-selected agent skills directory.
- command examples for status, file-writing exports, and raw JSON responses.

The app should not silently install the CLI into `/usr/local/bin` or mutate shell startup files. Users can opt into an alias, symlink, Homebrew install, or `make install-cli` from a checkout. Agent skill installation is also explicit: the user chooses the destination directory in a file picker, and Health.md only replaces its own known user-facing CLI skill folder there.

## Agent install prompt

Users can copy this prompt into an agent to install the bundled CLI without the app mutating shell files directly:

```text
Install the Health.md CLI and stdio MCP helper for my shell from the bundled Mac app. The signed sandboxed binaries are at:

/Applications/Health.md.app/Contents/Helpers/healthmd
/Applications/Health.md.app/Contents/Helpers/healthmd-mcp

Please:
1. Verify both files exist; run the CLI with `--help` without starting the MCP stdio loop interactively.
2. Create `~/.local/bin` if needed.
3. Create or replace symlinks for both helper names.
4. If `~/.local/bin` is not on PATH, tell me the exact shell config line to add, but do not edit shell config unless I explicitly approve.
5. Run `healthmd status` or `~/.local/bin/healthmd status` and summarize the JSON readiness.

Use bounded, non-interactive commands. Do not modify Health.md export files.
```

## Agent skill install

The app bundles one optional, agent-agnostic, user-facing skill file as a resource:

- `healthmd-cli.skill.md`

This installable skill is for users and consumers of the CLI. It teaches agents how to install/verify the `healthmd` command, run status and export commands, request raw JSON, read CLI JSON, and troubleshoot Mac/iPhone readiness. It intentionally avoids developer-focused instructions for changing Health.md source code, sync protocols, or tests.

Users can install or update it from the CLI tab using the same pattern as CLI installation: an **Agent Prompt** tab for agent-assisted setup and a **Manual** tab for direct installation. The manual tab can open a folder picker for the skills directory or copy a shell command with an editable `SKILLS_DIR`. The app creates `healthmd-cli/SKILL.md` and replaces an existing `healthmd-cli` folder so updates stay current.

Users can also copy an agent prompt from the CLI tab that asks any automation-capable coding agent to copy the bundled `.skill.md` file manually into `healthmd-cli/SKILL.md`.

## Portable standalone install

After the first stable Rust release (prereleases use direct GitHub installers):

```bash
brew install CodyBontecou/tap/healthmd
```

GitHub Releases also provide checksummed macOS/Linux/Windows archives plus shell and PowerShell
installers. Protocol-v1 raw export, extract, status, resume, and cancellation work on all three
platforms. Generated-file destination commits work on macOS and Linux; Windows requires the future
protocol-v2 logical destination contract because v1 carries Unix absolute paths.

The portable client uses Manual IP/Tailscale only. It does not include the Mac-app HTTP/MCP surface
or Apple's Nearby framework.

## Bundled Swift helper install

From this app repository checkout:

```bash
make cli
make install-cli
```

By default this installs both helpers:

```text
~/.local/bin/healthmd
~/.local/bin/healthmd-mcp
```

Override with:

```bash
make install-cli CLI_INSTALL_DIR=/usr/local/bin
```

`make install-cli` ad-hoc signs both binaries with hardened runtime and their target-specific entitlements; the installed `healthmd-mcp` therefore keeps its App Sandbox while `healthmd` keeps only the network authority needed for direct listeners. The same Swift package can be used later for a Homebrew formula or GitHub release artifact, but packaged artifacts must preserve that signing split.

## Commands

```bash
healthmd status
healthmd export --iphone --yesterday
healthmd export --iphone --yesterday --raw
healthmd export --iphone --last 7 --raw --allow-partial
healthmd export --iphone --last 7
healthmd export --iphone --from 2026-06-01 --to 2026-06-07
healthmd export --iphone --yesterday --use-iphone-settings

healthmd direct pair --transport manual-ip
healthmd --backend direct status
healthmd --backend direct export --yesterday --raw --output yesterday.json
healthmd --backend direct export --yesterday --destination "$HOME/Documents/HealthVault"
```

## Safety constraints

- Keep the control server bound to IPv4/IPv6 loopback and reject non-loopback peer endpoints. Loopback is the complete `/v1/agent/*` access boundary; never expose or proxy it to another machine.
- Keep bounded request headers/bodies, a finite receive deadline, strict method/content-type checks, and the documented 5...900-second export timeout range.
- Keep HealthKit reads on iPhone.
- Keep default-backend file writes in the Mac app. Direct file mode may write only to the explicit validated `--destination` and must preserve restart-safe commit semantics.
- Keep backend and direct transport selection explicit; never silently fall back.
- Keep Direct CLI Access opt-in, authenticated, encrypted, and isolated from Mac-app sync trust. Pairing and new commands remain foreground-scoped; only an already-connected export may use finite iOS background execution time.
- `--raw` uses `canonical_source_records_v1`, temporarily forces lossless capture without changing saved `includeGranularData`, and returns schema-v7 daily documents in `healthmd.raw_result` v1.
- Strict raw exits non-zero on `partial_success` unless `--allow-partial` is explicit. Complete-empty remains success; unsupported/skipped/cancelled/missing branches remain partial.
- Strict raw and current file jobs require bounded, checksum-validated connected transfer and never downgrade to an unbounded whole raw payload.
- Raw responses can contain source/device details, clinical content, ECGs, routes, and base64 attachments. Do not log them. Current peers spool and validate corpus-scale responses on disk, but one dense day and available storage remain practical limits.
- Bundled CLI install/setup should remain explicit and user-initiated.
