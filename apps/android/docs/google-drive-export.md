# Google Drive export (Android)

Google Drive is a first-class profile destination implemented with Google Play services `AuthorizationClient` and the Drive v3 REST API. Exported health bytes travel directly from the Android app to Google. Health.md operates no health-data upload proxy or Google token server.

## Build configuration

Create separate test and production Google Cloud projects. In each project:

1. Enable the **Google Drive API** and **Google Picker API**.
2. Configure and publish the Google OAuth consent screen with the deployed Health.md homepage and privacy-policy URLs.
3. Create an Android OAuth client for the exact application ID and signing-certificate SHA fingerprints.
4. Supply the public client identifier as either a Gradle property or environment variable:

   ```properties
   GOOGLE_DRIVE_ANDROID_CLIENT_ID=000000000000-actual-client.apps.googleusercontent.com
   ```

   ```bash
   export GOOGLE_DRIVE_ANDROID_CLIENT_ID='000000000000-actual-client.apps.googleusercontent.com'
   ```

The identifier is public configuration, not a client secret. Never add a web-client secret or token broker to the APK. Missing, placeholder, or malformed configuration compiles but leaves Google Drive visibly unavailable as `configuration_missing`.

The implementation pins `com.google.android.gms:play-services-auth:21.6.0` because that release contains the mobile Picker folder resource parameters. Authorization requests only `https://www.googleapis.com/auth/drive.file`, opts out of inherited scopes, and independently validates the Drive account permission ID and selected folder capability.

## Execution and recovery

- One local destination record binds an encrypted Android `Account` reference, Drive `user.permissionId`, immutable folder ID, optional Shared Drive ID/resource key, and privacy-safe labels.
- Profiles, manual exports, compatibility exports, raw snapshots plus `.sha256` sidecars, legacy schedules, and profile schedules use the same durable Drive runner.
- Existing output bytes are materialized through the authoritative Android export planner. Append, Markdown Update, and Daily Note merge stage complete final bytes before any upload.
- New objects use persisted generated IDs. Resumable sessions, offsets, exact parents, remote versions, and checksums are journaled under private no-backup storage.
- A retry checks for and resumes the retained journal before reading Health Connect. History is written before the journal is acknowledged and eligible for completed-journal pruning.
- Android does not expose a serverless refresh token. Scheduled work requests an access token silently for the exact encrypted account. If Google returns a resolution, Health.md reports `reauthorization_required`, retains the journal, and resumes it after foreground authorization.
- Shared Drives use `supportsAllDrives=true`, capability checks, and resource-key headers. Names are never update authority.

`drive.file` cannot reveal every unrelated pre-existing child. Health.md manages files created by this OAuth application and never adopts prior Files/SAF or other-app exports automatically. Use a new or empty folder; accessible unowned same-name objects fail closed.

## Release gates

Before enabling the capability, run production-shaped Pixel tests for Picker return, account switching, Shared Drives, revocation, foreground resolution after process death, locked-device/background scheduling, resumable interruption/session expiry, quota/rate limits, conflicts, checksum verification, and disconnect. Complete Google OAuth publication, Play Data safety/Health apps declarations, review instructions, localization review, and the repository-wide checklist in [`docs/qa/google-drive-export-release-checklist.md`](../../../docs/qa/google-drive-export-release-checklist.md).
