# Experiments

| Experiment | Window | Status |
| --- | --- | --- |
| [$14.99 lifetime price (ISO-294)](./2026-09-17-19.99-lifetime-price.md) | 2026-06-01 → 2026-09-16 | Kept — results recorded in the $19.99 note |
| [$19.99 lifetime price](./2026-09-17-19.99-lifetime-price.md) | 2026-09-17 → | Live price retained pending the coordinated subscription launch |
| [Paid access, trials, and subscriptions](../../apps/apple/docs/experiments/subscription-pricing-rollout.md) | Pre-launch | Apple subscriptions READY_TO_SUBMIT with review screenshots complete; group/first-review preparation and purchase QA pending. Android 3.5.0/code 44 is available on Internal Testing with normal Play delivery and core license-test trial, purchase, restore, cancellation and expiry checks passed. Weekly/yearly plans and trials are Active; remaining production qualification is recorded in the Android billing guide. Lifetime pricing held unchanged |
| [Apple export competitor review brief](./2026-10-19-apple-export-competitors.md) | 2026-10-19 | Complete — public-source Treg trial; $0 spent |

## Operational sources

Notes record deployed price evidence, decision rules, and results at decision time.
Use ASC/Google Play price schedules and commerce reports for production price and proceeds.
StoreKit `.storekit` files and code fallback strings describe local/test behavior, not proof of
a deployed price or its effective date. Record the territory, report window, and reporting lag.

Custom app analytics are removed from the unpublished candidate. Use Apple/Google commerce reports for sales and subscription reporting. No price changes are included. The [retirement runbook](../../apps/apple/worker/pricing-analytics/README.md) covers the legacy endpoint and the separately approved deletion of historical analytics. Practice, wake, receipt verification, OAuth and scheduling remain separate essential services.

## Historical plans

The [original ISO-294 plan](../../apps/apple/docs/experiments/health-md-1499-lifetime-price-experiment.md)
is preserved under the Apple component. Its results log was never filled; actual results and the
corrected production timeline are recorded in the $19.99 note above. The plan's three-export
assumption is historical and does not describe current quota behavior. Imported history retains
its former path at `1511ae5ea:docs/experiments/health-md-1499-lifetime-price-experiment.md`.
