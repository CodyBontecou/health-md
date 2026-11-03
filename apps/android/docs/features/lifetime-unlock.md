# Lifetime Access

## Status

- **Docs status:** implemented
- **Video priority:** low
- **Primary screen:** Settings → Unlock (Google Play); included during onboarding (F-Droid)
- **Source files:** `app/src/main/java/com/healthmd/domain/distribution/DistributionPolicy.kt`, `app/src/main/java/com/healthmd/domain/repository/EntitlementRepository.kt`, `app/src/main/java/com/healthmd/domain/repository/PurchaseRepository.kt`, `app/src/play/java/com/healthmd/data/billing/BillingRepositoryImpl.kt`, `app/src/fdroid/java/com/healthmd/data/access/FdroidAccessRepository.kt`

## What it does

Health.md has one channel-neutral entitlement outcome: access to unlimited manual exports, scheduled exports, automation, recovery, and Direct CLI export.

- **Google Play:** a hard paywall before tracking/setup. Choose Individual weekly ($0.99 US), yearly ($29.99 US), or Lifetime ($49.99 US). Eligible subscriptions include a seven-day store-backed free trial; Lifetime is charged immediately. Existing paid and grandfathered permanent access is retained. Android has no Family plans.
- **F-Droid:** full access is included. There is no free counter, paywall, product lookup, purchase, or restore action.

The distribution difference does not change export formats, bytes, schemas, or direct-device protocol behavior.

## Google Play flow

1. Choose a plan using the localized Play price, or **Restore Purchase** for existing paid access.
2. Complete setup to connect permissions and choose a destination.
3. Manage or cancel a subscription through Google Play. Canceling renewal preserves access until the paid-through/trial end; expired subscriptions do not become Lifetime access.

Historical export counters are retained for migration but grant no new free actions. Missing products and failed verification do not bypass the gate. Subscription-only users need Play connectivity after a process restart. See the [billing guide](../../GOOGLE_PLAY_BILLING_SETUP.md) for lifecycle and qualification boundaries.

## F-Droid flow

No setup is required. Onboarding states that full access is included, and Settings shows the F-Droid channel plus source and AGPL links instead of purchase controls. More than ten exports, schedules, automation intents, recovery, and Direct CLI remain admitted through the same entitlement interfaces.

## Channel switching

Google Play and F-Droid use different signing keys. Switching requires uninstall/reinstall, which removes local app state. Health.md does not promise transfer of Play purchases, settings, history, credentials, or app-private files across signatures. Exported files remain wherever the user saved them.

## Troubleshooting

| Problem | Channel | Fix |
| --- | --- | --- |
| "No previous purchase" | Google Play | Sign into the purchasing Google account, then Restore Purchase |
| Unlock lost after reinstall | Google Play | Restore the purchase with the same account |
| Purchase controls are missing | F-Droid | Expected: full access is already included |
| Export reports unlock required | F-Droid | This is a defect; capture the channel shown in Settings and file an issue |

## Implementation notes

`DistributionPolicy` declares channel capabilities. Consumers gate behavior through `EntitlementRepository`, not Billing classes. The Play implementation combines current/cached Billing entitlement with `PurchaseRepository`; the F-Droid repository exposes a stable unlocked state and unavailable purchase operations. `ExportAccountingPolicy` never consumes a free action for an unlocked entitlement. Workers, automation, recovery, Direct CLI, schedules, export view models, and paywall navigation all use these channel-neutral boundaries.

## Trial and permanent access

Trials are store subscription entitlements, not a local timer or export allowance. Only permanent purchases are persisted in the historical purchase flag; subscription access is re-queried from Play. Workers, automation, recovery, and Direct CLI verify access before new work. No first/third-export soft upsells remain. F-Droid continues to include Full Access without purchase prompts.

These source changes do not establish configured products, live prices, or store approval. Store setup and authorized exact-build purchase testing remain release prerequisites.
