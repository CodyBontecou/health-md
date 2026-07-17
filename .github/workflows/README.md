# GitHub Actions release pipeline

Health.md ships iOS and macOS builds to App Store Connect from GitHub Actions.

## Trigger

The canonical release path starts from a draft GitHub Release whose tag starts with `v` (for example `v3.0`). After creating the draft against the exact committed and pushed `origin/main` SHA, dispatch both workflows with that tag through `workflow_dispatch`:

- `.github/workflows/release-ios.yml`
- `.github/workflows/release-macos.yml`

Use `release_tag=v<version>`. The tag version must match `MARKETING_VERSION` in `HealthMd.xcodeproj`; each workflow fails early if it does not. Keep the GitHub Release as a draft while App Store review is in progress. The ASC approval webhook and `announce.yml` publish it.

Publishing a release still triggers both workflows as a legacy fallback, but it is not the canonical path because publication must wait for ASC approval.

## What the workflows do

1. Build and sign the iOS `.ipa` and macOS App Store `.pkg`.
2. Upload each build to App Store Connect with `asc builds upload`.
3. Discover the processed ASC build through the builds API rather than treating an upload operation ID as a build ID.
4. Create or reuse the matching ASC version, apply locale-specific `metadata/version/<version>/*.json` release notes, validate it, and submit it for review.
5. Attach the notarized macOS Developer ID zip to the draft GitHub Release.
6. Wait for the ASC approval webhook (`announce.yml`) to publish the release, publish the macOS zip to isolated.tech, and post Discord announcements.

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

1. Resolve a remote-safe build number with `asc builds next-build-number` for both platforms.
2. Bump `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`, update `CHANGELOG.md`, in-app notes, canonical metadata, and `fastlane/metadata/en-US/release_notes.txt`.
3. Test from a clean worktree, commit, and push the exact source to `origin/main`.
4. Create the `v<version>` tag and a **draft** GitHub Release targeting that exact commit. Its body is the canonical customer-facing release note.
5. Dispatch both workflows with `release_tag=v<version>`. Use `skip_asc_submit=true` when upload and validation/submission should be handled as separate phases.
6. Confirm `asc validate` passes for `IOS` and `MAC_OS`, then submit both versions for review.
7. Leave the GitHub Release as a draft. `announce.yml` publishes it after ASC approval.

For a no-upload smoke test, run either workflow manually with `dry_run=true`.
