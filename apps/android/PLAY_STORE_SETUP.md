# Google Play Store Deployment with gradle-play-publisher

This project uses **gradle-play-publisher** for automated Google Play Store management.

## Quick Start

### 1. Get Google Play Service Account Credentials

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project (or select existing)
3. Enable the **Google Play Android Developer API**
4. Create a **Service Account**:
   - Go to **Service Accounts** → **Create Service Account**
   - Grant role: **Editor**
5. Create a **JSON Key**:
   - Click on the service account
   - Go to **Keys** tab
   - **Add Key** → **Create new key** → **JSON**
   - Save it outside the repository, for example `~/.config/play-console/play-publisher-<project-id>.json`
   - Set `PLAY_CONSOLE_KEY_PATH` when the file is not at the default path configured in `app/build.gradle.kts`

### 2. Link Service Account to Play Console

1. Go to [Google Play Console](https://play.google.com/console)
2. Select your app
3. Go to **Settings** → **Users and permissions**
4. **Invite user** and paste the service account email from the JSON key
5. Grant role: **Release Manager** (or **Admin** for full access)

### 3. Prepare Your App Metadata

Create the `play-console` directory structure:

```
play-console/
├── listing/
│   ├── en-US/
│   │   ├── title.txt          # App title (max 50 chars)
│   │   ├── short-description.txt  # 80 chars
│   │   ├── full-description.txt   # Full description
│   │   └── video.txt          # YouTube video URL (optional)
│   │
│   └── release-notes/
│       ├── en-US/
│       │   └── default.txt    # What's new in this version
│
├── screenshots/
│   ├── en-US/
│   │   ├── phone/
│   │   │   ├── 1.png         # 1080x1920px (5+ recommended)
│   │   │   ├── 2.png
│   │   │   └── ...
│   │   ├── sevenInch/         # 7" tablet (optional)
│   │   ├── tenInch/           # 10" tablet (optional)
│   │   └── wear/              # Wear OS (optional)
│   │
│   └── ...other languages...
│
├── graphics/
│   ├── en-US/
│   │   ├── featureGraphic.png    # 1024x500px (required)
│   │   ├── icon.png             # 512x512px (required)
│   │   ├── promoGraphic.png      # 180x120px (optional)
│   │   └── tvBanner.png          # 1280x720px (optional)
│   │
│   └── ...other languages...
```

## Build & Upload Commands

### Build Release Bundle

```bash
./gradlew bundleRelease
```

Outputs to: `app/build/outputs/bundle/release/app-release.aab`

### Upload to Internal Testing Track

```bash
./gradlew publishReleaseBundle
```

- Uses the external service-account file selected by `PLAY_CONSOLE_KEY_PATH` or the default in `app/build.gradle.kts`
- Publishes to **Internal Testing** track
- Publishes the committed `versionCode`; bump it before every upload

### Upload to Closed Testing (Beta)

```bash
./gradlew publishReleaseBundle --track beta
```

### Upload to Production

```bash
./gradlew publishReleaseBundle --track production
```

### Staged Rollout (5% → 25% → 50% → 100%)

```bash
./gradlew publishReleaseBundle --track production --user-fraction 0.05
```

Then increase fraction to push further:
```bash
./gradlew publishReleaseBundle --track production --user-fraction 0.25
```

### Update Metadata Only (No Build)

```bash
./gradlew publishListingBundle
```

## Version Management

Every Play upload requires a `versionCode` higher than every previously uploaded build. Update `versionCode` and `versionName` in `app/build.gradle.kts` before creating the release commit; do not rely on an uncommitted CI-time increment.

Track version history:
```bash
git log --oneline app/build.gradle.kts | grep -i version
```

## CI/CD Integration

The canonical workflow is [`.github/workflows/android-release.yml`](../../.github/workflows/android-release.yml). An `android/v<version>` tag builds a signed AAB and uploads it directly to Google Play's `internal` track. The AAB is never committed, attached to a GitHub Release, or retained as a workflow artifact; production promotion remains manual in Play Console.

The tag-restricted `google-play` environment stores the Play service-account JSON, existing upload keystore, and signing values as environment secrets. The workflow writes them only under `$RUNNER_TEMP` and removes the temporary files in an `always()` cleanup step. Never commit or regenerate the existing Play upload key.

## Troubleshooting

### "Service account not found"
- Verify `PLAY_CONSOLE_KEY_PATH` points to an existing service-account JSON file, or that the external default path in `app/build.gradle.kts` exists
- Check the service account email is invited to Play Console

### "Invalid version code"
- Ensure the committed `versionCode` is higher than every previous Play upload

### "Upload failed: Invalid localization"
- Screenshot dimensions must be exact
- Ensure all required files exist in listing structure

### "Health Connect permissions warning"
- App already declares Health Connect opt-in
- Make sure privacy policy is set in Play Console

## Documentation Links

- [gradle-play-publisher Docs](https://github.com/Triple-T/gradle-play-publisher)
- [Google Play Upload Guide](https://support.google.com/googleplay/android-developer/answer/9859152)
- [Health Connect Policies](https://developer.android.com/health-and-fitness/guides/health-connect)

## Release validation

From `apps/android`:

```bash
PLAY_CONSOLE_KEY_PATH="$HOME/.config/play-console/play-publisher-<project-id>.json" \
  ./gradlew :app:bundleRelease

PLAY_CONSOLE_KEY_PATH="$HOME/.config/play-console/play-publisher-<project-id>.json" \
  ./gradlew publishReleaseBundle --track internal --dry-run
```

The first command validates the release signing configuration and produces a signed AAB without uploading it. The second validates the Gradle Play Publisher task graph without opening or committing a Play edit. Verify service-account access separately before enabling an upload workflow.
