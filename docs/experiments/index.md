# Experiments

| Experiment | Window | Status |
| --- | --- | --- |
| [$14.99 lifetime price (ISO-294)](./2026-09-17-19.99-lifetime-price.md) | 2026-06-01 → 2026-09-16 | Kept — results recorded in the $19.99 note |
| [$19.99 lifetime price](./2026-09-17-19.99-lifetime-price.md) | 2026-09-17 → | In progress |

## Operational sources

Notes record deployed price evidence, decision rules, and results at decision time.
Use ASC/Google Play price schedules and commerce reports for production price and proceeds.
StoreKit `.storekit` files and code fallback strings describe local/test behavior, not proof of
a deployed price or its effective date. Record the territory, report window, and reporting lag.

For D1 event definitions, privacy boundaries, mature conversion denominators, and query commands,
use the [pricing analytics Worker runbook](../../apps/apple/worker/pricing-analytics/README.md).
Its [Wrangler configuration](../../apps/apple/worker/pricing-analytics/wrangler.toml) selects the
pricing service; Practice and wake are separate services, not pricing-data sources.

## Historical plans

The [original ISO-294 plan](../../apps/apple/docs/experiments/health-md-1499-lifetime-price-experiment.md)
is preserved under the Apple component. Its results log was never filled; actual results and the
corrected production timeline are recorded in the $19.99 note above. The plan's three-export
assumption is historical and does not describe current quota behavior. Imported history retains
its former path at `1511ae5ea:docs/experiments/health-md-1499-lifetime-price-experiment.md`.
