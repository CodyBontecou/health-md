# Google Play command reference

## Current release ownership

The current Google Play release scope is **phone-only**. `release-scope.json` is the machine-readable source of truth. The selected release tag supplies the `:app` version name and code, while the `:wear` artifact is deferred and is not uploaded, promoted, or advertised by the phone app.

Gradle Play Publisher remains removed. Do not upload, promote, submit review, or replace Play metadata with ad hoc Gradle, Fastlane, browser, or local API commands. The separate final publication of already-approved changes under managed publishing is described below. Build uploads, track changes, metadata changes, and review submission use these protected mutation paths:

- `.github/workflows/android-release.yml` — qualifies an exact annotated, main-reachable `android/v<version>` tag, builds the signed phone AAB, retains SHA/AAB-bound intent evidence, and uploads it to `internal`.
- `.github/workflows/android-promote-production.yml` — runs from that exact tag, promotes the same phone version code from `internal` to `production`, applies the reviewed listing in that same edit, submits it for review, and verifies the resulting lifecycle.
- `.github/workflows/android-screenshots.yml` — replaces reviewed phone and tablet screenshots for all reviewed locales without writing tracks, listing copy, icons, or bundles. Requires the exact published release tag/code, a main-reachable annotated workflow tag, and assets identical to that release. Uses the protected `google-play` environment, retains the ordered SHA-256 intent before authentication, submits one edit for review, and verifies every committed digest and display order through a fresh disposable edit. Managed publishing remains a separate final Console action after approval.

`.github/workflows/android-google-play-access-audit.yml` is the only supported credential diagnostic. From an allowed annotated Android tag, it records exact Internal/generated-artifact state, inserts and immediately deletes one empty edit, and retains a receipt proving that no edit was committed. A separate no-upload job verifies that the protected keystore matches the registered Play upload certificate and retains only public certificate digests. The workflow cannot upload an artifact, change a track/listing, or submit review.

Both release workflows use the protected, tag-restricted `google-play` environment and short-lived Google Workload Identity Federation. The release build uses the separately tag-restricted `google-play-qa` environment only for upload signing; the private key is deleted before its exact signed AAB artifact enters the `google-play` mutation job. The environments normally allow `android/v*`; a retained `android/recovery/*` tag is permitted only for a main-reachable workflow-infrastructure fix that still binds all artifact work to the original immutable release tag. `google-play` stores the Workload Identity provider/service-account variables and does not need a long-lived Play JSON key or signing material. Generated AABs remain workflow artifacts and are never committed.

The Wear workflows and evidence tools remain in the repository as dormant implementation material for the planned `1.10.0` qualification cycle. They are not part of the current release sequence and must not be dispatched while Wear is deferred in the selected release scope.

## Safe local commands

Run from `apps/android`.

```bash
./gradlew :app:testPlayDebugUnitTest :app:testFdroidDebugUnitTest :direct-protocol:test
./gradlew :app:lintPlayDebug :app:lintFdroidDebug
./gradlew :app:assemblePlayDebug
./gradlew :app:bundlePlayRelease
./scripts/validate-play-listing.sh
```

A release build requires externally supplied signing configuration. Local substitute signing proves only build/package behavior and is not production-signing evidence.

The deferred Wear implementation may still be compiled and tested without publication:

```bash
./gradlew :wearable-contract:test :wear:testDebugUnitTest :wear:assembleDebug
bundle exec fastlane android validate_wear_release
```

## Authorized phone release sequence

1. Commit the complete source and push it to `origin/main`.
2. Require successful Android CI for that exact SHA.
3. Create an annotated `android/v<version>` tag at the exact main-reachable SHA. For a new build of an already tagged version, use `android/v<version>+<versionCode>` (for example `android/v3.5.0+44`). The suffix must equal the committed phone version code; never move an existing release tag. Both phone workflows and the production announcement validate this identity. Wear remains deferred and does not use these phone rebuild tags.
4. Let `.github/workflows/android-release.yml` re-run exact-SHA qualification and upload the phone AAB to Internal Testing.
5. Verify that workflow's signed AAB, immutable intent, and committed-upload receipt artifacts.
6. Dispatch `.github/workflows/android-promote-production.yml` from the exact annotated release tag with the exact version name and phone version code. Use its `release_tag` recovery input only from an annotated, main-reachable `android/recovery/*` workflow tag after an infrastructure-only fix; the checked-out product source remains the original release tag. An Internal-upload recovery also requires the successful exact-SHA Android CI run ID and attempt so the workflow can reverify all retained qualification jobs without rebuilding unchanged test inputs.
7. Require the workflow to prove `IN_REVIEW`, `APPROVED_NOT_PUBLISHED`, or `PUBLISHED` before treating the submission as successful.
8. Monitor Play review and publish the Android announcement only after Google Play reports the production release as published.

See `PLAY_STORE_SETUP.md` for protected credential setup. See `docs/features/wear-os-completion-audit.md` for the deferred Wear qualification work; it is not a phone-release gate.

## Command-line operator runbook

### Update screenshots for an already-published release

Use `android-screenshots.yml` from an immutable annotated release tag containing
the workflow, or a main-reachable `android/recovery/*` infrastructure tag when
repairing a missing screenshot upload path. Set `release_tag` to the original
published release and `version_code` to its phone code. The workflow rejects
assets that differ from that release, serializes with other Play mutations, and
changes only phone, seven-inch, and ten-inch screenshots. It excludes deferred Wear.
Inspect the retained intent and result artifacts. A successful receipt proves
committed screenshot hashes and order; it does not prove review approval or public
store propagation. A failed or lost commit response must be investigated before
another dispatch; never blindly repeat the edit. Publish the approved screenshot
batch using the final managed-publishing procedure below.

Run from the repository root with Git, GitHub CLI (`gh`), and `jq`. Set the
repository explicitly so an agent in another worktree cannot dispatch elsewhere:

```bash
repo=CodyBontecou/health-md
gh auth status
gh api "repos/$repo" --jq .full_name
git status --short
gh run list --repo "$repo" --workflow android-release.yml --limit 5
gh run list --repo "$repo" --workflow android-promote-production.yml --limit 5
```

First establish whether the owner means **new source**, **an existing Internal
Testing build**, or **an approved build waiting to go live**. For the latter two,
reuse the existing immutable tag and code. Do not bump the version, rebuild, merge
unrelated work, or include uncommitted changes just to publish an approved build.
Read version identity from the selected tag, not the current checkout:

```bash
tag=android/v3.5.2  # Example only: select the owner's intended release.
git fetch origin main --tags
scope=$(git show "$tag:apps/android/release-scope.json")
version=$(printf '%s' "$scope" | jq -er .releaseVersionName)
code=$(printf '%s' "$scope" | jq -er .googlePlay.phone.versionCode)
test "$(git cat-file -t "$tag")" = tag
git merge-base --is-ancestor "$tag^{commit}" origin/main
printf 'Release %s, phone code %s, tag %s\n' "$version" "$code" "$tag"
```

### New source: qualify and upload to Internal Testing

Complete the authorized source changes, version/scope/release-note updates, and
required checks before committing and pushing to `main`. Use an isolated worktree
if the current checkout has unrelated work. Follow the exact-source qualification
policy above; never move an existing release tag.

```bash
# Run after the qualified release commit is on origin/main.
release_sha=<exact-qualified-main-commit>
tag=android/v<version>
git merge-base --is-ancestor "$release_sha" origin/main
git tag -a "$tag" "$release_sha" -m "Android <version>"
git push origin "refs/tags/$tag"
gh run list --repo "$repo" --workflow android-release.yml \
  --commit "$release_sha" --json databaseId,headSha,headBranch,status,conclusion,url
```

Select the returned run whose SHA and tag match. Use that exact run ID for
monitoring and artifact inspection; never assume the newest repository run belongs
to this release:

```bash
upload_run=<matching-run-id>
gh run watch "$upload_run" --repo "$repo" --exit-status
gh run view "$upload_run" --repo "$repo"
gh api "repos/$repo/actions/runs/$upload_run/artifacts" \
  --jq '.artifacts[] | {id,name,expired}'
```

Verify the signed AAB, intent, and committed-upload receipt per the release
sequence above. A green build without a successful Internal upload is insufficient.

### Existing Internal build: submit production for review

Only dispatch this when the exact build still needs production promotion or review
submission. An approved managed-publishing build skips to the next section.

```bash
gh workflow run android-promote-production.yml --repo "$repo" --ref "$tag" \
  -f version="$version" -f version_code="$code"
gh run list --repo "$repo" --workflow android-promote-production.yml \
  --branch "$tag" --limit 5 \
  --json databaseId,headSha,headBranch,status,conclusion,url
promotion_run=<matching-new-run-id>
gh run watch "$promotion_run" --repo "$repo" --exit-status
gh run view "$promotion_run" --repo "$repo" --log
```

Check the receipt's exact SHA/code and `reviewLifecycle`. `IN_REVIEW` means
submitted, `APPROVED_NOT_PUBLISHED` means held after approval, and `PUBLISHED`
means live. All three can produce a successful promotion workflow. Re-running it
for an approved build is a no-op, not the managed-publishing release action.

### Approved build: final managed-publishing action

**There is currently no repository-supported CLI command for this final step.**
The protected promotion workflow deliberately stops at an accepted review
lifecycle. Do not invent a `gh`, Fastlane, Gradle, or `edits.commit` command that
claims to release a managed-publishing hold. Google documents approval and final
publication as separate steps in [managed publishing][managed-publishing];
[`edits.commit`][edits-commit] controls edit submission/review behavior.

When the owner explicitly requests publishing the approved release, use this
narrow Console action (or hand it to the owner when no signed-in session exists):

1. Open [Health.md Publishing overview][healthmd-publishing] under developer
   account **Cody R Bontecou** (`cody@isolated.tech`). Account indexes such as
   `/u/1/` vary by browser session; verify developer ID `8478281120215349264`,
   app ID `4974084218060959146`, and package `com.healthmd.android`.
2. Verify **Changes ready to publish** contains the intended production version
   and rollout scope. Inspect every accompanying listing change; the publish
   action applies to the ready batch. Resolve unrelated pending changes before
   publishing them under a release-only request.
3. Click **Publish N changes**, then **Publish changes** in the confirmation.
   Preserve managed publishing; do not toggle it off as a workaround.
4. Wait for the page to show an updated **Last published** date and no remaining
   ready changes. Report publication separately from store propagation; Console
   advises changes usually appear within an hour and can take longer.

This exception only publishes an already-reviewed batch. Uploads, metadata edits,
track promotion, and review submission remain owned by the protected workflows.
For `3.5.2` (phone code `48`), the approved batch was a full production rollout
plus the English full-description update. It was published on November 13, 2026.
That is an example of the final gate, not an instruction to repeat that release.

### Verify publication from the CLI without sending an announcement

The announcement workflow reads Play's release lifecycle using its dedicated
read-only credential. Dispatch **dry-run only** to check the exact code without
posting to Discord or writing the announcement status:

```bash
gh workflow run android-announce.yml --repo "$repo" --ref main \
  -f version_code="$code" -f dry_run=true
gh run list --repo "$repo" --workflow android-announce.yml --branch main --limit 5 \
  --json databaseId,event,status,conclusion,url
verification_run=<matching-new-manual-run-id>
gh run watch "$verification_run" --repo "$repo" --exit-status
gh run view "$verification_run" --repo "$repo" --log
```

Read the result, not just the exit status: this workflow also succeeds when no
matching published release exists. A matching published candidate for the exact
code proves API visibility; `No matching published production release is
available` does not. Scheduled announcements are managed separately; do not
manually dispatch `dry_run=false` without authorization to send the announcement.

### Access and retry handling

If `gh` reports a connection failure in a network-restricted agent shell, retry
with the environment's authorized network access before treating the token as
invalid. If authentication actually fails with network access, use `gh auth login
--hostname github.com`; never print tokens or copy Play credentials locally.
Protected environment approval, when configured, must be completed through its
normal GitHub gate. Do not bypass it.

On a failed mutation run, inspect its failed step, exact-source artifacts, and
Play postconditions before retrying. Use the documented recovery inputs only for
their intended workflow-only recovery case. Never blindly rebuild or repeat a
non-idempotent Play commit after a timeout.

[managed-publishing]: https://support.google.com/googleplay/android-developer/answer/9859654?hl=en
[edits-commit]: https://developers.google.com/android-publisher/api-ref/rest/v3/edits/commit
[healthmd-publishing]: https://play.google.com/console/developers/8478281120215349264/app/4974084218060959146/publishing
