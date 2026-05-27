# GitHub Actions release pipeline

Health.md ships iOS and macOS builds to App Store Connect from GitHub Actions.

## Trigger

Publishing a GitHub Release whose tag starts with `v` (for example `v2.1.3`) starts both release workflows:

- `.github/workflows/release-ios.yml`
- `.github/workflows/release-macos.yml`

The tag version must match `MARKETING_VERSION` in `HealthMd.xcodeproj`; the workflow fails early if it does not.

## What the workflows do

1. Build and sign the iOS `.ipa` and macOS App Store `.pkg`.
2. Upload each build to App Store Connect with `asc builds upload`.
3. Create the matching ASC version and submit it for review.
4. Attach the notarized macOS Developer ID zip to the GitHub Release.
5. Wait for the ASC approval webhook (`announce.yml`) to publish the macOS zip to isolated.tech and post Discord announcements.

Bot-authored release publishes are skipped so legacy draft releases promoted by `announce.yml` do not redeploy the same build.

## Required repository secrets

These are configured under Settings → Secrets and variables → Actions:

| Secret | Used for |
| --- | --- |
| `APPLE_CERTIFICATE_P12` | Combined signing identities for iOS, Mac App Store, Developer ID, and installer signing |
| `APPLE_CERTIFICATE_PASSWORD` | Password for the `.p12` bundle |
| `APPLE_TEAM_ID` | Apple Developer Team ID |
| `IOS_APP_STORE_PROVISIONING_PROFILE` | Base64-encoded iOS App Store provisioning profile |
| `MAC_APP_STORE_PROVISIONING_PROFILE` | Base64-encoded Mac App Store provisioning profile |
| `APPLE_ID` | Apple ID for notarization |
| `APPLE_ID_PASSWORD` | App-specific password for notarization |
| `ASC_KEY_ID` | App Store Connect API key id |
| `ASC_ISSUER_ID` | App Store Connect issuer id |
| `ASC_API_KEY_P8` | Base64-encoded ASC `.p8` private key |
| `HEALTHMD_ASC_APP_ID` | App Store Connect app id |
| `ISOLATED_API_KEY` | isolated.tech publish from `announce.yml` |
| `SPARKLE_ED_PRIVATE_KEY` | Sparkle signing for isolated.tech publish |
| `DISCORD_BOT_TOKEN` | Discord release announcement |

Optional repository secret:

| Secret | Used for |
| --- | --- |
| `LLM_WIKI_DISPATCH_TOKEN` | Launch-checklist dispatch from `announce.yml` |

Required repository variable:

| Variable | Used for |
| --- | --- |
| `ISOLATED_APP_SLUG` | isolated.tech app slug |

## Release steps

1. Bump `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in the Xcode project and commit the change.
2. Create and publish a GitHub Release with a `v<version>` tag, e.g. `v2.1.3`.
3. Use the release body for customer-facing notes; it is copied to ASC “What’s New” (truncated to ASC limits).
4. Watch the `Release iOS` and `Release macOS` workflow runs.

For a no-upload smoke test, run either workflow manually from the Actions tab with `dry_run=true`.
