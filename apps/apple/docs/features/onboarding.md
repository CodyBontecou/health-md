# Onboarding

## What it does

First-run setup gets the first real note into the user's folder in about five taps: pick what to track, connect Apple Health, choose a folder, see the past week rendered as notes, and save them. The first real export is free and covers the past 7 days; further exports and the daily schedule require active paid access. The trial is offered only after the user has seen their notes.

Apple and Google Play Android share this flow and its pack IDs. The free macOS companion and F-Droid included-access policy are unchanged. Existing paid and grandfathered users retain access; they see "Turn on daily notes" instead of the trial offer.

## Setup

1. **Welcome.** Tap **Get started**.
2. **Packs.** Choose what goes in the daily note. Sleep & Recovery, Activity and Heart are preselected; Body, Mind, Nutrition and Cycle Tracking are opt-in. **Select all** toggles every pack. The summary shows the number of Health types and roughly how many Apple permission pages that is.
3. **Apple Health.** Explains that iOS asks next and that **Turn On All** approves the listed packs. **Continue to Apple Health** requests read access for the selected packs' types only, or choose **Skip for now**.
4. **Folder.** Choose **Local folder or iCloud** (recommended), **Google Drive**, or **API endpoint**. The local choice opens the Files picker; the folder can also be skipped.
   - **Google Drive**, when the build has the direct Drive connection ([Google Drive export](google-drive-export.md)), shows the Drive privacy disclosure, then Google consent (`drive.file` only) and the mobile folder Picker. The chosen folder is bound to the Daily note automation and shown as a connected row with **Change**. Cancelling keeps the step; a failure is shown inline. Builds without Drive configuration fall back to a Drive folder picked in Files.
   - **API endpoint** slides up the **New API endpoint** sheet: name, URL (https://, or http:// on the local network), optional bearer token (Keychain), and **Test connection**. **Save endpoint** needs only a valid URL; an untested or failing endpoint can still be saved. The endpoint is saved for reuse and bound to the Daily note automation, the step then shows it with **Edit** and previews the JSON payload, and First note offers **Send 7 days to …**.
5. **First note.** The past 7 complete days, read from Apple Health and rendered: a sleep chart to pick a night, the day's key values and a short summary. **View raw file** shows the exact Markdown the export writes. **Save 7 notes to …** runs the free export.
   - No Health records, or Health not connected: a labelled sample note is shown and **Finish setup** leaves the free export unused.
   - Folder skipped, or API endpoint chosen without saving one: **Finish setup**; the free export runs later from **Run now**.
   - Google Drive connected: **Save 7 notes to Google Drive/…** uploads through the Drive export service, keyed by one operation ID for history and the free-export allowance. Drive not connected or needing reauthorization: **Finish setup**. The daily schedule is enabled only for a ready Drive folder.
6. **Make it daily?** Shows the schedule (every morning at 8:00, yesterday's note) and the trial timeline. **Start 7-day free trial** purchases the yearly subscription's introductory offer and turns the schedule on. Users not eligible for the introductory offer see **Subscribe for daily notes** and the yearly price instead of the trial timeline. An API destination without a URL is never scheduled. **Not now, I'll export manually** leaves the automation manual.

Setup ends on Automations with the configured automation.

## Recovery and access

- Onboarding configures the existing Default automation and renames it **Daily note**; it never creates a second automation.
- Packs set the automation's metrics exactly; more can be added from the automation's fields later. Metrics enabled later are requested from Apple Health when the automation's metrics page closes.
- Without paid access the automation card says **Manual** (or **Daily schedule needs paid access** when a schedule is switched on) and shows **Daily at 8:00 AM is off · Automatic notes need a subscription · Try free**. It never shows a next run it cannot keep.
- Denied permissions, a skipped folder and a cancelled trial purchase do not trap users in setup.
- Saved API endpoints are shared: an automation's Output page lists them with a visible edit button and **New endpoint**. Editing one applies to every automation that uses it; deleting one unbinds those automations and clears the live endpoint, so they never send elsewhere.
- Share My Setup transfers preferences; destinations must be rebound locally.
- Existing usage counts are preserved. Purchase, restore and subscription expiry do not replenish an already consumed free export. Failed exports do not consume the allowance; one that writes output consumes it, even when some days fail. A failed save offers **Continue without saving**; a replayed setup with the allowance used finishes without exporting.

## Implementation

`OnboardingView` (`iOS/Views/OnboardingView.swift`) owns the step state; the step views are in `iOS/Views/OnboardingSteps.swift`. `OnboardingMetricPack` (`Shared/Models/OnboardingMetricPack.swift`) maps the shared pack IDs (`sleep`, `activity`, `heart`, `body`, `mind`, `nutrition`, `cycle`) to HealthKit metric IDs; members are platform-specific (Apple HRV is SDNN; State of Mind is Apple-only). `HealthKitManager.requestAuthorization(forMetricIDs:)` makes the pack-scoped request.

`ContentView` supplies `OnboardingServices`: packs are applied to the active profile's metric selection, the preview fetches each day with the frozen capture settings and renders the same Markdown as the export, and the save runs `ExportOrchestrator.exportDates`, records history and consumes the free allowance only when output was written. Finishing renames the migration Default profile and, with paid access, upserts its daily 8:00 schedule entry (`lookbackDays` 1) and refreshes scheduled automation. `PurchaseManager.freeExportLimit` is one.

These source changes do not qualify StoreKit products or device behavior. Runtime and store purchase QA require separate explicit authorization.
