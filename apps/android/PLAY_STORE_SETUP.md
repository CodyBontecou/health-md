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
   - Save as `play-console-key.json` in project root

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

- Uses `play-console-key.json` for auth
- Publishes to **Internal Testing** track
- Version code increments automatically

### Upload to Closed Testing (Beta)

```bash
./gradlew publishReleaseBundle --play-track=beta
```

### Upload to Production

```bash
./gradlew publishReleaseBundle --play-track=production
```

### Staged Rollout (5% → 25% → 50% → 100%)

```bash
./gradlew publishReleaseBundle --play-track=production --play-user-fraction=0.05
```

Then increase fraction to push further:
```bash
./gradlew publishReleaseBundle --play-track=production --play-user-fraction=0.25
```

### Update Metadata Only (No Build)

```bash
./gradlew publishListingBundle
```

## Version Management

Version codes **auto-increment** for each release:
- Current: `versionCode = 1` (in `app/build.gradle.kts`)
- Manually bump for major releases or let gradle-play-publisher increment automatically

Track version history:
```bash
git log --oneline app/build.gradle.kts | grep -i version
```

## CI/CD Integration

Example GitHub Actions workflow:

```yaml
name: Deploy to Play Store
on:
  push:
    tags:
      - 'v*'

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Setup Java
        uses: actions/setup-java@v4
        with:
          java-version: '17'
          distribution: 'temurin'
      
      - name: Deploy to Play Store
        run: ./gradlew publishReleaseBundle
        env:
          PLAY_CONSOLE_KEY: ${{ secrets.PLAY_CONSOLE_KEY }}
```

Store `play-console-key.json` contents in GitHub Secrets as `PLAY_CONSOLE_KEY`.

## Troubleshooting

### "Service account not found"
- Verify `play-console-key.json` exists in project root
- Check service account email is invited to Play Console

### "Invalid version code"
- Ensure `versionCode` is higher than previous release
- gradle-play-publisher should auto-increment

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

## Next Steps

1. ✅ gradle-play-publisher configured
2. ⏳ Create `play-console-key.json` from Google Cloud
3. ⏳ Set up Play Console app listing
4. ⏳ Organize app store assets in `play-console/` directory
5. ⏳ Run first test upload to Internal Testing track
