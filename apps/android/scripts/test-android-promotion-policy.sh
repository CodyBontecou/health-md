#!/usr/bin/env bash
set -euo pipefail

fail() { echo "phone release policy test: $*" >&2; exit 1; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# shellcheck source=google-play-phone-policy.sh
source "$(dirname "$0")/google-play-phone-policy.sh"

phone=39
play_phone_assert_version_code "$phone" || fail 'valid phone versionCode rejected'
for invalid in 0 1000000 1000039 nope; do
  if play_phone_assert_version_code "$invalid" >/dev/null 2>&1; then
    fail "invalid phone versionCode accepted: $invalid"
  fi
done

printf '%s\n' 'Dependable phone release.' > "$tmp/notes.txt"
play_phone_release_payload "$phone" completed en-US "$tmp/notes.txt" > "$tmp/release.json"
jq -e --arg code "$phone" '
  .releases == [{
    versionCodes:[$code],status:"completed",
    releaseNotes:[{language:"en-US",text:"Dependable phone release."}]
  }]
' "$tmp/release.json" >/dev/null || fail 'phone release payload is incorrect'
if play_phone_release_payload "$phone" halted en-US "$tmp/notes.txt" >/dev/null 2>&1; then
  fail 'invalid release status accepted'
fi

cat > "$tmp/response.json" <<'JSON'
{"track":"internal","releases":[{"status":"completed","versionCodes":["39"]}]}
JSON
play_phone_validate_track_response "$tmp/response.json" "$phone" completed \
  || fail 'valid phone track response rejected'
for bad in \
  '{"releases":[{"status":"completed","versionCodes":["39","40"]}]}' \
  '{"releases":[{"status":"draft","versionCodes":["39"]}]}' \
  '{"releases":[]}'; do
  printf '%s' "$bad" > "$tmp/bad.json"
  if play_phone_validate_track_response "$tmp/bad.json" "$phone" completed >/dev/null 2>&1; then
    fail "invalid track response accepted: $bad"
  fi
done

cat > "$tmp/internal.json" <<'JSON'
{"track":"internal","releases":[
  {"name":"old","status":"completed","versionCodes":["38"]},
  {"name":"1.9.1","status":"completed","versionCodes":["39"],
   "releaseNotes":[{"language":"en-US","text":"Dependable phone release."}],
   "userFraction":0.5,"countryTargeting":{"countries":["US"]},"inAppUpdatePriority":5}
]}
JSON
play_phone_promotion_payload "$tmp/internal.json" production "$phone" "$tmp/production.json"
jq -e --arg code "$phone" '
  .track == "production" and (.releases | length == 1) and
  .releases[0].versionCodes == [$code] and .releases[0].status == "completed" and
  .releases[0].releaseNotes[0].language == "en-US" and
  (.releases[0] | has("userFraction") or has("countryTargeting") or has("inAppUpdatePriority") | not)
' "$tmp/production.json" >/dev/null || fail 'phone promotion payload is incorrect'
if play_phone_promotion_payload "$tmp/internal.json" production 40 "$tmp/missing.json" >/dev/null 2>&1; then
  fail 'missing source version accepted'
fi
if play_phone_promotion_payload "$tmp/internal.json" wear:production "$phone" "$tmp/wrong.json" >/dev/null 2>&1; then
  fail 'Wear production destination accepted by phone policy'
fi

repo=$(cd "$(dirname "$0")/../../.." && pwd)
release="$repo/.github/workflows/android-release.yml"
promotion="$repo/.github/workflows/android-promote-production.yml"
uploader="$(dirname "$0")/upload-google-play-phone-release.sh"
scope="$(dirname "$0")/../release-scope.json"
manifest="$(dirname "$0")/../app/src/play/AndroidManifest.xml"
runtime="$(dirname "$0")/../app/src/play/java/com/healthmd/distribution/PlayDistributionRuntime.kt"
distribution_policy="$(dirname "$0")/../app/src/main/java/com/healthmd/domain/distribution/DistributionPolicy.kt"
listing="$(dirname "$0")/../play-console/listing/en-US/full-description.txt"

jq -e '
  .schemaVersion == 1 and .releaseVersionName == "1.9.1" and
  .googlePlay.phone.status == "release_candidate" and
  .googlePlay.phone.versionCode == 39 and
  .googlePlay.phone.testingTrack == "internal" and
  .googlePlay.phone.productionTrack == "production" and
  .googlePlay.wear.status == "deferred" and
  .googlePlay.wear.published == false and
  .googlePlay.wear.runtimeAdvertisedByPhone == false
' "$scope" >/dev/null || fail 'release-scope.json does not declare the phone-only candidate'

for workflow in "$release" "$promotion"; do
  grep -q 'environment: google-play' "$workflow" || fail "$workflow does not use the protected google-play environment"
  grep -q 'release-scope.json' "$workflow" || fail "$workflow does not enforce release-scope.json"
  grep -q 'wear.status == "deferred"' "$workflow" || fail "$workflow does not enforce deferred Wear status"
  if grep -Eq 'wear_version_code|wear:internal|wear:production|:wear:bundleRelease|upload-google-play-paired-release' "$workflow"; then
    fail "$workflow still publishes or promotes Wear"
  fi
done

grep -q 'sha="$(git rev-parse "${tag}^{commit}")"' "$release" \
  || fail 'release identity does not peel the annotated tag'
grep -q 'RELEASE_SHA: ${{ needs.resolve.outputs.release_sha }}' "$release" \
  || fail 'release job is not bound to the peeled tag commit'
grep -q 'test "$(git rev-parse HEAD)" = "$RELEASE_SHA"' "$release" \
  || fail 'release checkout is not bound to the exact SHA'
grep -q 'uses: ./.github/workflows/android-ci.yml' "$release" \
  || fail 'release does not requalify the exact source through Android CI'
grep -q 'Build signed phone app bundle' "$release" || fail 'release does not build the phone bundle'
grep -q './scripts/upload-google-play-phone-release.sh' "$release" || fail 'release bypasses phone uploader'
grep -q 'wearIncluded:false' "$release" || fail 'release intent does not record phone-only scope'
grep -q 'healthmd-android-phone-upload-${{ steps.version.outputs.version }}-${{ steps.version.outputs.release_sha }}-attempt-${{ github.run_attempt }}' "$release" \
  || fail 'phone upload intent is not SHA/attempt bound'
intent_line=$(grep -n 'Retain immutable phone upload intent receipt' "$release" | head -1 | cut -d: -f1)
credential_line=$(grep -n 'Configure ephemeral Google Play credential' "$release" | head -1 | cut -d: -f1)
upload_line=$(grep -n 'Upload phone bundle to Internal Testing' "$release" | head -1 | cut -d: -f1)
[[ "$intent_line" =~ ^[0-9]+$ && "$credential_line" =~ ^[0-9]+$ && "$upload_line" =~ ^[0-9]+$ ]] \
  || fail 'release intent/credential/upload stages are missing'
(( intent_line < credential_line && credential_line < upload_line )) \
  || fail 'phone intent is not retained before credential materialization and upload'

grep -q 'release-notes/$locale/default.txt' "$uploader" || fail 'uploader omits canonical release notes'
if grep -q '/listings/' "$uploader"; then
  fail 'internal uploader must leave listing mutation for the atomic production review edit'
fi
grep -q 'CONFIRM_PLAY_PHONE_UPLOAD' "$uploader" || fail 'uploader lacks explicit exact upload confirmation'
grep -q 'play_phone_release_payload' "$uploader" || fail 'uploader bypasses tested payload policy'
grep -q 'editCommitted:true' "$uploader" || fail 'uploader does not produce a committed-state receipt'
grep -q 'commit_response_received=true' "$uploader" || fail 'uploader cannot classify response reconciliation'
grep -q 'commit_exit_code -eq 22' "$uploader" || fail 'uploader can relabel a definite HTTP rejection'
grep -q 'reconciledExisting:true' "$uploader" || fail 'uploader cannot safely recover a completed prior attempt'
[[ $(grep -c ':commit?changesNotSentForReview=' "$uploader") -eq 1 ]] \
  || fail 'uploader must contain exactly one non-idempotent Play commit'
if grep -Eq -- '--retry [0-9]+.*:commit|:commit.*--retry [0-9]+' "$uploader"; then
  fail 'uploader retries the non-idempotent Play commit'
fi

grep -q 'test "$GITHUB_REF_NAME" = "android/v$VERSION"' "$promotion" \
  || fail 'production dispatch is not bound to the exact release tag'
grep -q 'test "$(git cat-file -t "$GITHUB_REF_NAME")" = tag' "$promotion" \
  || fail 'production dispatch does not require an annotated tag'
grep -q 'git merge-base --is-ancestor "$tagged_sha" refs/remotes/origin/main' "$promotion" \
  || fail 'production tag is not required to be main-reachable'
grep -q 'play_phone_promotion_payload' "$promotion" \
  || fail 'production workflow bypasses tested payload policy'
grep -q 'play-console/listing/$locale' "$promotion" \
  || fail 'production review edit omits the reviewed Play listing'
grep -q 'google-play-listing-update.json' "$promotion" \
  || fail 'production workflow does not verify its listing update response'
grep -q 'versionCode $VERSION_CODE is not active on Internal Testing' "$promotion" \
  || fail 'production workflow does not require the exact internal artifact'
grep -q 'changesNotSentForReview=false&changesInReviewBehavior=ERROR_IF_IN_REVIEW' "$promotion" \
  || fail 'production commit does not submit the release for review'
grep -q 'RELEASE_LIFECYCLE_STATE_IN_REVIEW' "$promotion" \
  || fail 'production workflow does not verify review lifecycle'
grep -q 'android-phone-production-${{ inputs.version }}-${{ steps.release.outputs.sha }}-attempt-${{ github.run_attempt }}' "$promotion" \
  || fail 'production receipt is not SHA/attempt bound'
grep -q 'wearIncluded:false' "$promotion" || fail 'production intent omits phone-only scope'
grep -q 'commit_response_received=true' "$promotion" \
  || fail 'production commit cannot distinguish a received response from reconciliation'
grep -q 'commit_exit_code -eq 22' "$promotion" \
  || fail 'production can relabel a definite HTTP rejection'
[[ $(grep -c ':commit?changesNotSentForReview=' "$promotion") -eq 1 ]] \
  || fail 'production workflow must contain exactly one Play commit'
if grep -Eq -- '--retry [0-9]+.*:commit|:commit.*--retry [0-9]+' "$promotion"; then
  fail 'production workflow retries the non-idempotent Play commit'
fi
promotion_intent_line=$(grep -n 'Retain immutable phone promotion intent' "$promotion" | head -1 | cut -d: -f1)
promotion_credential_line=$(grep -n 'Configure ephemeral Google Play credential' "$promotion" | head -1 | cut -d: -f1)
promotion_mutation_line=$(grep -n 'Promote exact phone artifact and submit it for review' "$promotion" | head -1 | cut -d: -f1)
[[ "$promotion_intent_line" =~ ^[0-9]+$ && "$promotion_credential_line" =~ ^[0-9]+$ && "$promotion_mutation_line" =~ ^[0-9]+$ ]] \
  || fail 'production intent/credential/mutation stages are missing'
(( promotion_intent_line < promotion_credential_line && promotion_credential_line < promotion_mutation_line )) \
  || fail 'production intent is not retained before credential materialization and mutation'

if grep -Eq 'WearPhoneDataLayerService|com\.google\.android\.gms\.wearable|android:scheme="wear"' "$manifest"; then
  fail 'phone manifest still advertises or receives Wear Data Layer traffic'
fi
[[ ! -e "$(dirname "$0")/../app/src/play/res/values/wear.xml" ]] \
  || fail 'phone capability resource still advertises Wear support'
[[ ! -e "$(dirname "$0")/../app/src/main/res/raw/keep_wear.xml" ]] \
  || fail 'phone resource shrinker still preserves a Wear capability'
if grep -Eq 'WearPhoneSync|WearPhoneSyncScheduler' "$runtime"; then
  fail 'Play runtime still starts Wear synchronization'
fi
grep -A12 'fun play()' "$distribution_policy" | grep -q 'wearSyncAvailable = false' \
  || fail 'Play UI policy still exposes Wear settings'
if grep -Eqi 'WEAR OS COMPANION|Health\.md watch app' "$listing"; then
  fail 'reviewed Play listing still advertises the deferred watch app'
fi
if grep -R -E '<string name="release_notes_highlight_workouts">.*Wear OS' \
    "$(dirname "$0")/../app/src/main/res" >/dev/null; then
  fail 'localized in-app release notes still advertise Wear OS'
fi

grep -Fq "'.github/workflows/android-*.yml'" "$repo/.github/workflows/android-ci.yml" \
  || fail 'Android workflow changes do not trigger main-push Android CI'

printf '%s\n' 'Android phone-only release policy tests passed'
