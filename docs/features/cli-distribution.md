# Health.md CLI distribution

## Status

- **Docs status:** draft
- **Primary surfaces:** Health.md macOS app, bundled `healthmd` and `healthmd-mcp` binaries, standalone Swift package under `HealthMdCLI/`, development wrapper at `scripts/healthmd`

## Packaging model

The Health.md CLI is a thin localhost client. The macOS app remains the service owner:

```text
healthmd CLI / healthmd-mcp stdio → 127.0.0.1:17645 → Health.md Mac app → connected/open iPhone app
```

The CLI does not read HealthKit, manage Multipeer, write export files directly, or access sandbox bookmarks. It only sends JSON requests to the running Mac app.

## Where the code lives

- `HealthMdCLI/`: standalone SwiftPM executable package that builds the `healthmd` binary.
- `scripts/healthmd`: development wrapper that runs the Swift package from a repo checkout.
- `HealthMd/macOS/Managers/HealthMdControlServer.swift`: localhost HTTP server inside the Mac app.
- `HealthMd/macOS/Managers/MacIPhoneExportRequestCoordinator.swift`: Mac-side request coordinator.
- `HealthMd/iOS/IPhoneExportRequestHandler.swift`: iPhone HealthKit fetch/raw/file-export request handler.
- `HealthMd/Shared/Sync/CanonicalRawCLIModels.swift`: strict `healthmd.raw_result` v1 contract.
- `HealthMd/Shared/Sync/ConnectedTransfer.swift`: bounded, checksum-validated iPhone/Mac transport.

## App bundle distribution

The Xcode project has first-class macOS command-line tool targets named `healthmd` and `healthmd-mcp`. They compile the same CLI, MCP core, and MCP entry-point sources used by the standalone SwiftPM package.

The `HealthMd-macOS` app target depends on both and embeds them with a signed-on-copy **Embed CLI Helper** copy phase at:

```text
Health.md.app/Contents/Helpers/healthmd
Health.md.app/Contents/Helpers/healthmd-mcp
```

Both targets use App Sandbox with network-client-only entitlements and hardened runtime. The MCP helper's own protocol surface additionally has no shell, arbitrary filesystem, arbitrary URL, resources, prompts, roots, or sampling capability.

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

## Standalone install

From a repo checkout:

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

The same Swift package can be used later for a Homebrew formula or GitHub release artifact.

## Commands

```bash
healthmd status
healthmd export --iphone --yesterday
healthmd export --iphone --yesterday --raw
healthmd export --iphone --last 7 --raw --allow-partial
healthmd export --iphone --last 7
healthmd export --iphone --from 2026-06-01 --to 2026-06-07
healthmd export --iphone --yesterday --use-iphone-settings
```

## Safety constraints

- Keep the control server bound to IPv4/IPv6 loopback and reject non-loopback peer endpoints. Loopback is a network boundary, not agent identity; `/v1/agent/*` requires a registered bearer, exact grant, and profile.
- Keep bounded request headers/bodies, a finite receive deadline, strict method/content-type checks, and the documented 5...900-second export timeout range.
- Keep HealthKit reads on iPhone.
- Keep file writes in the Mac app.
- `--raw` uses `canonical_source_records_v1`, temporarily forces lossless capture without changing saved `includeGranularData`, and returns schema-v7 daily documents in `healthmd.raw_result` v1.
- Strict raw exits non-zero on `partial_success` unless `--allow-partial` is explicit. Complete-empty remains success; unsupported/skipped/cancelled/missing branches remain partial.
- Strict raw and current file jobs require bounded, checksum-validated connected transfer and never downgrade to an unbounded whole raw payload.
- Raw responses can contain source/device details, clinical content, ECGs, routes, and base64 attachments. Do not log them. Final response serialization can still use substantial memory; request smaller ranges.
- Bundled CLI install/setup should remain explicit and user-initiated.
