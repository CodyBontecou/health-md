# gradle-play-publisher Commands Reference

## Authentication
Before using any commands, ensure `play-console-key.json` is in the project root.

```bash
# Validate credentials
./gradlew validatePlayConsoleCredentials
```

## Build Commands

```bash
# Build release bundle (AAB)
./gradlew bundleRelease

# Build and immediately upload to Internal Testing
./gradlew publishReleaseBundle

# Build for debug testing
./gradlew bundleDebug
```

## Publishing Commands

### By Track

```bash
# Internal Testing (fastest feedback)
./gradlew publishReleaseBundle

# Closed Testing / Beta
./gradlew publishReleaseBundle --play-track=beta

# Production (full release)
./gradlew publishReleaseBundle --play-track=production
```

### Staged Rollouts

```bash
# Release to 5% of users
./gradlew publishReleaseBundle --play-track=production --play-user-fraction=0.05

# Increase to 25%
./gradlew publishReleaseBundle --play-track=production --play-user-fraction=0.25

# Increase to 50%
./gradlew publishReleaseBundle --play-track=production --play-user-fraction=0.50

# Full rollout (100%)
./gradlew publishReleaseBundle --play-track=production --play-user-fraction=1.0
```

## Metadata Publishing

```bash
# Update listing, screenshots, and graphics (no build)
./gradlew publishListingBundle

# Update only specific elements
./gradlew publishListingBundle --play-no-confirm
```

## Release Notes & Version Updates

```bash
# Update release notes for current version
# Edit: play-console/listing/en-US/release-notes/en-US/default.txt
./gradlew publishListingBundle
```

## Version Management

```bash
# View current version
grep versionCode app/build.gradle.kts

# Auto-increment for next release
# gradle-play-publisher handles this automatically
./gradlew publishReleaseBundle
```

## Typical Release Workflow

```bash
# 1. Update version in build.gradle.kts (optional - auto-increments)
# 2. Update release notes
# nano play-console/listing/en-US/release-notes/en-US/default.txt

# 3. Build release bundle
./gradlew bundleRelease

# 4. Test locally on device
./gradlew installDebug

# 5. Upload to Internal Testing
./gradlew publishReleaseBundle

# 6. Test in internal testing for 1-2 days

# 7. Move to Beta
./gradlew publishReleaseBundle --play-track=beta

# 8. Beta test for 3-7 days

# 9. Release to production (5% initially)
./gradlew publishReleaseBundle --play-track=production --play-user-fraction=0.05

# 10. Monitor crashes/reviews for 2-3 days

# 11. Increase rollout
./gradlew publishReleaseBundle --play-track=production --play-user-fraction=1.0
```

## Troubleshooting

```bash
# Enable verbose output
./gradlew publishReleaseBundle --info

# Validate without publishing
./gradlew validatePlayConsoleCredentials

# Check latest published version
# (requires querying Play Console API)
```

## CI/CD Quick Start

Save Play Console key to GitHub Secrets:
```bash
# 1. In GitHub repo: Settings → Secrets and variables → Actions
# 2. New secret: PLAY_CONSOLE_KEY
# 3. Paste contents of play-console-key.json
```

Create `.github/workflows/play-store.yml`:
```yaml
name: Publish to Play Store
on:
  push:
    tags:
      - 'v*'

jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          java-version: '17'
      - name: Create key file
        run: echo '${{ secrets.PLAY_CONSOLE_KEY }}' > play-console-key.json
      - name: Publish to Play Store
        run: ./gradlew publishReleaseBundle --play-track=beta
```

## Documentation

- [gradle-play-publisher GitHub](https://github.com/Triple-T/gradle-play-publisher)
- [Google Play Console Help](https://support.google.com/googleplay/android-developer/)
- [Health Connect Guidelines](https://developer.android.com/health-and-fitness/guides/health-connect)
