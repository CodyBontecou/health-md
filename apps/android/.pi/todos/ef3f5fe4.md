{
  "id": "ef3f5fe4",
  "title": "P1: Bring Android onboarding to iOS parity",
  "tags": [
    "android",
    "parity",
    "p1",
    "onboarding",
    "paywall"
  ],
  "status": "closed",
  "created_at": "2026-06-05T14:39:30.169Z"
}

## Goal
Align Android first-run onboarding with iOS setup and education flow.

## Current gap
Android onboarding is a 4-page flow (welcome, Health Connect, folder, ready). iOS has a 5-step flow with an unlock/free-export step, clearer privacy/technical messaging, and specific folder naming behavior.

## Key files
- `app/src/main/java/com/healthmd/presentation/onboarding/OnboardingScreen.kt`
- `app/src/main/java/com/healthmd/presentation/onboarding/OnboardingViewModel.kt`
- `app/src/main/java/com/healthmd/presentation/paywall/PaywallScreen.kt`
- iOS reference: `HealthMd/iOS/Views/OnboardingView.swift`

## Acceptance criteria
- Onboarding includes Health Connect permission, folder selection, and unlock/free-export education.
- Folder selection captures any needed Health.md subfolder default/name behavior.
- Users can continue if Health Connect permission is denied but get clear guidance to fix later, matching iOS intent.
- Existing users with folder/setup are not forced through onboarding again.
- Paywall/free quota state is visible when relevant.

Implemented onboarding parity improvements:
- Onboarding is now a 5-step flow with unlock/free-export education.
- Users can continue past Health Connect guidance even before granting permissions, with setup guidance preserved.
- Existing skip behavior for folder/setup remains; existing users with a saved folder still bypass onboarding.
- Free quota/purchased state is visible in the unlock education page.

Validation: `./gradlew testDebugUnitTest` passes.
