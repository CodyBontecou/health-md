# HealthKit Permissions

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** Onboarding → Health Data Access; Export → Health badge
- **Source files:** `HealthMd/iOS/Views/OnboardingView.swift`, `HealthMd/iOS/Views/ExportTabView.swift`, `HealthMd/Shared/Models/HealthMetrics.swift`

## What it does

HealthKit permissions let Health.md read selected Apple Health categories and convert them into Markdown, Obsidian Bases, JSON, or CSV files. Health.md reads data on-device and writes files to the folder you choose. Health data is not uploaded for normal exports.

Permissions are controlled by iOS. Health.md can request access, but the final category-by-category choices live in the Apple Health app.

## Who it is for

- Users exporting Apple Health data from iPhone.
- Users who want to limit Health.md to only certain categories.
- Users troubleshooting missing metrics in exported files.

## Where to find it

During first launch:

1. Open Health.md.
2. Continue to **Health Data Access**.
3. Tap **Grant Access**.

After setup:

1. Open Health.md.
2. Go to **Export**.
3. Tap the **Health** status badge.
4. If already authorized, Health.md shows instructions for adjusting permissions in Apple Health.

## Prerequisites

- iPhone with Health data.
- Apple Health enabled on the device.
- Health.md installed on the same iPhone that stores or syncs the health data.

## Setup

1. Tap **Grant Access** in Health.md.
2. In the iOS permission sheet, enable the categories you want to export.
3. Return to Health.md.
4. Confirm the Health badge shows connected.
5. Go to **Export → Health Metrics** to decide which of the allowed metrics should appear in exports.

To adjust permissions later:

1. Open Apple **Health**.
2. Tap your profile icon.
3. Tap **Apps**.
4. Select **Health.md**.
5. Toggle read permissions on or off.

## Supported data categories

Health.md can export categories such as Sleep, Activity, Heart, Respiratory, Vitals, Body Measurements, Mobility, Cycling, Nutrition, Vitamins, Minerals, Hearing, Mindfulness, Reproductive Health, Symptoms, Other, and Workouts.

Medication tracking appears as pending because it requires special Apple approval and cannot be enabled until that approval is granted.

## Example output

If permissions and metric selection include steps, sleep, and resting heart rate, a Markdown export can include values like:

```markdown
---
date: 2026-05-12
type: health-data
steps: 8432
sleep_total_hours: 7.50
resting_heart_rate: 58
---
```

If a permission is disabled, Health.md cannot read that metric and it will be absent from the export.

## Tips

- Grant only the categories you actually want in your vault.
- Missing data is usually a permission issue, a metric-selection issue, or Apple Health having no sample for that day.
- Health permissions and **Export → Health Metrics** are separate: iOS controls what Health.md may read; Health.md controls what it writes.
- Use Apple Health to audit or revoke access at any time.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Health.md says Health is not connected | Permission has not been granted | Tap the Health badge or grant access during onboarding. |
| A metric is enabled but not exported | Apple Health permission for that type is off | Open Apple Health → Apps → Health.md and enable the category. |
| Permission prompt does not reappear | iOS only shows the system prompt once per install | Adjust permissions manually in Apple Health. |
| Medication tracking is locked | Special Apple entitlement is pending | Wait for app support; the category cannot be enabled yet. |
| No data for a date | Apple Health has no samples for that metric/date | Check the Health app for that day. |

## Video outline

- **Suggested title:** Fix Missing Apple Health Data in Health.md
- **Hook:** “If a metric is missing, check these two places first.”
- **Demo flow:**
  1. Show Health Data Access during onboarding.
  2. Grant permissions in the iOS sheet.
  3. Open Export and tap the Health badge.
  4. Open Apple Health → Apps → Health.md.
  5. Compare Health permissions with Health.md metric selection.
  6. Export a date and show the resulting file.
- **Key screenshot/recording moments:** Health badge, Apple Health app permissions, metric selection screen, exported frontmatter.
- **CTA / next video:** “Next, we’ll choose the vault folder where these files are saved.”

## Implementation notes

- Onboarding calls `healthKitManager.requestAuthorization()` from `HealthAccessStep`.
- Export tab’s Health badge can request authorization and then shows a guide for changing permissions in Apple Health.
- `HealthMetrics` defines the user-facing metric categories and metric identifiers.
- `HealthMetricCategory.medications` is marked `isPendingAppleApproval` and is blocked in selection state.
- Export reads are performed by `HealthKitManager.fetchHealthData(...)` before `VaultManager` writes files.
