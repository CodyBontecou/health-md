# Paid access, trials, and restore

## Scope

This guide describes the subscription-enabled source for the planned 3.5.0 phone release. Store preparation is not a public release; see the [rollout status](../experiments/subscription-pricing-rollout.md). Earlier distributed versions can show the former export allowance.

## Access before setup

On iPhone and iPad, a root paywall precedes setup for users without access. Start an eligible store-backed trial, subscribe, buy Lifetime, or restore an existing purchase. There is no local free-export allowance or dismissible first/third-export offer. An unavailable catalog, canceled purchase, or pending purchase does not grant access.

Individual and Apple Family Sharing each offer weekly, yearly, and Lifetime access. Family shares access with up to five other eligible family members through Apple; it does not share health records, folders, or exports. The Mac companion remains free. Google Play offers Individual weekly/yearly/Lifetime; the F-Droid build includes access without billing. Apple purchases do not transfer to Google Play.

## Trials and billing

Eligible subscriptions include a 7-day free trial, then automatically renew at the localized price and interval displayed by the store. Apple or Google determines eligibility; installing the app, completing setup, switching plans, or reinstalling does not guarantee a trial. Lifetime is charged once immediately, without a trial or recurring renewal.

Manage subscriptions with the purchasing Apple or Google account. For Apple subscriptions, cancel at least 24 hours before the trial or current period ends; follow the applicable store confirmation for your offer. Deleting Health.md or buying Lifetime does not cancel an existing subscription.

## Existing purchases and restore

Existing lifetime purchases, eligible Family Sharing transactions, and previously granted legacy access remain valid. Use Restore Purchase with the purchasing account. If Family restore fails, check Apple's purchase/subscription sharing settings and purchase visibility. Store restoration recovers access, not deleted local files.

The discounted Family Lifetime upgrade is for eligible Individual Lifetime or legacy owners. A subscription alone does not qualify. Existing product IDs remain unchanged; see the rollout document for the four subscription IDs. Prices come from StoreKit/Play, not source-code fallback amounts. Higher lifetime targets remain on hold and are not current offers.

## When access ends

Expired or revoked subscriptions block new exports and setup through the root gate. Exported files already saved to your destinations remain yours. Pending/manual/scheduled/Shortcut/direct admission checks use the same access requirement; an old usage ledger does not grant a free action. After restoring access, inspect pending work and use the normal recovery path.

## Troubleshooting

| Problem | Action |
|---|---|
| No trial appears | The store may consider the account ineligible. Review the paid terms before confirming. |
| Prices are missing | Retry loading the catalog after checking the store/network. Do not infer access from a loading failure. |
| Export or scheduling is blocked | Restore or obtain active access, then inspect the pending attempt. |
| Family access is missing | Check the purchasing account's Family Sharing settings, then restore. |
| Old files are missing | Purchases restore access only; check your chosen folder or backups. |

Implementation owners: `PurchaseAccessGate`, `PurchaseManager`, `PaywallView`, and `OnboardingPurchaseDisclosure`. `freeExportLimit` is zero for the paid phone flow and `upgradePromptMilestones` is empty. Historical post-preview state is not the unpaid entry point.
