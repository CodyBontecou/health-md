# Lifetime Unlock

## Status

- **Docs status:** draft
- **Video priority:** low
- **Primary screen:** Settings → Unlock (paywall)
- **Source files:** `app/src/main/java/com/healthmd/presentation/paywall/PaywallScreen.kt`, `app/src/main/java/com/healthmd/data/billing/BillingRepositoryImpl.kt`, `app/src/main/java/com/healthmd/domain/billing/FreemiumPolicy.kt`

## What it does

Health.md is free to try with **10 free manual export actions**, then unlocks forever with a **one-time lifetime purchase** through Google Play Billing. No subscription, no recurring charge — the live price is always shown by Google Play inside the app.

## Who it is for

- Everyone: the free tier exists to verify permissions, folder access, formats, and your Obsidian workflow before paying
- Lifetime unlock buyers get unlimited exports and automated scheduled exports
- Not a data plan — purchases never relate to where your data goes

## Where to find it

1. Open **Settings**.
2. Tap **Unlock** / **Unlock Health.md**, or hit the paywall when the free limit is reached.

## Prerequisites

- A Google account with Google Play
- Internet access for the purchase

## Setup

1. Use your free exports to confirm everything works.
2. Open the paywall and tap **Unlock for …** (live price shown).
3. Complete the Google Play purchase, or **Restore Purchase** after reinstalling or switching phones.

## Example output

Paywall rows: **Unlimited exports, forever** · **Automated scheduled exports** · **All future features included** · **One-time payment — no subscription**.

## Tips

- The counter tracks **export actions, not files**: exporting Markdown + JSON + CSV for a whole range still counts as **one** action.
- Free actions cover manual exports; scheduled automation requires the unlock ("Scheduled exports require the lifetime unlock").
- Restore Purchase reclaims the unlock on a new device or after reinstall.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| "No previous purchase" | Not signed into the purchasing account | Sign into the same Google account, then Restore Purchase |
| Unlock lost after reinstall | Purchase not restored yet | Tap Restore Purchase |
| "Export failed: unlock required" | Free limit reached or schedule gated | Retry after unlocking |

## Video outline

- **Suggested title:** Free to Try, Yours Forever
- **Hook:** "Ten exports to prove it works. One payment, forever."
- **Demo flow:** run a free export → hit the paywall → unlock → schedule unlocks.
- **Key screenshot/recording moments:** feature rows, price button, restore.
- **CTA / next video:** Scheduled Exports.

## Implementation notes

`FreemiumPolicy.FREE_EXPORT_LIMIT = 10`; `canExport(isUnlocked, freeExportsUsed)` gates manual runs and `ExportAccountingPolicy` counts actions across every trigger (manual, scheduled, automation). `BillingRepositoryImpl` wraps Google Play Billing 7 acknowledgements/purchases; `PaywallScreen` maps `BillingError` cases (`PRODUCT_UNAVAILABLE`, `SERVICE_UNAVAILABLE`, `PURCHASE_FAILED`, `NO_PREVIOUS_PURCHASE`, `RESTORE_FAILED`) to user copy. Apple's equivalent unlock is documented separately in the Apple feature docs; pricing mechanics differ by platform store.
