# GitHub Actions for macOS App Releases

Automated build, notarization, and publishing of macOS apps to [isolated.tech](https://isolated.tech).

## Overview

When you create a GitHub release, this workflow will:

1. **Build** the macOS app with Xcode
2. **Sign** the app with your Developer ID certificate
3. **Notarize** the app with Apple
4. **Publish** to isolated.tech (triggers Sparkle auto-updates)
5. **Attach** the release zip to the GitHub release

## Setup

### Required Secrets

Add these secrets to your repository (Settings → Secrets and variables → Actions):

| Secret | Description | How to get it |
|--------|-------------|---------------|
| `ISOLATED_API_KEY` | API key for isolated.tech | Run `isolated login`, then copy token from `~/.isolated/credentials.json` |
| `SPARKLE_ED_PRIVATE_KEY` | EdDSA private key for Sparkle signing | Base64-encoded. From Keychain or `~/.config/sparkle/ed25519_private.key` |
| `APPLE_CERTIFICATE_P12` | Developer ID Application certificate | Export from Keychain Access as .p12, then base64 encode |
| `APPLE_CERTIFICATE_PASSWORD` | Password for the .p12 file | The password you set when exporting |
| `APPLE_ID` | Your Apple ID email | Your Apple Developer account email |
| `APPLE_ID_PASSWORD` | App-specific password | Create at [appleid.apple.com](https://appleid.apple.com/account/manage) |
| `APPLE_TEAM_ID` | Apple Developer Team ID | Found in [developer.apple.com](https://developer.apple.com/account) membership details |

### Getting Your Secrets

#### ISOLATED_API_KEY

```bash
isolated login
cat ~/.isolated/credentials.json | jq -r '.token'
```

#### SPARKLE_ED_PRIVATE_KEY

```bash
# From Keychain
security find-generic-password -s "Sparkle EdDSA Key" -w | base64

# Or from file
cat ~/.config/sparkle/ed25519_private.key
```

#### APPLE_CERTIFICATE_P12

1. Open **Keychain Access**
2. Find your "Developer ID Application" certificate
3. Right-click → Export Items → Save as .p12
4. Base64 encode: `base64 -i ~/Downloads/Certificates.p12 | pbcopy`

#### APPLE_ID_PASSWORD

1. Go to [appleid.apple.com](https://appleid.apple.com/account/manage)
2. Sign in → Security → App-Specific Passwords
3. Generate a new password for "GitHub Actions"

## Usage

### Creating a Release

1. Update your version in Xcode
2. Create a new GitHub release with a tag like `v1.2.3`
3. Add release notes (these become Sparkle update notes)
4. Publish

### Manual Trigger

Trigger from the Actions tab with dry-run option to test without publishing.

## Reusable Workflow

This workflow uses the reusable workflow from [isolated-tech-website](https://github.com/CodyBontecou/isolated-tech-website).

To use it in other repos:

```yaml
name: Release macOS

on:
  release:
    types: [published]

jobs:
  release:
    uses: CodyBontecou/isolated-tech-website/.github/workflows/release-macos.yml@main
    with:
      xcode-scheme: MyApp-macOS
      app-name: MyApp
      isolated-slug: myapp
    secrets: inherit
```
