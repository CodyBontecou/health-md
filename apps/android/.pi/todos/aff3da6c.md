{
  "id": "aff3da6c",
  "title": "P2: Android accessibility parity audit and fixes",
  "tags": [
    "android",
    "parity",
    "accessibility",
    "ui",
    "p2"
  ],
  "status": "open",
  "created_at": "2026-06-05T19:36:18.168Z"
}

## Goal
Run an Android accessibility pass equivalent to the iOS VoiceOver/Dynamic Type polish and fix high-impact TalkBack/font-scaling issues.

## Current gap
- iOS changelog calls out full VoiceOver support, Dynamic Type, announcements, and hiding decorative elements.
- Android has Material/Compose UI but has not had a documented TalkBack/font-scale audit in this parity pass.

## Key files
- Android UI root/navigation: `app/src/main/java/com/healthmd/presentation/navigation/HealthMdNavigation.kt`
- Android screens: `app/src/main/java/com/healthmd/presentation/export/ExportScreen.kt`, `schedule/ScheduleScreen.kt`, `history/HistoryScreen.kt`, `settings/*.kt`, `onboarding/OnboardingScreen.kt`, `paywall/PaywallScreen.kt`
- Shared components: `app/src/main/java/com/healthmd/presentation/common/*.kt`
- iOS reference notes: `/Users/codybontecou/projects/health-md/app/CHANGELOG.md`

## Acceptance criteria
- Audit primary flows with TalkBack: onboarding, permission request, folder selection, export, preview, schedule setup, history retry, settings/customization, paywall.
- Add clear `contentDescription`/semantics to icon-only actions and custom cards/buttons.
- Mark decorative images/glows/backgrounds as non-accessibility content.
- Ensure status badges/progress dialogs announce meaningful state changes.
- Verify UI remains usable at large Android font scales and display sizes.
- Ensure touch targets meet Material minimum sizing.
- Add Compose UI/accessibility checks where practical.
- Document remaining known limitations in `docs/`.

## Notes
This ticket should not change feature behavior unless required for accessibility.
