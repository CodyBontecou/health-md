# Onboarding

## What it does

First-run setup guides users through Health Connect access, an export folder, and creating an automation. On Google Play, the first real export is free and further exports require active paid access. Previews do not consume the allowance or open a purchase offer. F-Droid continues to include Full Access without purchase controls.

## Setup

1. Review Welcome, or use **Use a Shared Setup** to import preferences.
2. Grant Health Connect read access. When unavailable, install/open Health Connect and complete setup. Permission and folder steps may be skipped and repaired later.
3. Choose a writable folder using the Android folder picker. The app retains persistent URI access.
4. F-Droid shows its included-access explanation; Play does not insert an access/purchase page.
5. On Ready, tap **Create My First Automation**. Setup completes and opens the normal creator in Automations.
6. Name the automation and choose its metrics, formats, and destination, then create it.
7. Review the automation and use **Run now** to generate the first export for free. Repair missing permissions/folder access before exporting.
8. Review the export result. A later export asks for paid access once the allowance is consumed.

## Recovery and access

- Cancelling the creator keeps Automations available. Use **+** to try again.
- Existing setup can be changed from Export now, Automations, and Settings.
- The app and existing files remain reachable after the allowance is used.
- Existing usage is retained through purchase, restore, and expiry; these events do not grant another free export.
- Failed exports do not consume a use. Partial output consumes one action, so a retry may require paid access.
- Scheduled execution requires paid access on Play. Creating an automation and running its first manual export do not require a purchase.

## Implementation

`onboardingPages` selects Welcome → Health → Folder → Ready for Play, inserting Included Access for F-Droid. Permission/folder success auto-advances after approximately 0.8 seconds; tests can disable this. The saved one-shot creation request opens the standard automation editor after completion. Export entry points enforce the one-action allowance via `FreemiumPolicy`, settings usage accounting, and live billing admission; navigation does not replace the app with a root paywall.

Permission requests use `HealthConnectPermissionPolicy` and the system Health Connect contract. Folder selection uses `OpenDocumentTree` and persistent URI permission. No custom onboarding analytics are collected.
