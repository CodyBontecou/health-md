# Full Access Unlock

## Status

- **Docs status:** draft
- **Video priority:** medium
- **Primary screens:** Post-preview offer; 3rd/7th export reminder; hard-quota paywall; Settings restore
- **Source files:** `HealthMd/iOS/Views/PaywallView.swift`, `HealthMd/iOS/Views/ExportUpgradePrompt.swift`, `HealthMd/Shared/Managers/PurchaseManager.swift`, `HealthMd/iOS/ContentView.swift`

## What it does

Full Access removes the shared free export limit. Free users can complete 10 accounted export actions across manual, scheduled, Shortcut, and direct workflows. One action can write several formats or dates and still consumes one use.

Health.md offers Individual Lifetime and Family Lifetime one-time purchases, plus a Family Lifetime upgrade for eligible Individual or legacy owners. There is no recurring subscription. Family Lifetime uses Apple Family Sharing for up to five family members under Apple's eligibility and Purchase Sharing rules.

## Offer timing

The purchase flow is designed not to block setup prematurely:

1. Onboarding itself has no paywall step.
2. After the first real export preview closes, an eligible locked user sees one dismissible Full Access offer per install.
3. A soft, dismissible upgrade prompt can appear after the 3rd and 7th completed free exports.
4. After all 10 actions are used, another accounted export is blocked until purchase or restore.

Dismissing the post-preview, 3rd-export, or 7th-export offer does not spend an export or remove remaining quota.

## Where to find it

- The one-time offer after the first onboarding export preview.
- The soft prompt after the 3rd and 7th successful free actions.
- The hard-quota paywall when another export is attempted after 10 uses.
- Restore and plan-management controls in the paywall/settings surfaces.

## Products

- Individual Lifetime: `com.codybontecou.obsidianhealth.unlock`
- Family Lifetime: `com.codybontecou.obsidianhealth.unlock.family`
- Family Lifetime Upgrade: `com.codybontecou.obsidianhealth.unlock.family.upgrade`

The App Store sheet and StoreKit product are the live localized price authority.

## Free export accounting

```text
Free export limit: 10
One manual action exporting Markdown + JSON + CSV for 7 days: 1 use
One accepted scheduled request exporting one or more dates: 1 use
One dismissed soft upgrade prompt: 0 uses
```

The counter is Keychain-backed. Durable retries use idempotent job accounting so resuming the same accepted job does not consume another use. Unlocking clears accumulated free-use state.

## Restore and legacy access

Tap **Restore Purchase** while signed into the purchasing Apple ID. For Family Lifetime, confirm Family Sharing, Purchase Sharing, and purchase visibility. Earlier paid users can be recognized through StoreKit app-transaction history and the bounded legacy verification path; successful verification is cached in Keychain.

Legacy verification concerns entitlement evidence only. It does not include health values, selected metrics, export files, or folder paths.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Offer appears before 10 uses | Non-blocking post-preview or 3rd/7th reminder | Dismiss it to retain the remaining allowance. |
| Export is blocked | The 10-action allowance is exhausted | Purchase Full Access or restore an existing entitlement. |
| Price is missing | StoreKit product unavailable or still loading | Check network/App Store state and retry. |
| Family restore fails | Purchase Sharing, Apple ID, or purchase visibility mismatch | Correct Apple Family settings, reopen Health.md, and restore again. |
| Scheduled export pauses | The shared allowance is exhausted | Unlock or restore, then use the normal pending/retry flow. |

## Video outline

- **Suggested title:** Try Health.md, Then Unlock Unlimited Exports
- **Hook:** “Your first 10 successful export actions are free.”
- **Demo flow:** complete onboarding without a gate → inspect first preview → dismiss the offer → show remaining quota → demonstrate a 3rd/7th reminder → show restore.
- **Key captures:** preview dismissal, quota-aware subtitle, soft prompt, plan choices, restore.

## Implementation notes

- `PurchaseManager.freeExportLimit` is `10`.
- `PurchaseManager.upgradePromptMilestones` is `[3, 7]`.
- `ExportUpgradePrompt` is non-blocking and consumes only the pending prompt state.
- The one-time post-onboarding offer is armed by onboarding completion and presented after the first preview's dismissal transaction.
- `PaywallContext.onboarding` uses quota-aware copy rather than claiming the free allowance is exhausted.
- Durable scheduled and direct jobs use job-ID-based accounting.
- StoreKit entitlements, family eligibility, and legacy paths remain separate from health data access.
