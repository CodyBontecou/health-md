# Google Play Store deployment

Health.md currently publishes the Android phone app only. The Wear OS companion is deferred to the planned `1.10.0` qualification cycle and is not included in the `1.9.1` Play upload or production promotion. See `release-scope.json`.

## Protected release environment

Repository administrators—not local release operators—maintain the `google-play` GitHub environment:

1. Allow deployments only from tags matching `android/v*`.
2. Store `PLAY_CONSOLE_KEY_JSON` for the Play service account authorized for this app's Internal Testing and production tracks.
3. Store the existing upload-signing values: `ANDROID_RELEASE_KEYSTORE_BASE64`, `RELEASE_STORE_PASSWORD`, `RELEASE_KEY_ALIAS`, and `RELEASE_KEY_PASSWORD`.
4. Keep the service account app-scoped and grant only the Play permissions required to upload bundles, update the reviewed English listing, manage testing/production releases, and submit changes for review.
5. Never copy the mutation credential or upload keystore onto a developer workstation.

The Android Publisher OAuth scope is broad. App-level Play Console grants, the tag-restricted GitHub environment, exact-source workflow checks, and ephemeral credential cleanup provide the practical boundary.

## Optional local read-only inspection

A separate app-level read-only service account may be stored outside the repository for diagnostic scripts. It must not have upload, track, review, metadata, pricing, or production permissions. Do not place a QA or production mutation key on a developer workstation.

## Authored Play metadata

Canonical metadata lives under `play-console/`. `play-console/locales.json` determines which locales are reviewed and publishable. For the current release, `en-US` is the reviewed listing and release-note locale.

Validate it locally with:

```bash
cd apps/android
./scripts/validate-play-listing.sh
```

The reviewed full description must describe only capabilities present in the phone artifact. It must not advertise the deferred Wear OS companion.

## Version management

Every upload requires a phone `versionCode` higher than every phone build previously uploaded to Play. Update `versionCode` and `versionName` in `app/build.gradle.kts`, then update `release-scope.json`, release notes, and readiness tests in the same commit. Do not rely on an uncommitted CI-time increment.

The deferred `:wear` module retains its independent 1,000,000+ code range, but its code is neither validated as part of phone release identity nor uploaded by the current release workflows.

## Canonical workflow behavior

`.github/workflows/android-release.yml`:

- accepts only an annotated `android/v<version>` tag whose peeled commit is reachable from `origin/main`;
- re-runs the complete Android CI workflow for that exact commit;
- verifies `release-scope.json` declares phone release and deferred Wear scope;
- materializes signing inputs only under `$RUNNER_TEMP`;
- builds and inspects only `app-play-release.aab`;
- retains the signed AAB and a tag/SHA/run-attempt/AAB-digest-bound intent before obtaining Play credentials;
- uploads the phone AAB and exact release notes to `internal` in one validated Play edit;
- issues the non-idempotent commit once and reconciles exact track state if the response is lost.

`.github/workflows/android-promote-production.yml`:

- must be dispatched from the exact annotated release tag;
- verifies the requested version/code against that immutable source and `release-scope.json`;
- retains a pre-mutation intent before materializing the Play credential;
- requires the exact code on `internal` and rejects a newer production code;
- applies the reviewed English listing, promotes only that phone artifact to `production`, and submits the single validated edit for review;
- verifies an accepted review lifecycle and retains an attempt-qualified receipt.

No current workflow uploads `:wear`, writes `wear:internal`/`wear:production`, or requires physical-watch evidence. Dormant Wear workflows must remain unused until a future source change explicitly restores Wear publication and its independent evidence gates.

## Release commands

Operators use Git and GitHub Actions, not local Play mutation tools:

1. Push a clean, qualified release commit to `main`.
2. Create and push annotated tag `android/v<version>`.
3. Monitor `Android Release` through the Internal Testing upload receipt.
4. Dispatch `Android Promote production` from the same tag with the exact phone version and code.
5. Confirm the workflow-reported Google Play lifecycle is in review, approved, or published.

See `PLAY_STORE_COMMANDS.md` for the checklist and `PLAY_CONSOLE_BROWSER_PROMPT.md` for read-only Console auditing.

## Troubleshooting

### Service account not found

Verify the protected environment's `PLAY_CONSOLE_KEY_JSON` and app-level Play Console invitation. Do not copy the credential locally.

### Invalid version code

Confirm the committed phone code is higher than every prior Play upload and matches `release-scope.json`.

### Invalid localization

Run `./scripts/validate-play-listing.sh`; only reviewed locales are publication inputs.

### Release not submitted

Inspect the production workflow's lifecycle query and receipt. Success requires `IN_REVIEW`, `APPROVED_NOT_PUBLISHED`, or `PUBLISHED`; a merely uploaded or not-sent release is not a successful submission.
