# Full Access Unlock

## Status

- **Docs status:** draft
- **Video priority:** medium
- **Primary screen:** Export paywall; Settings/Restore Purchase
- **Source files:** `HealthMd/iOS/Views/PaywallView.swift`, `HealthMd/Shared/Managers/PurchaseManager.swift`, `HealthMd/iOS/ContentView.swift`

## What it does

Full Access Unlock removes the free export limit and enables the complete Health.md workflow with a one-time in-app purchase. Free users can try 3 successful export actions. After that, Health.md shows the unlock screen before additional exports.

The unlock is handled by Apple StoreKit 2. There is no Health.md subscription for the current unlock: it is a one-time payment, and the paywall copy says “Unlimited exports, forever” and “All future features included.”

## Who it is for

- Users who want unlimited manual exports.
- Users who want automated scheduled exports.
- Users who use Health.md as a daily Obsidian workflow.
- Legacy users restoring or verifying access after reinstalling.

## Where to find it

Health.md shows the unlock screen when an export is blocked by the free limit.

You may encounter it from:

1. **Export** → **Export Health Data** after free exports are used.
2. Scheduled export setup when Full Access is required.
3. Restore purchase controls on the paywall.

## Prerequisites

- Apple ID signed in to the App Store.
- Network access for StoreKit product loading, purchase, and restore.
- Health.md installed from TestFlight or the App Store for production purchases.
- A valid App Store Connect product: `com.codybontecou.obsidianhealth.unlock`.

## Setup

To unlock:

1. Open Health.md.
2. Start an export after the free quota is used, or open the paywall from the app.
3. Tap **Unlock for [price]** or **Unlock Full Access**.
4. Confirm the purchase with Apple.
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
Free export limit: 3
One button press exporting Markdown + JSON + CSV for 7 days: 1 export use
```

The counter is stored in Keychain so deleting and reinstalling the app does not grant another free trial. When a user becomes unlocked, Health.md clears any accumulated free-export count.

## Legacy user behavior

Health.md includes legacy unlock paths for earlier paid users. It checks Apple StoreKit app transaction data and can verify legacy status with the Health.md worker. Successful server verification is cached in Keychain so access survives future reinstalls.

## Tips

- Use the 3 free exports to confirm HealthKit permission, folder access, and preferred formats before unlocking.
- Unlock before relying on scheduled exports.
- If the price does not load, check network access and try again later.
- Use **Restore Purchase** after reinstalling or moving to a new device.
- If you were an earlier paid user and restore fails, contact support with the diagnostics block.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Paywall appears when exporting | Free export quota is used | Unlock Full Access or restore a previous purchase. |
| Price is missing | StoreKit product did not load yet | Check internet, reopen the paywall, and try again. |
| Purchase fails | App Store transaction failed or was cancelled | Try again and confirm the Apple purchase sheet. |
| Restore says no purchase found | Apple ID has no entitlement or StoreKit has not synced | Confirm the Apple ID, then try restore again. |
| Legacy access not detected | Local receipt/AppTransaction unavailable after reinstall | Use Restore Purchase or contact support for legacy verification help. |
| Scheduled export is blocked | Scheduled exports require unlock after free limit | Unlock Full Access before depending on automation. |

## Video outline

- **Suggested title:** Unlock Unlimited Apple Health Exports in Health.md
- **Hook:** “Health.md lets you test exports first, then unlock unlimited exports with one purchase.”
- **Demo flow:**
  1. Show the free exports remaining label on Export.
  2. Use the final free export.
  3. Trigger the paywall.
  4. Explain unlimited exports, scheduled exports, future features, and one-time purchase.
  5. Show Restore Purchase.
  6. Return to Export and run another export after unlock.
- **Key screenshot/recording moments:** free exports label, paywall feature rows, unlock button, restore button, successful export after unlock.
- **CTA / next video:** “Next, we’ll set up scheduled exports now that Full Access is enabled.”

## Implementation notes

- `PurchaseManager.productID` is `com.codybontecou.obsidianhealth.unlock`.
- `freeExportLimit` is `3`.
- `canExport` returns true when unlocked or when free exports remain.
- `recordExportUse()` increments the Keychain-backed counter once per successful export action and no-ops for unlocked users.
- `PaywallView` presents the StoreKit purchase and restore actions and dismisses when `isUnlocked` becomes true.
- Legacy unlock checks use AppTransaction date logic plus optional worker verification at `healthmd-receipt-verifier.costream.workers.dev`.
