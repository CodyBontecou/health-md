# Gradle Play Publisher removal

Gradle Play Publisher has been removed from the Android application modules. Module-level mutation tasks bypass exact annotated-tag qualification, protected credentials, retained intent receipts, and production lifecycle verification. Do not reintroduce `com.github.triplet.play`, a module `play {}` block, or Gradle Play mutation tasks.

## Current phone-only release

`release-scope.json` defines the active release boundary. Android `1.9.1` publishes only the phone `:app` artifact; `:wear` remains deferred for a later qualification cycle.

Gradle may build and test artifacts locally without Play credentials:

```bash
./gradlew :app:testPlayDebugUnitTest :app:testFdroidDebugUnitTest :direct-protocol:test
./gradlew :app:lintPlayDebug :app:lintFdroidDebug
./gradlew :app:bundlePlayRelease
```

Release bundles require signing configuration from ignored `local.properties` or protected workflow inputs. Never commit a keystore or `local.properties`. Substitute signing proves local package behavior only and is not production-signing evidence.

The dormant Wear implementation may still be compiled in development, but no Wear bundle is part of the current publication flow.

## Canonical publication flow

1. Commit the phone release source and push it to `main`.
2. Require successful Android CI for that exact source.
3. Create an annotated `android/v<version>` tag whose peeled commit is reachable from `origin/main`.
4. `.github/workflows/android-release.yml` requalifies the exact tag, builds/signs `app-play-release.aab`, retains SHA/AAB-bound intent evidence, and uploads it with reviewed listing copy to Internal Testing.
5. `.github/workflows/android-promote-production.yml` runs from the same exact tag, promotes only that version code to production, submits it for review, and verifies the Play lifecycle.

Both mutation workflows use the tag-restricted `google-play` GitHub environment. Credentials are materialized only on the runner and removed unconditionally. Local Play mutation is unsupported.

## References

- `PLAY_STORE_COMMANDS.md` — operator commands and release sequence
- `PLAY_STORE_SETUP.md` — protected environment and Play account setup
- `docs/features/wear-os-completion-audit.md` — deferred Wear work, not a current release gate
