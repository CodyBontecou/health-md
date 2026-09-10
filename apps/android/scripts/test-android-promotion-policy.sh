#!/usr/bin/env bash
set -euo pipefail

fail() { echo "phone release policy test: $*" >&2; exit 1; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
test_script_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=google-play-phone-policy.sh
source "$test_script_dir/google-play-phone-policy.sh"
uploader="$test_script_dir/upload-google-play-phone-release.sh"

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

# The uploader must accept a short-lived Workload Identity token and fail closed if it cannot
# establish exact track state. A failed read must never fall through to edit creation.
mock_root="$tmp/mock-release"
mkdir -p "$mock_root/app/build/outputs/bundle/playRelease" \
  "$mock_root/play-console/listing/en-US/release-notes/en-US" "$tmp/bin"
printf 'signed-aab-fixture' > "$mock_root/app/build/outputs/bundle/playRelease/app-play-release.aab"
printf 'Dependable phone release.\n' \
  > "$mock_root/play-console/listing/en-US/release-notes/en-US/default.txt"
cat > "$tmp/bin/curl" <<'SH'
#!/bin/sh
set -eu
printf '%s\n' "$*" >> "$MOCK_CURL_LOG"
output=''
write_out=''
url=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o|--output) output=$2; shift 2 ;;
    -w|--write-out) write_out=$2; shift 2 ;;
    http://*|https://*) url=$1; shift ;;
    *) shift ;;
  esac
done
case "$url" in
  */tracks/internal/releases) ;;
  *) echo "unexpected mock Play request: $url" >&2; exit 90 ;;
esac
if [ "${MOCK_PLAY_MODE:-deny}" = reconcile ]; then
  printf '%s' '{"releases":[{"activeArtifacts":[{"versionCode":"39"}]}]}' > "$output"
  [ -z "$write_out" ] || printf '200'
  exit 0
fi
printf '%s' '{"error":{"code":403,"status":"PERMISSION_DENIED","message":"track read denied"}}' > "$output"
[ -z "$write_out" ] || printf '403'
exit 22
SH
chmod +x "$tmp/bin/curl"
upload_env=(
  PATH="$tmp/bin:$PATH"
  PLAY_RELEASE_ROOT="$mock_root"
  PLAY_PHONE_POLICY_PATH="$test_script_dir/google-play-phone-policy.sh"
  PLAY_ACCESS_TOKEN=do-not-print-this-token
  CONFIRM_PLAY_PHONE_UPLOAD=com.healthmd.android:internal:39
  PHONE_VERSION_CODE=39
  PHONE_PLAY_TRACK=internal
  PLAY_RELEASE_STATUS=completed
  PLAY_UPLOAD_RECEIPT_PATH="$tmp/mock-receipt.json"
  MOCK_CURL_LOG="$tmp/mock-curl.log"
)
if env "${upload_env[@]}" "$uploader" >"$tmp/mock-denied.log" 2>&1; then
  fail 'uploader accepted an unavailable exact-track preflight'
fi
grep -q 'preflight track query failed (HTTP 403): PERMISSION_DENIED: track read denied' "$tmp/mock-denied.log" \
  || fail 'uploader omitted bounded Play-stage diagnostics'
grep -q 'refusing to create a Play edit without an exact-track reconciliation result' "$tmp/mock-denied.log" \
  || fail 'uploader did not fail closed after the track error'
! grep -q 'do-not-print-this-token' "$tmp/mock-denied.log" || fail 'uploader printed its access token'
[[ $(wc -l < "$tmp/mock-curl.log") -eq 1 ]] || fail 'uploader made a request after failed preflight'
! grep -q '/edits' "$tmp/mock-curl.log" || fail 'uploader created an edit after failed preflight'

: > "$tmp/mock-curl.log"
env "${upload_env[@]}" MOCK_PLAY_MODE=reconcile "$uploader" >"$tmp/mock-reconciled.log" 2>&1
jq -e '.versionCode == 39 and .track == "internal" and .editCommitted == true and
  .reconciledExisting == true and .commitResponseReceived == false' "$tmp/mock-receipt.json" >/dev/null \
  || fail 'uploader did not retain a reconciled Workload Identity receipt'
[[ $(wc -l < "$tmp/mock-curl.log") -eq 1 ]] || fail 'reconciliation made an unnecessary Play request'

repo=$(cd "$(dirname "$0")/../../.." && pwd)
release="$repo/.github/workflows/android-release.yml"
promotion="$repo/.github/workflows/android-promote-production.yml"
access_audit="$repo/.github/workflows/android-google-play-access-audit.yml"
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
  grep -q 'google-github-actions/auth@7c6bc770dae815cd3e89ee6cdf493a5fab2cc093' "$workflow" \
    || fail "$workflow does not use the pinned Workload Identity action"
  grep -q 'GOOGLE_PLAY_WORKLOAD_IDENTITY_PROVIDER' "$workflow" \
    || fail "$workflow omits the protected Workload Identity provider"
  grep -q 'GOOGLE_PLAY_SERVICE_ACCOUNT' "$workflow" \
    || fail "$workflow omits the protected Google Play service account"
  if grep -q 'PLAY_CONSOLE_KEY_JSON' "$workflow"; then
    fail "$workflow still materializes a long-lived Google Play key"
  fi
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
grep -q '.release-tooling/apps/android/scripts/upload-google-play-phone-release.sh' "$release" \
  || fail 'release bypasses the SHA-bound phone uploader'
grep -q 'PLAY_RELEASE_ROOT: ${{ github.workspace }}/apps/android' "$release" \
  || fail 'recovery uploader is not bound to the exact release root'
grep -q 'wearIncluded:false' "$release" || fail 'release intent does not record phone-only scope'
grep -q 'workflowSha:$workflowSha' "$release" || fail 'release intent omits workflow-tooling provenance'
grep -q 'uploadToolSha256:$uploadToolSha256' "$release" || fail 'release intent omits uploader digest'
grep -q 'healthmd-android-phone-upload-${{ steps.version.outputs.version }}-${{ steps.version.outputs.release_sha }}-attempt-${{ github.run_attempt }}' "$release" \
  || fail 'phone upload intent is not SHA/attempt bound'
intent_line=$(grep -n 'Retain immutable phone upload intent receipt' "$release" | head -1 | cut -d: -f1)
credential_line=$(grep -n 'Authenticate to Google Play with protected Workload Identity' "$release" | head -1 | cut -d: -f1)
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
grep -q 'PLAY_ACCESS_TOKEN' "$uploader" || fail 'uploader cannot consume ephemeral Workload Identity access'
grep -q "refusing to create a Play edit without an exact-track reconciliation result" "$uploader" \
  || fail 'uploader does not fail closed when exact-track reconciliation is unavailable'
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

grep -q 'expected_tag="android/v$VERSION"' "$promotion" \
  || fail 'production dispatch is not bound to the exact release tag'
grep -q 'test "$(git cat-file -t "$expected_tag")" = tag' "$promotion" \
  || fail 'production dispatch does not require an annotated release tag'
grep -q '\[\[ "$GITHUB_REF_NAME" == android/recovery/\* \]\]' "$promotion" \
  || fail 'workflow-only production recovery lacks a constrained tag namespace'
grep -q 'test "$(git rev-parse HEAD)" = "$tagged_sha"' "$promotion" \
  || fail 'workflow-only recovery does not check out the exact release source'
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
grep -q 'workflowRecovery:$recovery' "$promotion" || fail 'production intent omits recovery provenance'
grep -q 'commit_response_received=true' "$promotion" \
  || fail 'production commit cannot distinguish a received response from reconciliation'
grep -q 'commit_exit_code -eq 22' "$promotion" \
  || fail 'production can relabel a definite HTTP rejection'
[[ $(grep -c ':commit?changesNotSentForReview=' "$promotion") -eq 1 ]] \
  || fail 'production workflow must contain exactly one Play commit'
if grep -Eq -- '--retry [0-9]+.*:commit|:commit.*--retry [0-9]+' "$promotion"; then
  fail 'production workflow retries the non-idempotent Play commit'
fi

grep -q 'environment: google-play' "$access_audit" || fail 'Play access audit is not protected'
grep -q 'google-github-actions/auth@7c6bc770dae815cd3e89ee6cdf493a5fab2cc093' "$access_audit" \
  || fail 'Play access audit does not use pinned Workload Identity'
grep -q 'noPlayEditCommit:true' "$access_audit" || fail 'Play access audit omits its no-commit receipt'
grep -q 'emptyEditInsertDeleteVerified:true' "$access_audit" \
  || fail 'Play access audit does not prove bounded empty-edit cleanup'
if grep -Eq ':commit|/bundles|listings/.+(-X PUT|--request PUT)' "$access_audit"; then
  fail 'Play access audit can publish application state'
fi

promotion_intent_line=$(grep -n 'Retain immutable phone promotion intent' "$promotion" | head -1 | cut -d: -f1)
promotion_credential_line=$(grep -n 'Authenticate to Google Play with protected Workload Identity' "$promotion" | head -1 | cut -d: -f1)
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
