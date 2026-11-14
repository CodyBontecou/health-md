# UI test mode for Argent and adb

Android counterpart of the Apple launch-argument test mode (`apps/apple/HealthMd/Shared/TestMode.swift`). It opens the app in a fixed, synthetic state so an automation tool such as Argent can walk a journey without reading or changing a person's real health data.

Running it on an emulator or device is QA and follows the root [verification policy](../../../../AGENTS.md#verification-policy): it needs an explicit request for the current task.

## Isolation

- Only the `e2e` build type honors test mode (`BuildConfig.TEST_MODE_AVAILABLE`). Debug and release builds ignore the extras.
- The e2e app installs as `com.healthmd.android.e2e`, next to the debug or release app, with its own settings, folders and Health Connect grants.
- While test mode is active, `HealthConnectManager` never calls Health Connect. It reports the scenario's permission state and returns `TestModeHealthFixtures` (synthetic, date-stable values for the last 30 days). Raw-record export and incremental changes report Health Connect as unavailable.
- `MainActivity.onResume` skips scheduler, widget and distribution reconciliation, so a test launch arms no alarms.

## Launch

Argent's `launch-app` passes launch arguments only on Apple targets. On Android, start the activity with `adb` and then drive it with Argent as usual:

```bash
./gradlew :app:installPlayE2e          # with ANDROID_SERIAL set
adb shell pm clear com.healthmd.android.e2e   # optional: fresh install state
adb shell am start -S -n com.healthmd.android.e2e/com.healthmd.presentation.MainActivity \
  --ez uitesting true \
  --es UITEST_SHOW_ONBOARDING true \
  --es UITEST_HEALTH_AUTHORIZED true
```

`-S` restarts the process. Test mode activates on the first launch intent that carries `uitesting` and stays active until the process ends, so a later `launch-app` that only brings the app forward keeps the scenario. Values may be strings (`--es`) or primitives (`--ez`, `--ei`); `true/false`, `1/0` and `yes/no` are accepted.

## Scenario keys

| Key | Default | Effect |
| --- | --- | --- |
| `UITEST_HEALTH_AUTHORIZED` | `false` | Health Connect reports granted permissions and serves synthetic days. When false, it reports no access and empty days. |
| `UITEST_SHOW_ONBOARDING` | `false` | Starts in first-run onboarding. |
| `UITEST_HAS_COMPLETED_ONBOARDING` | `true` | `false` also starts in onboarding (Apple parity). |
| `UITEST_PURCHASE_UNLOCKED` | unchanged | Seeds the purchase flag and the debug entitlement override. |
| `UITEST_FREE_EXPORTS_USED` | unchanged | Seeds the free-export counter (clamped to the free limit). |
| `UITEST_STATIC_PURCHASE_PRICES` | `false` | Shows fixed paywall prices, the same as the `staticPurchasePrices` extra. |

The seeded values are written once per test process, before the first screen resolves. Later changes, such as finishing onboarding or using the free export, persist normally inside the e2e app.

## Not covered yet

- Folder selection: pick a folder through the system picker during the journey. There is no synthetic folder, because exports write through the Storage Access Framework.
- Apple keys without an Android equivalent here: schedule, release notes, sync state, feedback scenarios, export-result simulation and profile duplication.
- Background work started before the first activity launch (for example a scheduled export in a fresh process) runs outside test mode.
