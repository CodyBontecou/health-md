# Lifetime Access

## Status

- **Docs status:** implemented
- **Video priority:** low
- **Primary screen:** Settings → Unlock (Google Play); included during onboarding (F-Droid)
- **Source files:** `app/src/main/java/com/healthmd/domain/distribution/DistributionPolicy.kt`, `app/src/main/java/com/healthmd/domain/repository/EntitlementRepository.kt`, `app/src/main/java/com/healthmd/domain/repository/PurchaseRepository.kt`, `app/src/play/java/com/healthmd/data/billing/BillingRepositoryImpl.kt`, `app/src/fdroid/java/com/healthmd/data/access/FdroidAccessRepository.kt`

## What it does

Health.md has one channel-neutral entitlement outcome: access to unlimited manual exports, scheduled exports, automation, recovery, and Direct CLI export.

- **Google Play:** 10 free manual export actions, followed by a one-time lifetime purchase through Google Play Billing. There is no subscription.
- **F-Droid:** full access is included. There is no free counter, paywall, product lookup, purchase, or restore action.

The distribution difference does not change export formats, bytes, schemas, or direct-device protocol behavior.

## Google Play flow

1. Use the free exports to verify permissions, folder access, formats, and the Obsidian workflow.
2. Open **Settings → Unlock**, or follow the paywall after the free limit.
3. Tap **Unlock for …** using the live Play price, or **Restore Purchase** for an existing purchase.

The counter tracks export actions, not files: one action that writes Markdown, JSON, and CSV for a date range still consumes one free action.

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
