# Health.md CLI distribution

## Status

- **Docs status:** draft
- **Primary surfaces:** Health.md macOS app, bundled `healthmd` binary, standalone Swift package under `HealthMdCLI/`, development wrapper at `scripts/healthmd`

## Packaging model

The Health.md CLI is a thin localhost client. The macOS app remains the service owner:

```text
healthmd CLI → 127.0.0.1:17645 → Health.md Mac app → connected/open iPhone app
```

The CLI does not read HealthKit, manage Multipeer, write export files directly, or access sandbox bookmarks. It only sends JSON requests to the running Mac app.

## Where the code lives

- `HealthMdCLI/` — standalone SwiftPM executable package that builds the `healthmd` binary.
- `scripts/healthmd` — development wrapper that runs the Swift package from a repo checkout.
- `HealthMd/macOS/Managers/HealthMdControlServer.swift` — localhost HTTP server inside the Mac app.
- `HealthMd/macOS/Managers/MacIPhoneExportRequestCoordinator.swift` — Mac-side request coordinator.
- `HealthMd/iOS/IPhoneExportRequestHandler.swift` — iPhone HealthKit fetch/raw/file-export request handler.

## App bundle distribution

The Xcode project has a first-class macOS command-line tool target named `healthmd`. It compiles the same source used by the standalone SwiftPM package:

```text
HealthMdCLI/Sources/healthmd/main.swift
```

The `HealthMd-macOS` app target depends on that tool target and embeds it with a signed-on-copy **Embed CLI Helper** copy phase at:

```text
Health.md.app/Contents/Helpers/healthmd
```

The CLI target has sandbox/network-client entitlements so the nested executable is signed as normal app bundle code for distribution.

The Mac app includes a dedicated **CLI** tab that shows the bundled path and provides:

- a copyable alias command:
  ```bash
  alias healthmd="/Applications/Health.md.app/Contents/Helpers/healthmd"
  ```
- a copyable agent prompt for installing a `~/.local/bin/healthmd` symlink safely.
- command examples for status, file-writing exports, and raw JSON responses.

The app should not silently install the CLI into `/usr/local/bin` or mutate shell startup files. Users can opt into an alias, symlink, Homebrew install, or `make install-cli` from a checkout.

## Agent install prompt

Users can copy this prompt into an agent to install the bundled CLI without the app mutating shell files directly:

```text
Install the Health.md CLI for my shell from the bundled Mac app. The CLI binary is at:

/Applications/Health.md.app/Contents/Helpers/healthmd

Please:
1. Verify that file exists and runs with `--help`.
2. Create `~/.local/bin` if needed.
3. Create or replace a symlink at `~/.local/bin/healthmd` pointing to the bundled CLI.
4. If `~/.local/bin` is not on PATH, tell me the exact shell config line to add, but do not edit shell config unless I explicitly approve.
5. Run `healthmd status` or `~/.local/bin/healthmd status` and summarize the JSON readiness.

Use bounded, non-interactive commands. Do not modify Health.md export files.
```

## Standalone install

From a repo checkout:

```bash
make cli
make install-cli
```

By default this installs to:

```text
~/.local/bin/healthmd
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
healthmd export --iphone --last 7
healthmd export --iphone --from 2026-06-01 --to 2026-06-07
healthmd export --iphone --yesterday --use-iphone-settings
```

## Safety constraints

- Keep the control server bound to localhost.
- Keep HealthKit reads on iPhone.
- Keep file writes in the Mac app.
- Raw responses can contain health data; do not log raw payloads from the Mac app.
- Bundled CLI install/setup should remain explicit and user-initiated.
