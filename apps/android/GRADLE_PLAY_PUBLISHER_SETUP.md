# gradle-play-publisher Setup Complete ✅

Your Android project is now configured for automated Google Play Store deployment using **gradle-play-publisher**.

## What Was Set Up

### 1. **Plugin Configuration**
- ✅ Added `gradle-play-publisher` v3.10.1 to `gradle/libs.versions.toml`
- ✅ Applied plugin to `app/build.gradle.kts`
- ✅ Configured Play Store credentials in `app/build.gradle.kts`

### 2. **Directory Structure**
Created `play-console/` with these subdirectories:
```
play-console/
├── listing/
│   └── en-US/
│       ├── title.txt                    ✅ (populated)
│       ├── short-description.txt        ✅ (populated)
│       ├── full-description.txt         ✅ (populated)
│       └── release-notes/en-US/
│           └── default.txt              ✅ (populated)
├── graphics/
│   └── en-US/
│       └── (place PNG files here)
└── screenshots/
    └── en-US/
        └── phone/
            └── (place 1.png, 2.png, etc.)
```

### 3. **Security**
- ✅ Updated `.gitignore` to exclude `play-console-key.json`
- ✅ Never commit credentials to Git

### 4. **Documentation**
Created reference guides:
- **PLAY_STORE_SETUP.md** - Full setup and credential guide
- **PLAY_STORE_COMMANDS.md** - Command reference and workflows
- **GRADLE_PLAY_PUBLISHER_SETUP.md** - This file

## Next Steps

### 1. Create Google Play Service Account (Required)

Follow the detailed guide in **PLAY_STORE_SETUP.md**, section "Get Google Play Service Account Credentials":

1. Create service account in Google Cloud Console
2. Generate JSON key
3. Save as `play-console-key.json` in project root
4. Invite service account to Play Console

### 2. Organize App Store Assets

- **Metadata** (already partially filled in `play-console/listing/`)
  - Update `title.txt`, `short-description.txt`, `full-description.txt`
  - Update release notes in `release-notes/en-US/default.txt`

- **Graphics** (add to `play-console/graphics/en-US/`)
  - `featureGraphic.png` (1024x500px) — main store listing image
  - `icon.png` (512x512px) — app icon

- **Screenshots** (add to `play-console/screenshots/en-US/phone/`)
  - Minimum 2, recommended 5-8
  - Dimensions: 1080x1920px
  - Name as: `1.png`, `2.png`, `3.png`, etc.

### 3. Test the Setup

```bash
# Build release bundle
./gradlew bundleRelease

# Verify credentials work (requires play-console-key.json)
./gradlew validatePlayConsoleCredentials

# Upload to Internal Testing (safe first upload)
./gradlew publishReleaseBundle
```

## Common Commands

```bash
# Build only
./gradlew bundleRelease

# Build + upload to Internal Testing
./gradlew publishReleaseBundle

# Upload to Beta track
./gradlew publishReleaseBundle --play-track=beta

# Upload to Production (5% staged rollout)
./gradlew publishReleaseBundle --play-track=production --play-user-fraction=0.05

# Update metadata/screenshots without rebuild
./gradlew publishListingBundle
```

## Release Workflow

**Recommended flow for each release:**

1. Update release notes: `play-console/listing/en-US/release-notes/en-US/default.txt`
2. Increment `versionCode` in `app/build.gradle.kts` (or let auto-increment)
3. Build and test: `./gradlew bundleRelease`
4. Upload to internal: `./gradlew publishReleaseBundle`
5. Test for 1-2 days
6. Move to beta: `./gradlew publishReleaseBundle --play-track=beta`
7. Beta test for 3-7 days
8. Release to production (5% first): `./gradlew publishReleaseBundle --play-track=production --play-user-fraction=0.05`
9. Monitor for 2-3 days, then increase to 100%

## Key Files to Know

| File | Purpose |
|------|---------|
| `app/build.gradle.kts` | Gradle config + Play Publisher settings |
| `gradle/libs.versions.toml` | Dependency/plugin versions |
| `.gitignore` | Prevents credentials from committing |
| `play-console/` | All app store metadata & assets |
| `play-console-key.json` | Service account credentials (⚠️ Secret!) |

## Troubleshooting

**"Service account not found"**
- Ensure `play-console-key.json` exists in project root
- Check file permissions: `chmod 600 play-console-key.json`

**"Invalid version code"**
- `versionCode` must be higher than previous release
- Check `app/build.gradle.kts` for current code

**"Service account not invited"**
- Go to Play Console → Settings → Users and permissions
- Invite the service account email
- Grant "Release Manager" role

**Screenshots upload fails**
- Verify PNG format and exact dimensions (1080x1920px)
- Check naming: `1.png`, `2.png`, etc.

## More Information

- See **PLAY_STORE_SETUP.md** for detailed credential setup
- See **PLAY_STORE_COMMANDS.md** for all available commands
- [gradle-play-publisher docs](https://github.com/Triple-T/gradle-play-publisher)
- [Android build documentation](https://developer.android.com/build)
