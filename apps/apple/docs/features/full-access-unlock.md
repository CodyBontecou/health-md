# Full Access Unlock

## Status

- **Docs status:** draft
- **Video priority:** medium
- **Primary screen:** Export paywall; Settings/Restore Purchase
- **Source files:** `HealthMd/iOS/Views/PaywallView.swift`, `HealthMd/Shared/Managers/PurchaseManager.swift`, `HealthMd/iOS/ContentView.swift`, `HealthMd/iOS/SchedulingManager.swift`

## What it does

Full Access Unlock removes the shared free export limit. Free users can run 10 successful export actions across manual, scheduled, Shortcut, and direct workflows. After that, additional exports pause until the user unlocks Full Access or restores a purchase.

The unlock is handled by Apple StoreKit 2. Health.md offers Individual Lifetime and Family Lifetime one-time purchases, plus a Family Lifetime upgrade for existing Individual Lifetime or eligible legacy owners. Family plans use Apple Family Sharing for households that want to share access with up to 5 family members.

## Who it is for

- Users who want unlimited manual exports.
- Users who want unlimited, uninterrupted scheduled exports.
- Users who use Health.md as a daily Obsidian workflow.
- Families who want to share Health.md through Apple Family Sharing.
- Legacy users restoring or verifying access after reinstalling.

## Where to find it

Health.md shows the unlock screen when an export is blocked by the free limit.

You may encounter it from:

1. **Export** → **Export Health Data** after free exports are used.
2. A scheduled run after the shared free export allowance is exhausted.
3. Restore purchase controls on the paywall.

## Prerequisites

- Apple ID signed in to the App Store.
- Network access for StoreKit product loading, purchase, and restore.
- Health.md installed from TestFlight or the App Store for production purchases.
- Valid App Store Connect products:
  - Individual Lifetime: `com.codybontecou.obsidianhealth.unlock`
  - Family Lifetime: `com.codybontecou.obsidianhealth.unlock.family` with Family Sharing enabled
  - Family Lifetime Upgrade: `com.codybontecou.obsidianhealth.unlock.family.upgrade` with Family Sharing enabled.

## Setup

To unlock:

1. Open Health.md.
2. Start an export after the free quota is used, or open the paywall from the app.
3. Choose an Individual Lifetime or Family Lifetime option. Eligible existing owners can choose the Family Lifetime upgrade.
4. Confirm the one-time purchase with Apple.
5. Wait for the paywall to dismiss.
6. Continue exporting normally.

To restore:

1. Open the paywall.
2. Tap **Restore Purchase**.
3. Stay online while StoreKit refreshes entitlements.
4. If eligible, Health.md unlocks and dismisses the paywall.

## Free export behavior

Health.md counts export actions, not individual files.

Example:

```text
Free export limit: 10
One manual action exporting Markdown + JSON + CSV for 7 days: 1 export use
One scheduled request that exports one or more dates: 1 export use
```

The counter is stored in Keychain so deleting and reinstalling the app does not grant another free trial. When a user becomes unlocked, Health.md clears any accumulated free-export count.

## Legacy user behavior

Health.md includes legacy unlock paths for earlier paid users. It checks Apple StoreKit app transaction data and can verify legacy status with the Health.md worker. Successful server verification is cached in Keychain so access survives future reinstalls.

## Tips

- Use the 10 free exports to confirm HealthKit permission, folder access, and preferred formats before unlocking.
- Scheduled and manual exports draw from the same 10-export allowance; unlock for uninterrupted automation.
- If the price does not load, check network access and try again later.
- Use **Restore Purchase** after reinstalling or moving to a new device. Family members should use Restore Purchase while signed into an Apple ID in the purchaser’s Family Sharing group.
- For Family plans, the purchaser must have Apple **Purchase Sharing** enabled and Health.md must not be hidden from purchase history. If those settings were just changed, reopen Health.md on the family member’s device and restore again.
- If you were an earlier paid user and restore fails, contact support with the diagnostics block.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Paywall appears when exporting | Free export quota is used | Unlock Full Access or restore a previous purchase. |
| Price is missing | StoreKit product did not load yet | Check internet, reopen the paywall, and try again. |
| Purchase fails | App Store transaction failed or was cancelled | Try again and confirm the Apple purchase sheet. |
| Restore says no purchase found | Apple ID has no active entitlement, Family Purchase Sharing is off, Health.md is hidden from purchase history, or StoreKit has not synced | Confirm the Apple ID, then try restore again. For Family plans, confirm Apple Family Sharing and Purchase Sharing are enabled, then reopen the app and restore again. |
| Legacy access not detected | Local receipt/AppTransaction unavailable after reinstall | Use Restore Purchase or contact support for legacy verification help. |
| Scheduled export pauses | The shared 10-export allowance is exhausted | Unlock Full Access or restore a purchase; the pending schedule can then resume. |

## Video outline

- **Suggested title:** Unlock Unlimited Apple Health Exports in Health.md
- **Hook:** “Health.md lets you test exports first, then unlock unlimited exports with one purchase.”
- **Demo flow:**
  1. Show the free exports remaining label on Export.
  2. Use the final free export.
  3. Trigger the paywall.
  4. Explain that manual and scheduled runs share the free allowance, while Full Access makes both unlimited.
  5. Show Restore Purchase.
  6. Return to Export and run another export after unlock.
- **Key screenshot/recording moments:** free exports label, paywall feature rows, unlock button, restore button, successful export after unlock.
- **CTA / next video:** “Next, we’ll set up scheduled exports and show how successful runs use the shared free allowance.”

## Implementation notes

- `PurchaseManager.productID` is the Individual Lifetime product `com.codybontecou.obsidianhealth.unlock`.
- `PurchaseManager.familyProductID` is the Family Lifetime product `com.codybontecou.obsidianhealth.unlock.family`.
- `PurchaseManager.familyUpgradeProductID` is the Family Lifetime Upgrade product `com.codybontecou.obsidianhealth.unlock.family.upgrade`.
- `freeExportLimit` is `10`.
- `canExport` returns true when unlocked or when free exports remain; durable scheduled retries can continue after their job ID has already consumed one use.
- `recordExportUse()` increments the Keychain-backed counter once per successful export action and no-ops for unlocked users. Durable scheduled and direct jobs use the idempotent job-ID overload.
- `PaywallView` presents Individual Lifetime, Family Lifetime, and eligible Family Lifetime Upgrade StoreKit options plus restore, and dismisses when `isUnlocked` becomes true.
- Legacy unlock checks use AppTransaction date logic plus optional worker verification at `healthmd-receipt-verifier.costream.workers.dev`.
