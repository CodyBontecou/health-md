# Android distribution channels

Health.md ships one Android product from one source revision with two distribution variants. Both use `com.healthmd.android`, the same version code/name, Health Connect semantics, exporters, schemas, fixtures, automation actions, and Direct CLI protocol.

## Capability matrix

| Outcome | Google Play (`play`) | F-Droid (`fdroid`) |
| --- | --- | --- |
| Health Connect capture/export | Available | Available |
| Manual exports | 10 free, then lifetime entitlement | Full access included |
| Scheduling, automation, recovery, Direct CLI export | Requires lifetime entitlement | Included |
| Billing / purchase / restore | Google Play Billing | Absent |
| Direct Fitbit/Oura/WHOOP/Withings providers and OAuth | Available when configured | Absent; Health Connect only |
| Wear OS Data Layer and controls | Available | Absent |
| User-initiated Play review | Available | Absent |
| Install attribution and first-party onboarding telemetry | Configuration-gated | Not compiled in; no telemetry identity/state |
| App source/license links | Available in Settings | Available in Settings |

Unsupported F-Droid capabilities are omitted rather than reported as successful. The distribution split does not change public export bytes or direct protocol versions.

## Health Connect availability

- **Android 14+**: Health Connect is a system component; users can open its settings from Health.md.
- **Android 9–13**: a compatible Health Connect provider app must be installed and enabled. The onboarding/permission UI offers the available install, update, or settings route.

The F-Droid metadata declares `NonFreeDep` because Health Connect runtime availability may depend on a proprietary system/provider component even though the AndroidX client library and Health.md source are freely licensed.

## Installing and switching

Google Play and F-Droid sign releases with different keys. Android does not permit an in-place update across those signatures. To switch:

1. Export or otherwise preserve any app-private settings/history that matter; normal Health.md output files already remain in their selected destination.
2. Uninstall the installed channel.
3. Install the other channel and complete setup again.

Purchases, local settings, history, encrypted credentials, and private transfer state are not migrated across channel signatures.

## Build commands

From `apps/android`:

```bash
# Default developer/device channel
./gradlew :app:assemblePlayDebug
./gradlew :app:installPlayDebug

# Play release (requires local signing properties)
./gradlew :app:bundlePlayRelease
# app/build/outputs/bundle/playRelease/app-play-release.aab

# F-Droid (requires no credentials and remains unsigned)
./gradlew :app:assembleFdroidDebug
./gradlew :app:assembleFdroidRelease
./scripts/verify-fdroid-artifact.sh
# app/build/outputs/apk/fdroid/release/app-fdroid-release-unsigned.apk
```

Repository-root convenience commands are `make android-play-debug`, `make android-fdroid-debug`, and `make android-fdroid-release`.

## Validation

```bash
./gradlew \
  :app:testPlayDebugUnitTest :app:testFdroidDebugUnitTest \
  :app:lintPlayDebug :app:lintFdroidDebug \
  :app:assemblePlayDebug :app:assembleFdroidDebug
```

CI builds `fdroidRelease` from a clean checkout without release properties, checks the exact runtime graph and merged manifest, inspects package/version/SDK fields, rejects a signed upstream APK, scans the artifact with pinned fdroidserver, and retains the APK, report, scanner result, and checksums.

## Release policy

- One Android version and annotated `android/v<version>` tag feeds both channels.
- Play-only changes still pass the F-Droid dependency/scanner gate; common changes test both variants.
- F-Droid may publish later because its build/review queue is independent, but it receives no separate source commit under the same version code.
- Release notes must not claim Billing, Play review, direct cloud providers, attribution, or Wear support in F-Droid.
- Review F-Droid inclusion/scanner rules and pinned SDK, NDK, Rust, and Gradle support before toolchain upgrades.

The proposed fdroiddata metadata and reproducibility instructions live under [`../fdroid/`](../fdroid/).
