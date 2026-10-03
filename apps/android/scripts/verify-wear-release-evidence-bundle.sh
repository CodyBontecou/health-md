#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: EXPECTED_RELEASE_SHA=<40-hex> EXPECTED_VERSION_NAME=<semver> \
       EXPECTED_PHONE_VERSION_CODE=<integer> EXPECTED_WEAR_VERSION_CODE=<integer> \
       EXPECTED_ATTESTOR=<identity> EXPECTED_PLAY_APP_SIGNING_CERT_SHA256=<64-hex> \
       EXPECTED_BATTERY_REVIEWER=<identity> EXPECTED_BATTERY_REVIEW_TICKET=<record> \
       EXPECTED_BATTERY_CONTROL_PROFILE=<id> EXPECTED_PAIRED_REVIEWER=<identity> \
       EXPECTED_PAIRED_REVIEW_TICKET=<record> EXPECTED_SCREENSHOT_REVIEWER=<identity> \
       EXPECTED_SCREENSHOT_REVIEW_TICKET=<record> EXPECTED_SOURCE_REVIEWER=<identity> \
       EXPECTED_SOURCE_REVIEW_TICKET=<record> \
       verify-wear-release-evidence-bundle.sh EVIDENCE_ROOT [phase]
  phase: pre-promotion (default) | post-production

The evidence root is a durable artifact downloaded by the protected promotion workflow. It must
contain the exact retained Play APK evidence, screenshots/receipts, Pixel+Samsung paired/battery
evidence, remote-CI receipt, and independent manual attestations.
EOF
  exit 64
}
[[ $# -ge 1 && $# -le 2 ]] || usage
root=$1; phase=${2:-pre-promotion}
case "$phase" in pre-promotion|post-production) ;; *) usage ;; esac
expected_sha=${EXPECTED_RELEASE_SHA:-}
expected_version=${EXPECTED_VERSION_NAME:-}
expected_phone_code=${EXPECTED_PHONE_VERSION_CODE:-}
expected_wear_code=${EXPECTED_WEAR_VERSION_CODE:-}
expected_attestor=${EXPECTED_ATTESTOR:-}
expected_signer=${EXPECTED_PLAY_APP_SIGNING_CERT_SHA256:-}
expected_battery_reviewer=${EXPECTED_BATTERY_REVIEWER:-}
expected_battery_ticket=${EXPECTED_BATTERY_REVIEW_TICKET:-}
expected_battery_profile=${EXPECTED_BATTERY_CONTROL_PROFILE:-}
expected_paired_reviewer=${EXPECTED_PAIRED_REVIEWER:-}
expected_paired_ticket=${EXPECTED_PAIRED_REVIEW_TICKET:-}
expected_screenshot_reviewer=${EXPECTED_SCREENSHOT_REVIEWER:-}
expected_screenshot_ticket=${EXPECTED_SCREENSHOT_REVIEW_TICKET:-}
expected_source_reviewer=${EXPECTED_SOURCE_REVIEWER:-}
expected_source_ticket=${EXPECTED_SOURCE_REVIEW_TICKET:-}
hmac_key=${WEAR_EVIDENCE_HMAC_KEY:-}
[[ "$expected_sha" =~ ^[0-9a-f]{40}$ ]] || { echo 'EXPECTED_RELEASE_SHA must be lowercase 40-hex' >&2; exit 64; }
[[ "$expected_version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || { echo 'EXPECTED_VERSION_NAME must be semantic version' >&2; exit 64; }
[[ "$expected_phone_code" =~ ^[1-9][0-9]*$ && "$expected_wear_code" =~ ^[1-9][0-9]*$ ]] || { echo 'expected version codes are required' >&2; exit 64; }
[[ -n "$expected_attestor" ]] || { echo 'EXPECTED_ATTESTOR is required' >&2; exit 64; }
[[ "$expected_signer" =~ ^[0-9a-f]{64}$ ]] || { echo 'EXPECTED_PLAY_APP_SIGNING_CERT_SHA256 must be lowercase 64-hex' >&2; exit 64; }
for binding in \
  expected_battery_reviewer expected_battery_ticket expected_battery_profile \
  expected_paired_reviewer expected_paired_ticket \
  expected_screenshot_reviewer expected_screenshot_ticket \
  expected_source_reviewer expected_source_ticket; do
  [[ -n "${!binding}" ]] || { echo "Protected evidence binding is required: $binding" >&2; exit 64; }
done
[[ "$expected_battery_reviewer" != "$expected_attestor" && "$expected_paired_reviewer" != "$expected_attestor" && "$expected_screenshot_reviewer" != "$expected_attestor" && "$expected_source_reviewer" != "$expected_attestor" ]] \
  || { echo 'Manual reviewers must be independent from the release attestor' >&2; exit 64; }
[[ -n "$hmac_key" ]] || { echo 'WEAR_EVIDENCE_HMAC_KEY is required' >&2; exit 64; }
[[ -d "$root" ]] || { echo "Evidence root missing: $root" >&2; exit 65; }

fail() { printf 'Wear release evidence bundle: %s\n' "$*" >&2; exit 1; }
manifest="$root/release-attestation.json"
[[ -f "$manifest" ]] || fail 'release-attestation.json missing'
source_pr=$(jq -er .sourceReview.pullRequestNumber "$manifest")
source_review_id=$(jq -er .sourceReview.reviewId "$manifest")
[[ "$source_pr" =~ ^[1-9][0-9]*$ && "$source_review_id" =~ ^[1-9][0-9]*$ ]] \
  || fail 'source review pull request/review ID is missing or invalid'
python3 ./scripts/validate-wear-release-attestation.py "$manifest" \
  --release-sha "$expected_sha" --version-name "$expected_version" \
  --phone-version-code "$expected_phone_code" --wear-version-code "$expected_wear_code" \
  --attestor "$expected_attestor" --play-signer "$expected_signer" \
  --battery-reviewer "$expected_battery_reviewer" --battery-ticket "$expected_battery_ticket" \
  --battery-profile "$expected_battery_profile" \
  --paired-reviewer "$expected_paired_reviewer" --paired-ticket "$expected_paired_ticket" \
  --screenshot-reviewer "$expected_screenshot_reviewer" --screenshot-ticket "$expected_screenshot_ticket" \
  --source-reviewer "$expected_source_reviewer" --source-ticket "$expected_source_ticket" \
  --source-pull-request-number "$source_pr" --source-review-id "$source_review_id" >/dev/null \
  || fail 'manual release attestation missing, mismatched, or incomplete'

# Checksum the complete durable bundle except the checksum file itself. This detects omission and
# post-attestation mutation after upload/download; protected-environment identity remains the trust
# boundary for the attestor and independently supplied signer.
sums="$root/SHA256SUMS"
signature="$root/SHA256SUMS.hmac-sha256"
[[ -f "$sums" && -f "$signature" ]] || fail 'bundle SHA256SUMS/signature missing'
expected_hmac=$(openssl dgst -sha256 -hmac "$hmac_key" "$sums" | awk '{print $NF}')
actual_hmac=$(tr -d '[:space:]' <"$signature")
[[ "$actual_hmac" =~ ^[0-9a-f]{64}$ && "$actual_hmac" == "$expected_hmac" ]] \
  || fail 'bundle HMAC signature mismatch'
(
  cd "$root"
  shasum -a 256 -c SHA256SUMS >/dev/null
) || fail 'bundle checksum mismatch'
listed=$(awk '{print $2}' "$sums" | sed 's/^\*//' | LC_ALL=C sort)
actual=$(cd "$root" && find . -type f ! -name SHA256SUMS ! -name SHA256SUMS.hmac-sha256 -print | sed 's#^\./##' | LC_ALL=C sort)
[[ "$listed" == "$actual" ]] || fail 'bundle checksum inventory does not exactly cover every retained file'

EXPECTED_PHONE_VERSION_CODE="$expected_phone_code" \
EXPECTED_WEAR_VERSION_CODE="$expected_wear_code" \
EXPECTED_VERSION_NAME="$expected_version" \
EXPECTED_PLAY_APP_SIGNING_CERT_SHA256="$expected_signer" \
  ./scripts/verify-google-play-generated-apk-evidence.sh "$root/wear-play/play-app-signing.json" >/dev/null
actual_signer=$(jq -er .expectedPlayAppSigningCertSha256 "$root/wear-play/play-app-signing.json")
[[ "$actual_signer" == "$expected_signer" ]] || fail 'retained Play evidence signer differs from independent protected value'
phone_sha=$(jq -er .phone.apkSha256 "$root/wear-play/play-app-signing.json")
wear_sha=$(jq -er .wear.apkSha256 "$root/wear-play/play-app-signing.json")
battery_reviewer=$(jq -er .manualQa.batteryReviewer "$manifest")
battery_ticket=$(jq -er .manualQa.batteryReviewTicket "$manifest")
battery_profile=$(jq -er .manualQa.batteryControlProfile "$manifest")
[[ "$battery_reviewer" == "$expected_battery_reviewer" && "$battery_ticket" == "$expected_battery_ticket" && "$battery_profile" == "$expected_battery_profile" ]] \
  || fail 'battery reviewer, ticket, or control profile differs from protected trust inputs'
python3 ./scripts/verify-wear-battery-evidence.py "$root/wear-battery" \
  --wear-apk-sha256 "$wear_sha" --play-signer-sha256 "$expected_signer" \
  --wear-version-code "$expected_wear_code" --version-name "$expected_version" \
  --expected-reviewer "$expected_battery_reviewer" --expected-control-profile "$expected_battery_profile" \
  --expected-review-ticket "$expected_battery_ticket" >/dev/null
paired_reviewer=$(jq -er .manualQa.pairedReviewer "$manifest")
paired_ticket=$(jq -er .manualQa.pairedReviewTicket "$manifest")
[[ "$paired_reviewer" == "$expected_paired_reviewer" && "$paired_ticket" == "$expected_paired_ticket" ]] \
  || fail 'paired QA reviewer or ticket differs from protected trust inputs'
python3 ./scripts/verify-wear-paired-qa-evidence.py "$root/wear-paired" \
  --phone-apk-sha256 "$phone_sha" --wear-apk-sha256 "$wear_sha" \
  --play-signer-sha256 "$expected_signer" --phone-version-code "$expected_phone_code" \
  --wear-version-code "$expected_wear_code" --version-name "$expected_version" \
  --expected-reviewer "$expected_paired_reviewer" --expected-review-ticket "$expected_paired_ticket" >/dev/null
python3 ./scripts/validate-wear-play-assets.py --root "$root/wear-screenshots" >/dev/null
screenshot_reviewer=$(jq -er .screenshots.reviewer "$manifest")
screenshot_ticket=$(jq -er .screenshots.reviewTicket "$manifest")
[[ "$screenshot_reviewer" == "$expected_screenshot_reviewer" && "$screenshot_ticket" == "$expected_screenshot_ticket" ]] \
  || fail 'screenshot reviewer or ticket differs from protected trust inputs'
python3 ./scripts/verify-wear-play-screenshot-evidence.py \
  --assets "$root/wear-screenshots" --evidence "$root/wear-play-screenshots" \
  --wear-apk-sha256 "$wear_sha" --play-signer-sha256 "$expected_signer" \
  --wear-version-code "$expected_wear_code" --version-name "$expected_version" \
  --expected-reviewer "$expected_screenshot_reviewer" --expected-review-ticket "$expected_screenshot_ticket" >/dev/null
source_reviewer=$(jq -er .sourceReview.reviewer "$manifest")
source_ticket=$(jq -er .sourceReview.reviewTicket "$manifest")
source_pr=$(jq -er .sourceReview.pullRequestNumber "$manifest")
source_review_id=$(jq -er .sourceReview.reviewId "$manifest")
[[ "$source_reviewer" == "$expected_source_reviewer" && "$source_ticket" == "$expected_source_ticket" ]] \
  || fail 'source reviewer or review ticket differs from protected trust inputs'
[[ "$source_pr" =~ ^[1-9][0-9]*$ && "$source_review_id" =~ ^[1-9][0-9]*$ ]] \
  || fail 'source review pull request/review ID is missing or invalid'
python3 ./scripts/verify-wear-play-screenshot-upload-evidence.py \
  "$root/wear-play-screenshot-upload" --assets "$root/wear-screenshots" \
  --wear-apk-sha256 "$wear_sha" --play-signer-sha256 "$expected_signer" \
  --version-name "$expected_version" --phone-version-code "$expected_phone_code" \
  --wear-version-code "$expected_wear_code" --expected-reviewer "$expected_screenshot_reviewer" \
  --expected-review-ticket "$expected_screenshot_ticket" >/dev/null

# The protected ingest downloads these AABs and this receipt directly from the successful exact-SHA
# QA release run. Submitted evidence is forbidden from supplying this directory.
qa_dir="$root/qa-upload"
qa_phone_aab="$qa_dir/phone-release.aab"
qa_wear_aab="$qa_dir/wear-release.aab"
qa_receipt="$qa_dir/receipt.json"
qa_run="$qa_dir/run.json"
qa_jobs="$qa_dir/jobs.json"
qa_phone_track="$qa_dir/google-play-qa-current.json"
qa_wear_track="$qa_dir/google-play-wear-qa-current.json"
for file in "$qa_phone_aab" "$qa_wear_aab" "$qa_receipt" "$qa_run" "$qa_jobs" "$qa_phone_track" "$qa_wear_track"; do
  [[ -f "$file" ]] || fail "protected QA upload evidence missing: $file"
done
unzip -tqq "$qa_phone_aab" >/dev/null || fail 'retained QA phone AAB is not a valid archive'
unzip -tqq "$qa_wear_aab" >/dev/null || fail 'retained QA Wear AAB is not a valid archive'
qa_phone_sha=$(shasum -a 256 "$qa_phone_aab" | awk '{print $1}')
qa_wear_sha=$(shasum -a 256 "$qa_wear_aab" | awk '{print $1}')
qa_upload_run=$(jq -er .runId "$qa_receipt")
qa_upload_attempt=$(jq -er .runAttempt "$qa_receipt")
[[ "$qa_upload_run" =~ ^[1-9][0-9]*$ && "$qa_upload_attempt" =~ ^[1-9][0-9]*$ ]] \
  || fail 'QA upload receipt run ID/attempt is invalid'
jq -e --arg sha "$expected_sha" --arg version "$expected_version" \
  --arg tag "android/v$expected_version" --arg phoneSha "$qa_phone_sha" --arg wearSha "$qa_wear_sha" \
  --argjson phone "$expected_phone_code" --argjson wear "$expected_wear_code" '
  .schemaVersion == 1 and .workflow == ".github/workflows/android-release.yml" and
  .event == "push" and .tag == $tag and .headSha == $sha and .tagPeeledSha == $sha and
  .versionName == $version and .phoneVersionCode == $phone and .wearVersionCode == $wear and
  .phoneTrack == "qa" and .wearTrack == "wear:internal" and .releaseStatus == "completed" and
  .phoneAabSha256 == $phoneSha and .wearAabSha256 == $wearSha and .uploadPrepared == true
' "$qa_receipt" >/dev/null || fail 'QA upload receipt is SHA/version/AAB mismatched'
jq -e --arg sha "$expected_sha" --argjson run "$qa_upload_run" --argjson attempt "$qa_upload_attempt" '
  .id == $run and .run_attempt == $attempt and
  .path == ".github/workflows/android-release.yml" and .event == "push" and
  .head_sha == $sha and .status == "completed" and .conclusion == "success"
' "$qa_run" >/dev/null || fail 'protected QA upload workflow provenance is invalid'
jq -e --argjson code "$expected_phone_code" '
  any(.releases[]?; any(.activeArtifacts[]?; (.versionCode | tonumber) == $code))
' "$qa_phone_track" >/dev/null || fail 'protected QA phone track postcondition is absent'
jq -e --argjson code "$expected_wear_code" '
  any(.releases[]?; any(.activeArtifacts[]?; (.versionCode | tonumber) == $code))
' "$qa_wear_track" >/dev/null || fail 'protected QA Wear track postcondition is absent'
jq -e --argjson attempt "$qa_upload_attempt" '
  any(.jobs[]?; .name == "Publish Android internal release" and
    (.run_attempt // $attempt) == $attempt and .conclusion == "success" and
    any(.steps[]?; .name == "Retain immutable QA upload intent receipt" and .conclusion == "success") and
    any(.steps[]?; .name == "Upload phone/Wear bundles to their form-factor tracks in one Play edit" and .conclusion == "success") and
    any(.steps[]?; .name == "Remove ephemeral credentials after QA upload" and .conclusion == "success"))
' "$qa_jobs" >/dev/null || fail 'QA upload intent, paired edit, or credential cleanup step did not succeed'

protected_ingest="$root/protected-ingest.json"
[[ -f "$protected_ingest" ]] || fail 'protected ingest provenance missing'
jq -e --arg sha "$expected_sha" --arg phoneAab "$qa_phone_sha" --arg wearAab "$qa_wear_sha" \
  --argjson qaRun "$qa_upload_run" --argjson qaAttempt "$qa_upload_attempt" \
  --argjson pr "$source_pr" --argjson review "$source_review_id" '
  .schemaVersion == 1 and .releaseSha == $sha and
  (.repository | type == "string" and length > 0) and
  (.submissionRunId | type == "number" and . > 0) and
  (.submissionRunAttempt | type == "number" and . > 0) and
  .qaUploadRunId == $qaRun and .qaUploadRunAttempt == $qaAttempt and
  (.screenshotUploadRunId | type == "number" and . > 0) and
  (.screenshotUploadRunAttempt | type == "number" and . > 0) and
  (.screenshotSubmissionRunId | type == "number" and . > 0) and
  (.screenshotSubmissionRunAttempt | type == "number" and . > 0) and
  .qaPhoneAabSha256 == $phoneAab and .qaWearAabSha256 == $wearAab and
  .qaPairRequeried == true and
  (.remoteCiRunId | type == "number" and . > 0) and
  (.remoteCiRunAttempt | type == "number" and . > 0) and
  (.ingestRunId | type == "number" and . > 0) and
  (.ingestRunAttempt | type == "number" and . > 0) and
  .sourcePullRequestNumber == $pr and .sourceReviewId == $review
' "$protected_ingest" >/dev/null || fail 'protected ingest provenance is malformed or SHA/AAB-mismatched'
[[ "$(jq -er .repository "$qa_receipt")" == "$(jq -er .repository "$protected_ingest")" ]] \
  || fail 'QA upload repository differs from protected ingest repository'

# The named independent source review must be authenticated against GitHub's own PR/review
# records downloaded by protected ingest; string assertions in the manifest alone are not proof.
for file in pull-request.json review.json proof.json; do
  [[ -f "$root/source-review/$file" ]] || fail "authenticated source-review evidence missing: $file"
done
python3 ./scripts/verify-github-source-review-evidence.py "$root/source-review" \
  --repository "$(jq -er .repository "$protected_ingest")" \
  --release-sha "$expected_sha" --version-name "$expected_version" \
  --expected-reviewer "$expected_source_reviewer" --expected-review-ticket "$expected_source_ticket" \
  --expected-pull-request "$source_pr" --expected-review-id "$source_review_id" >/dev/null \
  || fail 'GitHub source review is not an authenticated approval of the exact release SHA'
ci="$root/wear-ci/verified-run.json"
[[ -f "$ci" ]] || fail 'remote CI receipt missing'
jq -e --arg sha "$expected_sha" '
  .schemaVersion == 1 and .headSha == $sha and .event == "push" and
  (.runAttempt | type == "number" and . > 0) and
  .workflowPath == ".github/workflows/android-ci.yml" and
  .status == "completed" and .conclusion == "success" and
  .wearJob.name == "Wear emulator smoke" and .wearJob.conclusion == "success" and
  .gateJob.name == "Android CI" and .gateJob.conclusion == "success"
' "$ci" >/dev/null || fail 'remote CI receipt is not a successful push for exact release SHA'
[[ "$(jq -er .runId "$ci")" == "$(jq -er .remoteCiRunId "$protected_ingest")" &&
   "$(jq -er .runAttempt "$ci")" == "$(jq -er .remoteCiRunAttempt "$protected_ingest")" ]] \
  || fail 'protected CI re-verification run attempt differs from retained receipt'

if [[ "$phase" == post-production ]]; then
  play="$root/google-play/readiness.json"
  jq -e '.observed.expectedPairAlreadyProduction == true' "$play" >/dev/null \
    || fail 'post-production exact pair evidence absent'
fi
printf 'Wear release evidence bundle verified for %s (%s)\n' "$expected_sha" "$phase"
