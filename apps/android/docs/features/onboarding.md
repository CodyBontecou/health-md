# Onboarding

## What it does

First-run setup gets the first real files into the user's vault in about five taps. It configures the existing default automation (renamed **Daily note**) instead of creating a second one, writes the last seven days with the single free export, and offers automatic daily notes only after the user has seen their notes. Completion opens **Automations**.

## Steps

1. **Welcome** — what Health.md writes and where. **Use a Shared Setup** imports a `.healthmdconfig` file instead.
2. **Packs** — choose what goes in the daily note: Sleep & Recovery, Activity, Heart, Body, Mind, Nutrition and Cycle Tracking. The first three are on by default; Cycle Tracking is always off by default. Each card shows its real metric count; packs this Health Connect provider cannot grant (for example Mind without mindfulness support) are shown as unavailable. Continue writes the union of the packs' metric IDs as the metric selection.
3. **Health Connect** — the permission sheet asks only for the selected packs' record types. Background and history access are not requested here. **Skip** continues without access; it can be granted later from Export now or Settings.
4. **Folder** — Local folder (recommended), API endpoint, or Google Drive (a Drive folder chosen in the system picker). The picked folder is bound to the Daily note. Choosing **API endpoint** opens the **New API endpoint** sheet (see below); once saved, the option shows the endpoint (status dot, name, URL, **Edit**) and the preview becomes the JSON payload that will be POSTed. **Skip** continues without a destination.
5. **First note** — a dry-run preview of the last seven days (today included) through the normal export pipeline. Tap a day in the week chart to see its note rendered; **View raw file** shows the exact file. **Save N notes to <folder>** runs one ordinary manual export of those seven days, which uses the one free export on Google Play. Without Health Connect access or data, a clearly labelled sample note is shown and **Finish setup** continues without consuming the free export. A skipped folder shows **Choose a folder to save** and **Continue without saving**. With an API endpoint the action is **Send 7 days to <endpoint name>**, using the same single free export; an API destination without an endpoint shows **Finish setup**.
6. **Make it daily** — "Every morning at 8:00, write yesterday's note to <folder>". On Google Play without paid access: **Start 7-day free trial** (the live Play yearly-trial price is shown; nothing is hard-coded) or **Not now, I'll export manually**. On F-Droid, or with access already active, **Turn on daily notes** enables the schedule directly. Health Connect's background-read permission is requested here, before the schedule is enabled.

## Saved API endpoints

The **New API endpoint** sheet takes a name (default "My API"), an endpoint URL (validated by the existing API endpoint rules), and an optional bearer token (masked, with show/hide). **Test connection** sends a HEAD request and shows the result inline; saving is allowed whether the test passed, failed or never ran. Saved endpoints are reusable: an automation's destination editor lists them as **Saved endpoints** (name, URL, "Used by …" / "Not used yet", a visible edit button per row) plus **New endpoint**, and selecting a row binds that automation to it.

Editing an endpoint updates every automation that uses it: their frozen destination is re-captured for the new URL. **Delete endpoint** leaves those automations unconfigured ("Endpoint not configured"); they stop sending and never fall back to another destination. Tokens are stored encrypted with the Android Keystore in the API credential file; a request to a saved endpoint's URL carries only that endpoint's token (no legacy Authorization or custom headers). Automations bind an endpoint by URL, and URLs are unique among saved endpoints.

## Automations without paid access

The Daily note card shows **Manual** instead of a switch, "Writes N metrics to <folder>", and a notice "Daily at 8:00 AM is off · Automatic notes need a subscription" with **Try free**. It never shows "Next · …" without access.

## Recovery

- Skipped Health Connect and folder steps are repaired from Export now, Automations, or Settings.
- Failed exports do not consume the free export; a partial export consumes it, as for Export now.
- A trial that is cancelled in the Play sheet leaves the user on Make it daily; **Not now** still finishes setup.
- Replaying onboarding from App & support keeps a renamed automation's name and reconfigures the active automation.

## Implementation

`OnboardingScreen.kt` is a step machine over `OnboardingStep`; pure rules live in `OnboardingFlow`. `HealthPack` (`domain/onboarding`) maps pack IDs (`sleep`, `activity`, `heart`, `body`, `mind`, `nutrition`, `cycle`) to metric IDs, and `HealthPackPermissions` maps packs to Health Connect read permissions, intersected with `HealthConnectPermissionPlan.foregroundPermissions`. The preview calls `ExportOrchestrator.previewDates` for seven days and `OnboardingNoteParser` renders its Markdown; saving reuses `ExportViewModel.startExport`, so access checks, `FreemiumPolicy` accounting and history match Export now. Completion flushes live settings into the active profile through `ExportProfileCoordinator`, renames a "Default" profile to "Daily note", and, for a trial or included access, enables an 8:00 daily `ScheduledProfileEntry`. No custom onboarding analytics are collected.

Android differences from iOS: Health Connect grants per record type; HRV is RMSSD; Mind has no State of Mind; the seven-day export fits Health Connect's default 30-day read window, so no history permission is needed; the trial is billed through Google Play.
