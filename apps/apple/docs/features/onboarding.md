# Onboarding

## What it does

First-run setup guides users through Health access, an export folder, sample output, and creating an automation. The first real export is free; further exports require active paid access. Previews do not consume the allowance or trigger a paywall.

Apple and Google Play Android share this outcome. The free macOS companion and F-Droid included-access policy are unchanged. Existing paid and grandfathered users retain access. Store-backed subscription trials remain separate from the first free export.

## Setup

1. Connect Apple Health, or choose **Skip for Now** and connect later.
2. Select an Obsidian vault, iCloud Drive, or another Files folder. This can also be skipped and repaired later.
3. Review sample Markdown, JSON, CSV, or Bases output and the optional Obsidian plugin link.
4. On Ready, tap **Create My First Automation**.
5. Name the automation and choose its metrics, formats, and destination, then tap **Create**.
6. Review the automation in the composer and use **Run now** to generate the first export for free. Missing Health/folder access must be repaired before writing files.
7. Review the completed export. A later export requests paid access after the free allowance is consumed.

Creating/editing automations, viewing previews, and opening existing files remain available without a purchase. Scheduling is configured on each automation; background execution remains subject to access and OS scheduling rules.

## Recovery and access

- Cancelling the creator leaves the Automations tab available; use **+** to try again.
- Denied permissions and cancelled folder selection do not trap users in setup.
- Share My Setup transfers preferences; destinations must be rebound locally.
- Configure Connected Mac after onboarding to write files on macOS.
- Existing usage counts are preserved. Purchase, restore, and subscription expiry do not replenish an already consumed free export.
- Failed exports do not consume the allowance; an action that writes output consumes one use, even when some requested days fail. Retrying after a partial export can therefore require paid access.

## Implementation

`OnboardingStep` is welcome → Health access → folder → sample → ready. The one-shot completion request selects Automations and opens its normal creator. After creation, the composer exposes settings and Run now. `PurchaseManager.freeExportLimit` is one; the existing durable usage ledger is retained. Export entry points enforce access after the allowance, while `PurchaseAccessGate` keeps the app reachable and refreshes access on activation. No post-preview purchase prompt runs.

These source changes do not qualify StoreKit products or device behavior. Runtime and store purchase QA require separate explicit authorization.
