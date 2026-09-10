# Android validation lanes

`validate_wear_release` is a non-publishing development lane retained for the deferred Wear OS implementation. It builds and validates both candidate AABs without Play credentials or mutation.

The current Android `1.9.1` publication path is phone-only and does not invoke Fastlane. `.github/workflows/android-release.yml` uploads the exact tagged phone artifact to Internal Testing, and `.github/workflows/android-promote-production.yml` promotes that exact version code and submits it for review. Wear upload, screenshots, and paired-track automation remain dormant until the planned `1.10.0` requalification cycle.

Never run credentialed Play mutation from Fastlane or a developer workstation.
