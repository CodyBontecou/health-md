# Android home-screen widgets

Health.md provides four resizable Android home-screen widgets backed directly by local Health Connect data:

| Widget | Compact | Wide | Medium | Tall large |
| --- | --- | --- | --- | --- |
| Health Summary | Steps, sleep, resting heart rate | Steps, active calories, exercise, sleep, HRV | Activity rings with seven-day sleep and heart range | Expanded charts and activity summary |
| Activity | Move, exercise, and steps rings | Rings plus progress toward each goal | — | — |
| Heart Range | — | Seven-day minimum/average/maximum chart | Chart, average, resting heart rate, HRV | Expanded chart and metric tiles |
| Sleep | Last sleep duration and window | Seven-day sleep bars | Last sleep, seven-day average, bedtime, wake time | Expanded seven-day chart and timing |

Android launcher dimensions vary. These names describe responsive compositions rather than guaranteed cell measurements. Compact cards switch to dense text-first layouts at larger font scales or when stale-status copy must fit.

## Platform parity

The widgets mirror the Health Summary, Activity Rings, Heart Range, and Sleep widgets in the Apple app, with Android-native semantics:

- **Steps:** 10,000-step reference goal.
- **Active calories:** 500 kcal reference goal.
- **Exercise:** 30-minute reference goal, derived from Health Connect exercise sessions.
- **Sleep:** 8-hour reference goal. Asleep stage totals are preferred; total session duration is used when a provider omits stages.
- **HRV:** displayed as RMSSD in milliseconds. Android Health Connect RMSSD is not interchangeable with Apple HealthKit SDNN.
- **Stand Hours:** Health Connect has no equivalent. The Android activity widget uses Steps as its third ring and never fabricates a stand value.

The Apple CLI export Live Activity maps to Android’s existing ongoing Direct CLI transfer notification. Wear OS is implemented separately in `:wear` using the private `:wearable-contract`; it receives minimized phone-authoritative Health Connect aggregates and does not depend on Glance/AppWidget UI. See `wear-os-implementation.md`.

## Data and privacy

Widgets read only the Health Connect categories required by installed widget types. Phone widgets do not request or cache blood oxygen because no current phone widget displays it.

The shared widget snapshot contains at most 14 daily records:

- Steps, active calories, and exercise minutes
- Sleep duration, start, and end
- Resting, average, minimum, and maximum heart rate
- HRV RMSSD

The snapshot excludes granular samples, source applications, Health Connect record identities, metadata, routes, and error messages. It is written atomically under the app’s credential-protected `noBackupFilesDir`, so it is excluded from cloud backup and device transfer. Final-instance deletion shares the refresh mutex, preventing an in-flight foreground read from recreating the cache after cleanup. A unique cleanup worker keeps retrying a failed final deletion instead of silently leaving health data behind.

Picker previews contain synthetic measurements only. API 31+ layouts localize their text; the API 28–30 fallback images are text-free and language-neutral.

Android does not offer WidgetKit’s sensitive-content redaction for third-party widgets. Provider metadata uses an API 28 base, API 31 enhanced picker previews/target-cell sizing, and `home_screen|not_keyguard` on API 36 and newer. They are home-screen widgets, not lock-screen widgets. Host compliance remains platform/OEM behavior.

## Permissions and setup

Adding a widget opens the shared Health.md setup activity. It requests only the foreground Health Connect permissions needed by that widget:

- Activity: steps, active calories, exercise sessions
- Sleep: sleep sessions
- Heart: heart rate, resting heart rate, HRV RMSSD
- Summary: the union of Activity, Sleep, and Heart

Background Health Connect access is requested separately and remains optional. Without it, a widget can still be added after a successful foreground read; measurements refresh when Health.md opens or when the user chooses **Settings → Home-Screen Widgets → Refresh Widgets**. The local periodic pulse may still hide revoked data and update stale copy, but it does not query Health Connect.

Permission reconciliation removes cached values for every denied record family before widgets redraw, even when another metric keeps the same widget partially readable.

## Refresh and freshness

One shared pipeline updates every installed widget:

1. Health Connect performs a dedicated 14-day focused read: Activity uses permission-scoped steps/calorie aggregates plus one exercise-session read, Sleep uses one session read, and Heart uses one exact aggregate plus RMSSD/resting reads. Granular samples and unrelated export categories are never queried.
2. Health.md maps the result into the minimal versioned snapshot.
3. The snapshot is durably replaced.
4. All four Glance providers reload from the same cache.

A single unique WorkManager request targets a 30-minute cadence while at least one widget exists. With optional background access it refreshes measurements; without that access it only reconciles foreground-permission revocations and stale/expired presentation. Android background scheduling is inexact and may be delayed by Doze, battery policy, Health Connect quotas, or OEM behavior.

The app also refreshes widgets after setup and when the main activity resumes, with a 15-minute foreground throttle.

- Up to 4 hours old: current.
- 4–24 hours old: displayed with an “Updated … ago” marker.
- More than 24 hours old: measurements are hidden until a successful refresh.
- Focused reads are strict: any selected record-family failure retains the last-good snapshot instead of saving a partial capture. Permission reconciliation still removes denied measurements immediately.

## Implementation

Primary code lives under `app/src/main/java/com/healthmd/widget/`:

- `model/`: bounded snapshot and widget requirements
- `data/`: Health Connect adapter, permission policy, mapper, atomic no-backup store
- `refresh/`: one-time/periodic WorkManager orchestration and lifecycle reconciliation
- `glance/`: four responsive providers, shared components, charts, and activity artwork
- `setup/`: placement setup and in-app widget management

Provider metadata lives in `app/src/main/res/xml/`, with API 36 privacy overrides in `xml-v36/`.

Jetpack Glance renders through `RemoteViews` and cannot reliably load bundled app fonts in a launcher process. The scoped platform-font exception is documented in `DESIGN.md` and `DESIGN.dark.md`; colors, spacing, radii, hierarchy, and light/dark behavior still use the named Geist tokens.

## Verification

Run from `apps/android`:

```bash
./gradlew :app:testDebugUnitTest
./gradlew :app:lintDebug
./gradlew :app:assembleDebug
./gradlew :app:connectedDebugAndroidTest
```

Physical QA targets Pixel 7 serial `2C061FDH200CJN`. API 37 verification confirmed picker previews/setup, all four simultaneous providers, compact/wide/tall resizing, light/dark rendering, 1.3× font scaling, Arabic RTL mirroring, whole-card TalkBack focus, root taps, stale/expired/no-data/pre-unlock states, `widgetCategory=9` (`home_screen|not_keyguard`), and an exact 1,800,000 ms unique periodic work row. Removing the final physical instance deletes the private snapshot directory and leaves the widget WorkManager rows cancelled. Automated coverage verifies partial permissions, before-first-unlock behavior, refresh/removal races, stale AppWidget IDs during deletion callbacks, and cleanup retries.
