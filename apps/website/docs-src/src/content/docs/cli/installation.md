---
title: "Install the Health.md CLI"
description: "Install healthmd and healthmd-mcp with Homebrew, the Health.md Mac app, a versioned release installer, or Cargo."
---

Choose one installation method. The standalone CLI is a public preview for macOS, Linux, and Windows. The Health.md Mac app also includes signed helpers for Mac users.

## Homebrew

Homebrew is the shortest path on macOS or Linux:

```bash
brew install CodyBontecou/tap/healthmd
healthmd --version
```

The formula installs both `healthmd` and the `healthmd-mcp` compatibility launcher from the same versioned CLI release.

To upgrade later:

```bash
brew update
brew upgrade healthmd
```

## Health.md for Mac

Health.md for Mac includes signed `healthmd` and `healthmd-mcp` helpers. Open the Mac app and select **CLI** to see the commands for your installed copy.

The normal app bundle paths are:

```text
/Applications/Health.md.app/Contents/Helpers/healthmd
/Applications/Health.md.app/Contents/Helpers/healthmd-mcp
```

To make them available in every terminal session, create symlinks in a user-owned bin directory:

```bash
mkdir -p ~/.local/bin
ln -sf "/Applications/Health.md.app/Contents/Helpers/healthmd" ~/.local/bin/healthmd
ln -sf "/Applications/Health.md.app/Contents/Helpers/healthmd-mcp" ~/.local/bin/healthmd-mcp
```

Add `~/.local/bin` to `PATH` if your shell does not already include it.

## Release installers and Cargo

Each exact `healthmd-cli/v<version>` release can include checksummed installers and archives for macOS, Linux, and Windows. Follow the [release verification and installation instructions](https://github.com/CodyBontecou/health-md/tree/main/apps/cli#installation) rather than the repository-wide latest-release link, which is reserved for the Apple apps.

After an exact version reaches crates.io, Rust users can install it with:

```bash
cargo install healthmd-cli --locked
```

## Verify the installation

These commands are local and do not contact a phone:

```bash
healthmd --version
healthmd --help
```

Both should resolve to the same installation you intended to use:

```bash
command -v healthmd
command -v healthmd-mcp
```

## Next step

Pair an open Health.md app on iPhone or Android:

```bash
healthmd direct pair --transport manual-ip
```

Or configure a supported local AI host and begin pairing in one flow:

```bash
healthmd setup codex
```

See [Direct phone CLI](/docs/cli-direct/) for mobile requirements, transport behavior, and the current preview compatibility matrix.
