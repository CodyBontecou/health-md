# Health Connect Permissions

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** Onboarding (first grant) and Export (re-grant)
- **Source files:** `app/src/main/java/com/healthmd/data/health/HealthConnectPermissionPolicy.kt`, `HealthConnectManager.kt`, `presentation/HealthPermissionsRationaleActivity.kt`, `presentation/onboarding/OnboardingScreen.kt`

## What it does

Health.md asks Health Connect for read access to the health record types it can export. The request is built from what your installed Health Connect provider actually supports: a core set of always-available record types, plus newer types (skin temperature, mindfulness, planned exercise, activity intensity, and medical/PHR resources) only when your provider can grant them. Two optional extras — reading history older than the standard window and background reads for widgets — are requested as separate, clearly labeled permissions.

## Who it is for

- Every user: without read permission, exports come back empty.
- Users with older devices or the sideloaded Health Connect APK, where newer record types may be unavailable.
- Anyone reviewing Health.md's privacy claims from the Health Connect privacy-policy screen.

## Where to find it

1. During onboarding, the **Health** page requests permissions (see ./onboarding.md).
2. Later, the Export tab shows a permission-required notice with a **Grant** button whenever required access is missing.
3. Android Settings → Health → Health Connect also shows and manages the granted types.
4. Health Connect's own "privacy policy" link opens Health.md's in-app rationale screen, which maps every requested permission group to the exported fields it produces.

## Prerequisites

- Health Connect installed, enabled, and set up on the device (Android 9 / API 28 floor).
- At least one app writing data into Health Connect, or exports will be empty rather than failing.

## Setup

1. Tap **Grant** on the onboarding Health page or the Export-tab notice.
2. In the Health Connect sheet, allow the data types you want to export.
3. Return to Health.md — the checkmark or notice updates on resume.

## Example output

With sleep granted and nothing else, a daily export contains sleep metrics and reports the other requested categories as having no available data — not as errors.

## Tips

- Grant only the categories you want exported; partial grants are fine and expected.
- To export data older than the standard read window, grant the separate **History** permission when Health Connect offers it (the Export tab surfaces a notice with its own grant button when history access is available but missing).
- Read access is read-only: Health.md never writes to Health Connect.
- Widgets may ask for the separate background-read permission so their refresh pulse can read Health Connect in the background; denying it keeps widgets working off data read while you use the app.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Exports report "no data" | Permission not granted, or no app writes that type to Health Connect | Re-check granted types in Health Connect settings |
| A newer metric (e.g. skin temperature) is missing | Provider does not expose that record type | Nothing to fix on Health.md's side; the type is not requested from providers that cannot grant it |
| History export stops at an older date | History read permission missing or unavailable | Grant it from the Export-tab notice, or export that range in shorter windows |
| "Health Connect needs setup" | Provider not initialized | Open Health Connect once, accept its terms, then return |

## Video outline

- **Suggested title:** What Health.md Asks Health Connect For — and Why
- **Hook:** "Every permission maps to a field you can export."
- **Demo flow:**
  1. Onboarding Health page grant.
  2. Show the rationale screen mapping groups → exported fields.
  3. Partial grant → export showing empty categories.
- **Key screenshot/recording moments:** permission sheet, green check, rationale cards.
- **CTA / next video:** ./metric-selection.md.

## Implementation notes

`HealthConnectPermissionPolicy` builds a `HealthConnectPermissionPlan`: `alwaysAvailableForegroundPermissions` (the core record set), feature-gated additions for `FEATURE_SKIN_TEMPERATURE`, `FEATURE_MINDFULNESS_SESSION`, `FEATURE_PLANNED_EXERCISE`, `FEATURE_ACTIVITY_INTENSITY`, and `FEATURE_PERSONAL_HEALTH_RECORD` (medical FHIR resources), plus `PERMISSION_READ_HEALTH_DATA_HISTORY` and `PERMISSION_READ_HEALTH_DATA_IN_BACKGROUND` when those features report available. Types that a provider cannot grant are never sent in the request (important for the Android 13 APK provider). `HealthPermissionsRationaleActivity` satisfies Health Connect's rationale requirement with twelve category cards (sleep, activity, heart, vitals, body, nutrition, mobility, reproductive, mindfulness, medical, history, background); `ViewPermissionUsageActivity` is an exported activity-alias onto it for `VIEW_PERMISSION_USAGE`, enforced by `HealthConnectManifestContractTest`. Permission state re-checks on every `ON_RESUME`. Deliberate difference from Apple: Android requests Health Connect record-type permissions in one system sheet; there is no per-object selector equivalent to Apple's special-access flows.
