#!/usr/bin/env bash
set -euo pipefail

fail() { echo "promotion policy test: $*" >&2; exit 1; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# shellcheck source=google-play-paired-policy.sh
source "$(dirname "$0")/google-play-paired-policy.sh"

phone=29
wear=1000029
play_assert_distinct_tracks qa wear:internal || fail 'valid form-factor tracks rejected'
if play_assert_distinct_tracks qa production >/dev/null 2>&1; then fail 'non-Wear destination accepted'; fi
if play_assert_distinct_tracks wear:internal wear:production >/dev/null 2>&1; then fail 'Wear phone source accepted'; fi

play_release_payload "$phone" completed >"$tmp/release.json"
jq -e --arg code "$phone" '.releases == [{versionCodes:[$code],status:"completed"}]' \
  "$tmp/release.json" >/dev/null || fail 'upload release payload'
if play_release_payload "$phone" halted >/dev/null 2>&1; then fail 'invalid release status accepted'; fi

cat >"$tmp/response.json" <<'JSON'
{"track":"optional-echo","releases":[{"status":"completed","versionCodes":["29"]}]}
JSON
play_validate_track_response "$tmp/response.json" "$phone" completed || fail 'semantic response rejected'
for bad in \
  '{"releases":[{"status":"completed","versionCodes":["29","30"]}]}' \
  '{"releases":[{"status":"draft","versionCodes":["29"]}]}' \
  '{"releases":[]}'; do
  printf '%s' "$bad" >"$tmp/bad.json"
  if play_validate_track_response "$tmp/bad.json" "$phone" completed >/dev/null 2>&1; then
    fail "invalid track response accepted: $bad"
  fi
done

cat >"$tmp/qa.json" <<'JSON'
{"track":"qa","releases":[{"name":"old","status":"completed","versionCodes":["28"]},{"name":"phone","status":"completed","versionCodes":["29"],"userFraction":0.5,"countryTargeting":{"countries":["US"]}}]}
JSON
cat >"$tmp/wear-qa.json" <<'JSON'
{"track":"wear:internal","releases":[{"name":"wear","status":"completed","versionCodes":["1000029"],"inAppUpdatePriority":5}]}
JSON
play_promotion_payload "$tmp/qa.json" production "$phone" "$tmp/phone-payload.json"
play_promotion_payload "$tmp/wear-qa.json" wear:production "$wear" "$tmp/wear-payload.json"
jq -e --arg code "$phone" '
  .track == "production" and .releases[0].versionCodes == [$code] and
  .releases[0].status == "completed" and
  (.releases[0] | has("userFraction") or has("countryTargeting") | not)
' "$tmp/phone-payload.json" >/dev/null || fail 'phone promotion payload'
jq -e --arg code "$wear" '
  .track == "wear:production" and .releases[0].versionCodes == [$code] and
  (.releases[0] | has("inAppUpdatePriority") | not)
' "$tmp/wear-payload.json" >/dev/null || fail 'Wear promotion payload'

if play_promotion_payload "$tmp/qa.json" production 30 "$tmp/missing.json" >/dev/null 2>&1; then
  fail 'missing source version accepted'
fi
if play_promotion_payload "$tmp/qa.json" wear:production "$phone" "$tmp/wrong-range.json" >/dev/null 2>&1; then
  fail 'phone code accepted on Wear production'
fi
if play_promotion_payload "$tmp/wear-qa.json" production "$wear" "$tmp/wrong-range.json" >/dev/null 2>&1; then
  fail 'Wear code accepted on phone production'
fi
if play_promotion_payload "$tmp/qa.json" beta "$phone" "$tmp/wrong-track.json" >/dev/null 2>&1; then
  fail 'non-production destination accepted'
fi

# Regression guard: production workflow and paired uploader must invoke these exact tested helpers;
# the policy test is not allowed to drift into a duplicate jq implementation.
repo=$(cd "$(dirname "$0")/../../.." && pwd)
promotion_workflow="$repo/.github/workflows/android-promote-production.yml"
grep -q 'play_promotion_payload' "$promotion_workflow" \
  || fail 'promotion workflow bypasses tested helper'
grep -q 'source scripts/google-play-paired-policy.sh' "$promotion_workflow" \
  || fail 'promotion workflow sources policy from wrong working-directory path'
grep -q 'verify-wear-release-evidence-bundle.sh' "$promotion_workflow" \
  || fail 'production promotion bypasses mandatory phase-6/7 evidence bundle'
grep -q 'evidence_run_id' "$promotion_workflow" \
  || fail 'production promotion is not bound to a durable evidence workflow run'
grep -q '^  actions: read$' "$promotion_workflow" \
  || fail 'production promotion lacks cross-run artifact read permission'
grep -q 'path == ".github/workflows/android-wear-evidence.yml"' "$promotion_workflow" \
  || fail 'operator-supplied evidence run is not rebound to the protected ingest workflow'
grep -q 'head_sha == \$sha' "$promotion_workflow" \
  || fail 'evidence ingest run is not rebound to the immutable release SHA'
if grep -q '\.inputs\.release_sha' "$promotion_workflow"; then
  fail 'promotion trusts workflow dispatch inputs absent from the Actions run REST response'
fi
grep -q 'wear-release-evidence-${{ inputs.version }}-${{ steps.release.outputs.sha }}-attempt-${{ steps.evidence-run.outputs.attempt }}' "$promotion_workflow" \
  || fail 'verified artifact name is not SHA/version/run-attempt bound'
grep -q 'environment: google-play-production' "$promotion_workflow" \
  || fail 'production mutation does not use the dedicated protected environment'
grep -q 'refusing to bypass the required one-edit paired promotion' "$promotion_workflow" \
  || fail 'already-production state can bypass exact paired edit evidence'
if grep -q "if: steps.preflight.outputs.already_production != 'true'" "$promotion_workflow"; then
  fail 'promotion still has an already-production skip path'
fi
grep -q 'The exact paired promotion edit did not complete successfully' "$promotion_workflow" \
  || fail 'postcondition can pass without this run committing the paired edit'
grep -q 'commit_response_received=true' "$promotion_workflow" \
  || fail 'production commit does not distinguish a received response from reconciled success'
grep -q 'paired_commit_visible' "$promotion_workflow" \
  || fail 'ambiguous production commit response is not reconciled against both tracks'
grep -q 'commit_exit_code -eq 22' "$promotion_workflow" \
  || fail 'definite production commit HTTP rejection can be relabeled as success'
if grep -Eq -- '--retry [0-9]+.*:commit|:commit.*--retry [0-9]+' "$promotion_workflow"; then
  fail 'non-idempotent production commit POST is configured for retry'
fi
grep -q 'changesNotSentForReview=false&changesInReviewBehavior=ERROR_IF_IN_REVIEW' "$promotion_workflow" \
  || fail 'paired production edit does not atomically submit both tracks for review'
[[ $(grep -c ':commit?changesNotSentForReview=' "$promotion_workflow") -eq 1 ]] \
  || fail 'production workflow contains more than one Play commit'
if grep -q 'Send production changes for review' "$promotion_workflow"; then
  fail 'production review submission regressed to a second fallible edit'
fi
grep -q 'google-play-wear-screenshots-before.json' "$promotion_workflow" \
  || fail 'production gate does not independently query committed Wear screenshots'
grep -q 'Committed Play Wear screenshots differ from the exact sealed approved PNGs' "$promotion_workflow" \
  || fail 'production gate does not compare Play screenshot hashes to sealed assets'
grep -q 'android-production-promotion-${{ inputs.version }}-${{ steps.release.outputs.sha }}-attempt-${{ github.run_attempt }}' "$promotion_workflow" \
  || fail 'exact paired production edit receipt is not retained under an attempt-specific name'
grep -q 'android-production-promotion-intent-${{ inputs.version }}-${{ steps.release.outputs.sha }}-attempt-${{ github.run_attempt }}' "$promotion_workflow" \
  || fail 'production intent is not retained under an attempt-specific name'
grep -q 'evidenceRunAttempt:$evidenceRunAttempt' "$promotion_workflow" \
  || fail 'production intent omits the exact evidence-ingest attempt used before mutation'
grep -q 'verify-android-production-promotion-evidence.sh' "$promotion_workflow" \
  || fail 'retained exact paired edit receipt is not independently validated before upload'
promotion_intent_line=$(grep -n 'Retain immutable production-promotion intent' "$promotion_workflow" | head -1 | cut -d: -f1)
promotion_credential_line=$(grep -n 'Configure ephemeral Google Play credentials' "$promotion_workflow" | head -1 | cut -d: -f1)
promotion_edit_line=$(grep -n 'Promote exact paired internal release to production' "$promotion_workflow" | head -1 | cut -d: -f1)
(( promotion_intent_line < promotion_credential_line && promotion_credential_line < promotion_edit_line )) \
  || fail 'production promotion intent is not durable before credential and mutation'
recovery_workflow="$repo/.github/workflows/android-promote-production-recover.yml"
grep -q 'verify-android-production-promotion-recovery-evidence.sh' "$recovery_workflow" \
  || fail 'failed post-commit receipt retention lacks protected recovery verifier'
grep -q 'Promote exact paired internal release to production.*conclusion == "success"' "$recovery_workflow" \
  || fail 'recovery does not prove the original paired edit step succeeded'
grep -q 'original_promotion_run_attempt' "$recovery_workflow" \
  || fail 'recovery does not require the exact original mutation attempt'
grep -q 'attempts/$ORIGINAL_RUN_ATTEMPT' "$recovery_workflow" \
  || fail 'recovery run provenance is not queried from the explicit original attempt'
grep -q 'attempts/${original_attempt}/jobs' "$recovery_workflow" \
  || fail 'recovery does not rebind step provenance to the intent attempt'
grep -q 'run_attempt=$(jq -er .evidenceRunAttempt "$intent")' "$recovery_workflow" \
  || fail 'recovery can substitute a later evidence-ingest attempt for the one used by promotion'
grep -q '.repository.full_name == $repo and .head_sha == $sha' "$recovery_workflow" \
  || fail 'recovery does not bind the original promotion run to the exact release SHA'
grep -q 'android-production-promotion-intent-${{ inputs.version }}-${{ steps.release.outputs.sha }}-attempt-${{ inputs.original_promotion_run_attempt }}' "$recovery_workflow" \
  || fail 'recovery intent download is attempt-ambiguous'
grep -q 'recovery-attempt-${{ github.run_attempt }}' "$recovery_workflow" \
  || fail 'recovery receipt artifact is not bound to its own attempt'
grep -Fq "'.github/workflows/android-*.yml'" "$repo/.github/workflows/android-ci.yml" \
  || fail 'Android workflow changes do not trigger main-push Android CI'
if grep -Eq -- '-X PUT|:commit' "$recovery_workflow"; then
  fail 'recovery-only workflow can mutate Play tracks or commit an edit'
fi
release_workflow="$repo/.github/workflows/android-release.yml"
grep -q 'environment: google-play-qa' "$release_workflow" \
  || fail 'QA upload does not use a production-separated Play environment'
grep -q 'git rev-parse "$GITHUB_REF_NAME^{commit}"' "$release_workflow" \
  || fail 'QA upload is not bound to the peeled annotated tag commit'
grep -q 'healthmd-android-qa-upload-${{ steps.version.outputs.version }}-${{ github.sha }}-attempt-${{ github.run_attempt }}' "$release_workflow" \
  || fail 'QA upload does not retain a SHA/run-attempt-bound intent receipt'
grep -q 'healthmd-android-${{ steps.version.outputs.version }}-attempt-${{ github.run_attempt }}' "$release_workflow" \
  || fail 'QA AAB pair is not retained under an attempt-specific artifact name'
qa_intent_line=$(grep -n 'Retain immutable QA upload intent receipt' "$release_workflow" | head -1 | cut -d: -f1)
qa_credential_line=$(grep -n 'Configure ephemeral Google Play credential' "$release_workflow" | head -1 | cut -d: -f1)
qa_upload_line=$(grep -n 'Upload phone/Wear bundles to their form-factor tracks' "$release_workflow" | head -1 | cut -d: -f1)
(( qa_intent_line < qa_credential_line && qa_credential_line < qa_upload_line )) \
  || fail 'QA intent/AAB evidence is not durable before Play credential and mutation'
grep -q 'uploadPrepared:true' "$release_workflow" \
  || fail 'QA pre-mutation receipt does not distinguish intent from completion'
submit_workflow="$repo/.github/workflows/android-wear-evidence-submit.yml"
screenshot_workflow="$repo/.github/workflows/android-wear-screenshots.yml"
ingest_workflow="$repo/.github/workflows/android-wear-evidence.yml"
grep -q 'evidence_archive_sha256' "$submit_workflow" \
  || fail 'large evidence submission is not digest bound'
grep -q 'secrets.WEAR_RELEASE_EVIDENCE_URL' "$submit_workflow" \
  || fail 'one-time evidence URL is exposed as a non-secret workflow input'
if grep -q 'WEAR_RELEASE_EVIDENCE_TAR_GZ_BASE64' "$ingest_workflow"; then
  fail 'infeasible base64 secret evidence transport returned'
fi
grep -q 'submission.json' "$ingest_workflow" \
  || fail 'ingest does not rebind downloaded artifact bytes to protected submission metadata'
grep -q 'submission_run_attempt' "$ingest_workflow" \
  || fail 'protected ingest does not require an explicit exact submission attempt'
grep -q 'submissionRunAttempt' "$ingest_workflow" \
  || fail 'submission artifact provenance is not bound to an exact run attempt'
grep -q 'environment: google-play-qa' "$screenshot_workflow" \
  || fail 'screenshot mutation is not in the reviewer-protected QA environment'
grep -q 'test "$GITHUB_REF_NAME" = "$tag"' "$screenshot_workflow" \
  || fail 'screenshot mutation is not restricted to the exact annotated release tag'
grep -q 'submission_run_attempt' "$screenshot_workflow" \
  || fail 'screenshot mutation input is not bound to an exact submission attempt'
grep -q './scripts/sync-google-play-wear-screenshots.sh' "$screenshot_workflow" \
  || fail 'protected screenshot workflow bypasses the verified mutation implementation'
grep -q 'wear-screenshot-upload-${{ inputs.version }}-${{ steps.release.outputs.sha }}-attempt-${{ github.run_attempt }}' "$screenshot_workflow" \
  || fail 'screenshot mutation receipt is not SHA/run-attempt bound'
grep -q 'screenshot_upload_run_id' "$ingest_workflow" \
  || fail 'protected ingest does not require the successful screenshot workflow run'
grep -q 'path == ".github/workflows/android-wear-screenshots.yml"' "$ingest_workflow" \
  || fail 'protected ingest does not re-query screenshot workflow provenance'
grep -q 'screenshotUploadRunAttempt:$screenshotAttempt' "$ingest_workflow" \
  || fail 'protected ingest does not retain the exact screenshot workflow attempt'
grep -q 'screenshotSubmissionRunAttempt:$screenshotSubmissionAttempt' "$ingest_workflow" \
  || fail 'protected ingest does not retain the screenshot workflow source-submission attempt'
grep -q 'remoteCiRunAttempt' "$ingest_workflow" \
  || fail 'remote CI provenance is not bound to an exact run attempt'
grep -q 'ingestRunAttempt' "$ingest_workflow" \
  || fail 'protected evidence artifact is not bound to its ingest attempt'
grep -q 'extract-wear-release-evidence-archive.py' "$ingest_workflow" \
  || fail 'ingest bypasses bounded safe archive extraction'
grep -q 'pull-requests: read' "$ingest_workflow" \
  || fail 'protected ingest cannot authenticate the GitHub source review'
grep -q 'source_pull_request_number' "$ingest_workflow" \
  || fail 'protected ingest does not bind an exact source-review pull request'
grep -q 'source_review_id' "$ingest_workflow" \
  || fail 'protected ingest does not bind an exact source-review review ID'
grep -q 'source-review/proof.json' "$ingest_workflow" \
  || fail 'protected ingest does not retain authenticated source-review proof'
grep -q 'verify-github-source-review-evidence.py' "$ingest_workflow" \
  || fail 'protected ingest bypasses authenticated source-review verification'
grep -q 'sourcePullRequestNumber' "$ingest_workflow" \
  || fail 'protected ingest provenance omits the authenticated source-review binding'
grep -q 'remote push CI' "$ingest_workflow" \
  || fail 'protected ingest does not re-query remote push CI provenance'
grep -q 'path == ".github/workflows/android-ci.yml"' "$ingest_workflow" \
  || fail 'protected ingest does not bind CI run to Android CI workflow'
grep -q 'seal-wear-release-evidence.sh' "$ingest_workflow" \
  || fail 'protected ingest does not construct the retained evidence seal'
grep -q 'qa_upload_run_id' "$ingest_workflow" \
  || fail 'protected ingest is not bound to the successful exact-SHA QA upload run'
grep -q 'qaPhoneAabSha256' "$ingest_workflow" \
  || fail 'protected ingest does not retain exact uploaded phone/Wear AAB digests'
grep -q 'Requery and retain exact QA track postconditions' "$ingest_workflow" \
  || fail 'protected ingest does not independently retain the exact QA track pair'
bundle_verifier="$(dirname "$0")/verify-wear-release-evidence-bundle.sh"
attestation_validator="$(dirname "$0")/validate-wear-release-attestation.py"
grep -q 'screenshotUploadRunAttempt' "$bundle_verifier" \
  || fail 'sealed bundle verifier omits protected screenshot workflow provenance'
grep -q 'google-play-wear-qa-current.json' "$bundle_verifier" \
  || fail 'sealed evidence verifier does not require the protected QA track observation'
grep -q 'validate-wear-release-attestation.py' "$bundle_verifier" \
  || fail 'release bundle bypasses the exact protected attestation schema validator'
grep -q 'verify-github-source-review-evidence.py' "$bundle_verifier" \
  || fail 'release bundle accepts an unauthenticated source-review assertion'
for source_binding in pullRequestNumber reviewId; do
  grep -q "$source_binding" "$attestation_validator" \
    || fail "attestation source review is not bound to its GitHub identity: $source_binding"
done
for source_flag in --source-pull-request-number --source-review-id; do
  grep -q -- "$source_flag" "$bundle_verifier" \
    || fail "sealed bundle verifier omits the required source-review CLI binding: $source_flag"
done
for approval in \
  closedTrackPhoneFirstInstallApproved closedTrackWatchFirstInstallApproved \
  closedTrackUpgradeFromProductionApproved closedTrackVersionSkewApproved \
  closedTrackDeleteUninstallReinstallApproved; do
  grep -q "$approval" "$attestation_validator" \
    || fail "closed-track attestation schema omits explicit scenario: $approval"
done
grep -q 'verify-wear-play-screenshot-upload-evidence.py' "$bundle_verifier" \
  || fail 'release bundle does not require committed screenshot upload evidence'
grep -q 'qaUploadRunId' "$bundle_verifier" \
  || fail 'release bundle does not verify protected exact-SHA QA upload provenance'
for binding in \
  WEAR_BATTERY_REVIEWER WEAR_BATTERY_REVIEW_TICKET WEAR_BATTERY_CONTROL_PROFILE \
  WEAR_PAIRED_REVIEWER WEAR_PAIRED_REVIEW_TICKET \
  WEAR_SCREENSHOT_REVIEWER WEAR_SCREENSHOT_REVIEW_TICKET \
  WEAR_SOURCE_REVIEWER WEAR_SOURCE_REVIEW_TICKET; do
  grep -q "vars.$binding" "$ingest_workflow" \
    || fail "protected ingest does not bind manual approval input: $binding"
  grep -q "vars.$binding" "$promotion_workflow" \
    || fail "production re-verification does not bind manual approval input: $binding"
done
uploader="$(dirname "$0")/upload-google-play-paired-release.sh"
screenshot_sync="$(dirname "$0")/sync-google-play-wear-screenshots.sh"
grep -q 'play_validate_track_response' "$uploader" \
  || fail 'paired uploader bypasses tested helper'
grep -q 'paired_commit_visible' "$uploader" \
  || fail 'ambiguous QA commit response is not reconciled against both tracks'
grep -q 'commit_exit_code -eq 22' "$uploader" \
  || fail 'definite QA commit HTTP rejection can be relabeled as success'
grep -q 'PHONE_VERSION_CODE and WEAR_VERSION_CODE are required' "$uploader" \
  || fail 'paired uploader retains an implicit release identity'
if grep -q 'listings/.*/wearScreenshots' "$uploader"; then
  fail 'initial paired upload must not circularly replace exact-release screenshots'
fi
grep -q 'verify-wear-play-screenshot-evidence.py' "$screenshot_sync" \
  || fail 'post-upload screenshot transaction bypasses exact-release evidence verifier'
grep -q 'EXPECTED_PHONE_VERSION_CODE="$phone_version_code" EXPECTED_WEAR_VERSION_CODE="$wear_version_code"' "$screenshot_sync" \
  || fail 'screenshot transaction does not propagate exact future codes to Play-generated APK verification'
grep -q -- '--version-name "$version_name"' "$screenshot_sync" \
  || fail 'screenshot transaction does not bind exact future version name'
grep -q 'expected_confirmation=.*expected_wear_apk.*expected_play_signer' "$screenshot_sync" \
  || fail 'screenshot replacement confirmation is not artifact/signer bound'
grep -q 'expected_wear_apk.*play_wear_apk' "$screenshot_sync" \
  || fail 'screenshot replacement APK is not cross-bound to retained Play-generated evidence'
grep -q 'EXPECTED_SCREENSHOT_REVIEWER' "$screenshot_sync" \
  || fail 'screenshot mutation is not bound to the protected visual reviewer'
grep -q 'verify-wear-play-screenshot-upload-evidence.py' "$screenshot_sync" \
  || fail 'committed screenshot metadata edit does not retain a verified receipt'
grep -q 'commit_response_received=true' "$screenshot_sync" \
  || fail 'screenshot commit does not classify ambiguous response loss'
grep -q 'precommit_already_matched' "$screenshot_sync" \
  || fail 'screenshot reconciliation is not bound to differing pre-commit state'
grep -q 'commit_exit_code -eq 22' "$screenshot_sync" \
  || fail 'definite screenshot commit HTTP rejection can be relabeled as success'
grep -q 'pre-commit-listing.json' "$screenshot_sync" \
  || fail 'screenshot receipt omits raw pre-commit listing state'
grep -q 'committed_listing' "$screenshot_sync" \
  || fail 'screenshot commit is not reconciled through a fresh committed-state edit'
precondition_list_line=$(grep -n 'listings/$language/$image_type' "$screenshot_sync" | sed -n '1s/:.*//p')
delete_line=$(grep -n 'listings/$language/$image_type' "$screenshot_sync" | sed -n '2s/:.*//p')
upload_line=$(grep -n 'Content-Type: image/png' "$screenshot_sync" | head -1 | cut -d: -f1)
staged_list_line=$(grep -n 'listings/$language/$image_type' "$screenshot_sync" | sed -n '4s/:.*//p')
staged_count_line=$(grep -n 'Play edit has an unexpected Wear screenshot count' "$screenshot_sync" | cut -d: -f1)
commit_line=$(grep -n 'changesInReviewBehavior=ERROR_IF_IN_REVIEW' "$screenshot_sync" | cut -d: -f1)
reconcile_list_line=$(grep -n 'listings/$language/$image_type' "$screenshot_sync" | tail -1 | cut -d: -f1)
reconcile_count_line=$(grep -n 'committed Play state has an unexpected Wear screenshot count' "$screenshot_sync" | cut -d: -f1)
for line in "$precondition_list_line" "$delete_line" "$upload_line" "$staged_list_line" "$staged_count_line" \
  "$commit_line" "$reconcile_list_line" "$reconcile_count_line"; do
  [[ "$line" =~ ^[0-9]+$ ]] || fail 'screenshot transaction lost delete/upload/list/count/commit/reconciliation stage'
done
(( precondition_list_line < delete_line && delete_line < upload_line && upload_line < staged_list_line && \
   staged_list_line < staged_count_line && staged_count_line < commit_line && \
   commit_line < reconcile_list_line && reconcile_list_line < reconcile_count_line )) \
  || fail 'screenshot transaction stages are no longer atomically ordered'
grep -q 'Play digest mismatch' "$screenshot_sync" || fail 'uploaded screenshot digest is not checked'
grep -q 'Play edit does not list' "$screenshot_sync" || fail 'remote screenshot set digests are not checked'
[[ $(grep -c 'play-store/wear/screenshots/wear-' "$screenshot_sync") -eq 2 ]] \
  || fail 'post-upload transaction does not name exactly two canonical screenshots'

printf '%s\n' 'Android paired promotion policy tests passed'
