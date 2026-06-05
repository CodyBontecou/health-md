{
  "id": "c2cde34c",
  "title": "P1: Wire free-export quota and paywall gates",
  "tags": [
    "android",
    "parity",
    "p1",
    "billing",
    "paywall"
  ],
  "status": "closed",
  "created_at": "2026-06-05T14:38:20.431Z"
}

## Goal
Make Android monetization behavior match iOS: 3 free exports, then one-time unlock for unlimited exports/scheduling.

## Current gap
Google Play Billing repository, paywall UI, and PaywallViewModel exist, but exports and scheduling are not gated. `SettingsRepository.isPurchased` also appears separate from BillingRepository unlock state.

## Key files
- `app/src/main/java/com/healthmd/data/billing/BillingRepositoryImpl.kt`
- `app/src/main/java/com/healthmd/presentation/paywall/PaywallScreen.kt`
- `app/src/main/java/com/healthmd/presentation/paywall/PaywallViewModel.kt`
- `app/src/main/java/com/healthmd/presentation/export/ExportViewModel.kt`
- `app/src/main/java/com/healthmd/presentation/schedule/ScheduleViewModel.kt`
- iOS reference: `PurchaseManager.swift`, `PaywallView.swift`, onboarding unlock step

## Acceptance criteria
- Track free export usage in durable storage (prefer encrypted storage, not reset on normal reinstall if possible).
- Manual exports check quota before starting; successful export action consumes one quota.
- Scheduled exports require unlock or are blocked with paywall.
- Onboarding includes/links unlock offer or equivalent.
- Paywall auto-dismisses after purchase/restore.
- Billing unlock state is the single source of truth or synchronized cleanly with settings.

Implemented P1 billing/paywall gating updates:
- Scheduled exports now require purchase/unlock in `ScheduleViewModel` and `ExportWorker`.
- Paywall unlock state is synchronized with persisted settings and auto-dismiss remains driven by combined unlock state.
- Manual export quota remains enforced and successful full exports consume quota.
- Onboarding now includes free-export/unlock education.

Validation: `./gradlew testDebugUnitTest` passes.
