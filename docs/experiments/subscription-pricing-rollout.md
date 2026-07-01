# Health.md Subscription Pricing Rollout

## Entitlement contract

Existing premium users are grandfathered forever. Any verified transaction for the existing lifetime products keeps unlocking all premium features after reinstall, restore purchases, device migration, and future app updates.

Legacy lifetime product IDs:

- `com.codybontecou.obsidianhealth.unlock`
- `com.codybontecou.obsidianhealth.unlock.family`
- `com.codybontecou.obsidianhealth.unlock.family.upgrade`

## New product matrix

Recommended App Store Connect setup:

| Audience | Cadence | Product ID | Suggested price |
|---|---|---|---:|
| Individual | Monthly | `com.codybontecou.obsidianhealth.pro.monthly` | $4.99/mo |
| Individual | Yearly | `com.codybontecou.obsidianhealth.pro.yearly` | $24.99/yr |
| Individual | Lifetime | `com.codybontecou.obsidianhealth.unlock` | $59.99 once |
| Family | Monthly | `com.codybontecou.obsidianhealth.pro.family.monthly` | $7.99/mo |
| Family | Yearly | `com.codybontecou.obsidianhealth.pro.family.yearly` | $39.99/yr |
| Family | Lifetime | `com.codybontecou.obsidianhealth.unlock.family` | $89.99 once |
| Lifetime owner upgrade | One-time | `com.codybontecou.obsidianhealth.unlock.family.upgrade` | TBD |

Yearly plans should be visually preferred. Monthly remains available as a flexible fallback, while lifetime stays as the ownership escape hatch.

## App behavior

All active paid plans unlock the same premium feature set:

- unlimited exports
- scheduled exports
- all future premium features

Family plans use Apple Family Sharing. The family upgrade remains gated in-app so only existing individual lifetime or grandfathered users can buy it.

## Analytics requirement

The rollout uses the pricing experiment assignment:

- Experiment ID: `pricing_subscription_transition`
- Baseline variant: `baseline_lifetime_only`
- Rollout variant: `subscription_lifetime_mix`

The analytics worker still accepts the previous lifetime-price experiment IDs so older released builds can flush queued events during the transition.

Use cohort conversion rather than raw revenue for the rollout decision:

- tracked install cohort → purchase
- activated install cohort → purchase
- paywall user cohort → purchase
- refund rate
- reviews/support mentioning subscription, pricing, or restore

Raw revenue is not enough because marketing spend/source mix can inflate top-of-funnel volume.

## Deployment checklist

Before App Store submission:

1. Create the App Store Connect subscription products and keep the legacy lifetime products active.
2. Confirm Family Sharing is enabled for all Family plans.
3. Apply the pricing analytics D1 migration before deploying the worker that writes `onboarding_step`.
4. Validate the updated local StoreKit configuration with monthly, yearly, lifetime, family, restore, and expired-subscription cases.
5. Confirm the paywall shows subscription auto-renewal disclosure plus Terms and Privacy links on iOS and macOS.
6. Submit through TestFlight first and verify StoreKit product loading with live App Store Connect products before phased release.
