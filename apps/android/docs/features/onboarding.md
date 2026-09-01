# Onboarding

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** Onboarding
- **Source files:** `app/src/main/java/com/healthmd/presentation/onboarding/OnboardingScreen.kt`, `OnboardingViewModel.kt`

## What it does

First-run setup walks through a welcome, Health Connect access, an export folder, distribution-specific access information, and a ready screen. Granting Health Connect permission or picking a folder auto-advances after a short pause, and the Health and Folder steps can be skipped—you can complete them later from the Export tab. The Play build offers the optional lifetime purchase; the F-Droid build explains that full access is included and has no purchase controls.

## Who it is for

- New users on a first install.
- Anyone re-running setup after clearing app data.
- Not for existing users; onboarding runs once and is marked complete when you tap through the final page.

## Where to find it

1. Install Health.md from Google Play or F-Droid and open it for the first time.
2. Swipe (or use Back/Continue) through the five pages: **Welcome → Health → Storage → Unlock → Ready** on Play, or **Welcome → Health → Storage → Included → Ready** on F-Droid.
3. On the Ready page, tap to finish and land on the Export tab.

## Prerequisites

- Android 9 / API 28 or newer.
- Health Connect installed and set up (the Health page offers to open install or setup when needed).
- A folder you can grant write access to, if you want to pick a destination during setup.

## Setup

1. **Welcome** — review what Health.md does. If you already have a shared setup file, tap **Use a Shared Setup** to review and apply a `.healthmdconfig` file instead of configuring by hand (the shared-setup surface also lives under Settings after onboarding).
2. **Health** — tap to grant Health Connect read access. The page shows a green check when permission is granted and continues automatically.
3. **Storage** — tap to open the Android folder picker and choose where exports are written. The selected folder name is shown and the page continues automatically.
4. **Access** — on Play, optionally buy the lifetime unlock or restore a purchase; **Continue free** keeps the 10 free export actions. On F-Droid, confirm the included full-access explanation and continue without a paywall.
5. **Ready** — finish setup.

## Example output

A completed onboarding ends on the Export tab with your folder shown under **Export Folder** and Health Connect granted. Your first export is one tap away (see ./manual-export.md).

## Tips

- Skipped steps are not lost: re-grant permissions from the Export tab's permission notice, and pick a folder any time from **Export Folder → Select**.
- Onboarding respects your system layout direction and swipes right-to-left in RTL locales.
- The Play unlock page always shows, even for existing purchasers, so restore is reachable on a new device. F-Droid never shows purchase or restore controls.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| "Health Connect not available" on the Health page | Health Connect missing or disabled | Use the page's install/open button, then return to Health.md |
| Health page shows an error after granting | The permission screen closed without a grant, or an availability check failed | Retry the grant; reopen the app so the status re-checks |
| Folder not remembered | Provider did not grant persistent access | Re-select the folder; prefer a provider that keeps write permission across restarts |
| Auto-advance felt too fast | Pages continue ~0.8s after success | Swipe back if you want to re-read a page |

## Video outline

- **Suggested title:** Health.md for Android: 60-Second Setup
- **Hook:** "Three taps from install to your first health note."
- **Demo flow:**
  1. Fresh install → Welcome page.
  2. Grant Health Connect access, auto-advance.
  3. Pick a folder, unlock (or continue free), Ready.
- **Key screenshot/recording moments:** green check on the Health page, folder name appearing, Ready page.
- **CTA / next video:** ./manual-export.md.

## Implementation notes

`OnboardingScreen.kt` is a five-page `HorizontalPager`. `onboardingPages(DistributionPolicy)` selects either `PLAY_ACCESS` (embedded `PaywallScreen`) or `INCLUDED_ACCESS` without changing the shared surrounding flow. Permission requests use `HealthConnectManager.getPermissionContract()` with a `permissionPlan()` built from `HealthConnectPermissionPolicy`; unavailable providers route to install (`HealthConnectIntentLauncher.openInstallOrUpdate`) or Health Connect settings. Folder selection uses `ActivityResultContracts.OpenDocumentTree()` and persists a persistable URI permission (see ./health-connect-permissions.md and ./folder-destination.md). Auto-advance is keyed to `pagerState.settledPage` and gated by `allowAutomaticAdvance` (used by tests). Play step events use the bounded first-party `OnboardingEventSink`; F-Droid binds a no-op sink and creates no analytics identity or state. Deliberate difference from Apple: Android launches the system Health Connect permission sheet rather than an in-app type picker.
