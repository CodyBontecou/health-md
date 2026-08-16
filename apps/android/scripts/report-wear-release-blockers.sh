#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

failures=0
pass() { printf 'PASS  %s\n' "$1"; }
info() { printf 'INFO  %s\n' "$1"; }
block() { printf 'BLOCK %s\n' "$1"; failures=$((failures + 1)); }

phone_gradle=app/build.gradle.kts
wear_gradle=wear/build.gradle.kts
version_name=$(sed -n 's/^[[:space:]]*versionName = "\([^"]*\)".*/\1/p' "$phone_gradle" | head -1)
phone_version_code=$(sed -n 's/^[[:space:]]*versionCode = \([0-9][0-9]*\).*/\1/p' "$phone_gradle" | head -1)
wear_version_code=$(sed -n 's/^[[:space:]]*versionCode = \([0-9][0-9_]*\).*/\1/p' "$wear_gradle" | head -1 | tr -d '_')
[[ "$version_name" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ && "$phone_version_code" =~ ^[1-9][0-9]*$ && "$wear_version_code" =~ ^[1-9][0-9]*$ ]] \
  || { echo 'Unable to derive exact release identity from Gradle' >&2; exit 65; }

[[ "$(git branch --show-current 2>/dev/null)" == feature/android-wear-os-widgets ]] \
  && pass 'isolated Wear worktree branch' || block 'not on feature/android-wear-os-widgets'
[[ ! -e local.properties ]] && pass 'no persistent local signing configuration' || block 'local.properties exists'

if [[ -f wear/build/outputs/bundle/release/wear-release.aab && -f app/build/outputs/bundle/release/app-release.aab ]]; then
  if ./scripts/validate-wear-artifact.sh wear/build/outputs/bundle/release/wear-release.aab app/build/outputs/bundle/release/app-release.aab >/dev/null; then
    pass 'phone and Wear release AAB outputs pass packaged identity/manifest validation'
  else
    block 'phone/Wear release AAB packaged validation failed'
  fi
else
  block 'phone/Wear release AAB pair missing'
fi
if [[ -f wear/build/outputs/apk/release/wear-release.apk ]]; then
  badging=$(${ANDROID_HOME:-$HOME/Library/Android/sdk}/build-tools/35.0.0/aapt dump badging wear/build/outputs/apk/release/wear-release.apk 2>/dev/null | head -1 || true)
  [[ "$badging" == *"versionCode='$wear_version_code'"* && "$badging" == *"versionName='$version_name'"* ]] \
    && pass "current Wear release APK is $version_name/$wear_version_code" || block 'Wear release APK is stale or unreadable'
else
  block 'Wear release APK missing'
fi

screenshots_present=true
for screenshot in wear-app.png wear-tile.png; do
  if [[ -f "play-store/wear/screenshots/$screenshot" ]]; then pass "$screenshot exists"; else block "$screenshot missing"; screenshots_present=false; fi
done
if $screenshots_present; then
  python3 ./scripts/validate-wear-play-assets.py >/dev/null \
    && pass 'Wear screenshots pass structural asset validation' \
    || block 'Wear screenshot structural validation failed'
fi

evidence_root=$(git rev-parse --show-toplevel)/.pi/evidence
battery_root=${WEAR_BATTERY_EVIDENCE_ROOT:-$evidence_root/wear-battery}
paired_root=${WEAR_PAIRED_EVIDENCE_ROOT:-$evidence_root/wear-paired}
ci_receipt=${WEAR_REMOTE_CI_RECEIPT:-$evidence_root/wear-ci/verified-run.json}
expected_battery_reviewer=${EXPECTED_BATTERY_REVIEWER:-${EXPECTED_WEAR_BATTERY_REVIEWER:-}}
expected_battery_ticket=${EXPECTED_BATTERY_REVIEW_TICKET:-${EXPECTED_WEAR_BATTERY_REVIEW_TICKET:-}}
expected_battery_profile=${EXPECTED_BATTERY_CONTROL_PROFILE:-${EXPECTED_WEAR_BATTERY_CONTROL_PROFILE:-}}
expected_paired_reviewer=${EXPECTED_PAIRED_REVIEWER:-}
expected_paired_ticket=${EXPECTED_PAIRED_REVIEW_TICKET:-}
expected_screenshot_reviewer=${EXPECTED_SCREENSHOT_REVIEWER:-}
expected_screenshot_ticket=${EXPECTED_SCREENSHOT_REVIEW_TICKET:-}
# Physical evidence is validated below after the retained Play-generated base-master APK hashes and
# independently supplied signer identity are known. This prevents same-version substitute binaries
# from satisfying battery or paired QA.
current_head=$(git rev-parse HEAD)
repo_slug=$(git config --get remote.origin.url 2>/dev/null | sed -E 's#^git@github.com:##; s#^https://github.com/##; s#\.git$##')
if [[ -f "$ci_receipt" ]] && [[ -n "$repo_slug" ]] && jq -e --arg head "$current_head" --arg repo "$repo_slug" '
    .conclusion == "success" and
    .event == "push" and
    .headSha == $head and
    .repository == $repo and
    (.runUrl | type == "string" and startswith("https://github.com/" + $repo + "/actions/runs/")) and
    (.workflow == "Android CI") and (.workflowPath == ".github/workflows/android-ci.yml") and
    (.runAttempt | type == "number" and . > 0) and
    (.wearJob.name == "Wear emulator smoke" and .wearJob.conclusion == "success") and
    (.gateJob.name == "Android CI" and .gateJob.conclusion == "success")
  ' "$ci_receipt" >/dev/null 2>&1; then
  pass 'verified remote Android CI receipt present'
else
  block 'verified remote x86_64 Wear CI receipt missing or invalid'
fi

if readiness=$(./scripts/check-wear-adb-pair-readiness.sh 2>&1); then
  info "$readiness; physical identity and behavior still require protected paired-QA evidence"
else
  info "$readiness; retained protected paired-QA evidence, not current ADB presence, is the completion gate"
fi

if github_environment_readiness=$(./scripts/check-github-wear-release-environments.sh 2>&1); then
  pass "$github_environment_readiness"
else
  while IFS= read -r detail; do
    [[ -z "$detail" ]] || info "GitHub environment proof: ${detail#BLOCK }"
  done <<<"$github_environment_readiness"
  block 'required protected GitHub Wear release environments are missing, unreviewed, policy-unrestricted, or incompletely configured'
fi

if [[ -n ${PLAY_CONSOLE_KEY_PATH:-} && -r ${PLAY_CONSOLE_KEY_PATH:-} ]]; then
  report=$(mktemp)
  EXPECTED_PHONE_VERSION_CODE="$phone_version_code" EXPECTED_WEAR_VERSION_CODE="$wear_version_code" \
    ./scripts/inspect-google-play-wear-readiness.sh "$report" >/dev/null
  if jq -e '.observed.expectedPairAlreadyInternal' "$report" >/dev/null; then
    pass 'Play exact qa/wear:qa pair is currently observable'
  else
    block 'Play exact qa/wear:qa pair is absent'
  fi
  if jq -e '.observed.expectedWearGeneratedSigningKeys > 0 and .observed.expectedWearGeneratedDownloads > 0' "$report" >/dev/null; then
    info 'Play generated inventory is available; signer-bound retained base-master APK evidence remains the completion gate'
  else
    info 'Play generated inventory is not yet available; signer-bound retained base-master APK evidence remains blocked below'
  fi
  if jq -e '.observed.expectedPairAlreadyProduction' "$report" >/dev/null; then
    promotion_root=${WEAR_PRODUCTION_PROMOTION_EVIDENCE_ROOT:-$evidence_root/google-play/production-promotion}
    if $screenshots_present && (
        export EXPECTED_RELEASE_SHA="$current_head" EXPECTED_VERSION_NAME="$version_name"
        export EXPECTED_PHONE_VERSION_CODE="$phone_version_code" EXPECTED_WEAR_VERSION_CODE="$wear_version_code"
        export EXPECTED_WEAR_APP_SCREENSHOT_SHA256="$(shasum -a 256 play-store/wear/screenshots/wear-app.png | awk '{print $1}')"
        export EXPECTED_WEAR_TILE_SCREENSHOT_SHA256="$(shasum -a 256 play-store/wear/screenshots/wear-tile.png | awk '{print $1}')"
        ./scripts/verify-android-production-promotion-evidence.sh "$promotion_root" >/dev/null 2>&1 \
          || ./scripts/verify-android-production-promotion-recovery-evidence.sh "$promotion_root" >/dev/null 2>&1
      ); then
      pass 'Play production exact pair has a verified original or recovery-only one-edit promotion receipt'
    else
      block 'Play production exact paired promotion remains unproven'
    fi
  else
    block 'Play production exact paired promotion remains unproven'
  fi
else
  block 'PLAY_CONSOLE_KEY_PATH unavailable for current read-only Play proof'
  block 'Play exact qa/wear:qa pair observation unavailable'
  block 'Play production exact paired promotion remains unproven'
fi

if [[ -n ${RELEASE_STORE_FILE:-} && -f ${RELEASE_STORE_FILE:-} && -n ${RELEASE_STORE_PASSWORD:-} && -n ${RELEASE_KEY_ALIAS:-} && -n ${RELEASE_KEY_PASSWORD:-} ]]; then
  if WEAR_REQUIRE_SIGNING_ATTESTATION=true \
      ./scripts/validate-wear-artifact.sh \
        wear/build/outputs/bundle/release/wear-release.aab \
        app/build/outputs/bundle/release/app-release.aab >/dev/null; then
    pass 'both exact AABs match the configured authorized upload signer'
  else
    block 'release signing environment does not attest both exact AABs'
  fi
else
  block 'authorized release signing environment unavailable'
fi

signer_receipt=${WEAR_PLAY_SIGNER_RECEIPT:-$evidence_root/wear-play/play-app-signing.json}
expected_play_signer=${EXPECTED_PLAY_APP_SIGNING_CERT_SHA256:-}
if EXPECTED_PHONE_VERSION_CODE="$phone_version_code" EXPECTED_WEAR_VERSION_CODE="$wear_version_code" \
    EXPECTED_VERSION_NAME="$version_name" EXPECTED_PLAY_APP_SIGNING_CERT_SHA256="$expected_play_signer" \
    ./scripts/verify-google-play-generated-apk-evidence.sh "$signer_receipt" >/dev/null 2>&1; then
  pass 'Play-generated phone/Wear APK signer receipt matches authorized identity'
  phone_apk_sha=$(jq -r .phone.apkSha256 "$signer_receipt")
  wear_apk_sha=$(jq -r .wear.apkSha256 "$signer_receipt")
  if python3 ./scripts/verify-wear-battery-evidence.py "$battery_root" \
      --wear-apk-sha256 "$wear_apk_sha" --play-signer-sha256 "$expected_play_signer" \
      --wear-version-code "$wear_version_code" --version-name "$version_name" \
      --expected-reviewer "$expected_battery_reviewer" --expected-review-ticket "$expected_battery_ticket" \
      --expected-control-profile "$expected_battery_profile" >/dev/null 2>&1; then
    pass 'Pixel/Samsung battery controls match exact Play Wear APK and satisfy duration/integrity/threshold'
  else
    block 'Pixel/Samsung battery evidence is missing, invalid, unbound, too short, or exceeds threshold'
  fi
  if python3 ./scripts/verify-wear-paired-qa-evidence.py "$paired_root" \
      --phone-apk-sha256 "$phone_apk_sha" --wear-apk-sha256 "$wear_apk_sha" \
      --play-signer-sha256 "$expected_play_signer" \
      --phone-version-code "$phone_version_code" --wear-version-code "$wear_version_code" \
      --version-name "$version_name" --expected-reviewer "$expected_paired_reviewer" \
      --expected-review-ticket "$expected_paired_ticket" >/dev/null 2>&1; then
    pass 'Pixel/Samsung paired/OEM evidence matches exact Play-generated phone/Wear APKs'
  else
    block 'Pixel/Samsung paired/OEM evidence is missing, inconsistent, unbound, or fails state validation'
  fi
  if $screenshots_present; then
    wear_apk_sha=$(jq -r .wear.apkSha256 "$signer_receipt")
    play_signer_sha=$(jq -r .expectedPlayAppSigningCertSha256 "$signer_receipt")
    screenshot_evidence=${WEAR_SCREENSHOT_EVIDENCE_ROOT:-$evidence_root/wear-play-screenshots}
    python3 ./scripts/verify-wear-play-screenshot-evidence.py \
      --evidence "$screenshot_evidence" \
      --wear-apk-sha256 "$wear_apk_sha" \
      --play-signer-sha256 "$play_signer_sha" \
      --wear-version-code "$wear_version_code" --version-name "$version_name" \
      --expected-reviewer "$expected_screenshot_reviewer" \
      --expected-review-ticket "$expected_screenshot_ticket" >/dev/null 2>&1 \
      && pass 'Wear screenshots match exact installed Play-signed capture receipts' \
      || block 'Wear screenshot release-binding evidence missing or invalid'
  fi
else
  block 'Play-generated APK signer identity receipt missing or invalid'
  block 'Pixel/Samsung battery evidence cannot be accepted without exact Play-generated APK binding'
  block 'Pixel/Samsung paired/OEM evidence cannot be accepted without exact Play-generated APK binding'
  $screenshots_present && block 'Wear screenshot release-binding evidence missing or invalid'
fi

[[ -z ${report:-} ]] || rm -f "$report"

source_review=${WEAR_SOURCE_REVIEW_RECEIPT:-$evidence_root/wear-source-review/review.json}
expected_source_reviewer=${EXPECTED_SOURCE_REVIEWER:-}
expected_source_ticket=${EXPECTED_SOURCE_REVIEW_TICKET:-}
release_tag="android/v$version_name"
source_ready=true
git diff --quiet && git diff --cached --quiet && [[ -z $(git ls-files --others --exclude-standard) ]] \
  || source_ready=false
git show-ref --verify --quiet "refs/tags/$release_tag" || source_ready=false
if $source_ready; then
  [[ "$(git cat-file -t "$release_tag" 2>/dev/null || true)" == tag ]] || source_ready=false
  [[ "$(git rev-parse "$release_tag^{commit}" 2>/dev/null || true)" == "$current_head" ]] || source_ready=false
fi
# Re-query authoritative remote refs rather than trusting a stale/locally forged origin/main or tag.
remote_main=$(git ls-remote --exit-code origin refs/heads/main 2>/dev/null | awk '$2 == "refs/heads/main" { print $1; exit }' || true)
remote_tags=$(git ls-remote --tags origin "refs/tags/$release_tag" "refs/tags/$release_tag^{}" 2>/dev/null || true)
remote_tag_object=$(printf '%s\n' "$remote_tags" | awk -v ref="refs/tags/$release_tag" '$2 == ref { print $1; exit }')
remote_tag_peeled=$(printf '%s\n' "$remote_tags" | awk -v ref="refs/tags/$release_tag^{}" '$2 == ref { print $1; exit }')
local_origin_main=$(git rev-parse --verify refs/remotes/origin/main 2>/dev/null || true)
local_tag_object=$(git rev-parse "$release_tag" 2>/dev/null || true)
[[ -n "$remote_main" && "$remote_main" == "$local_origin_main" ]] || source_ready=false
[[ -n "$remote_tag_object" && "$remote_tag_object" == "$local_tag_object" ]] || source_ready=false
[[ "$remote_tag_peeled" == "$current_head" ]] || source_ready=false
$source_ready && git merge-base --is-ancestor "$current_head" "$remote_main" 2>/dev/null \
  || source_ready=false
[[ -n "$expected_source_reviewer" && -n "$expected_source_ticket" && -f "$source_review" ]] \
  || source_ready=false
if $source_ready; then
  jq -e --arg sha "$current_head" --arg version "$version_name" \
    --arg reviewer "$expected_source_reviewer" --arg ticket "$expected_source_ticket" '
    .schemaVersion == 1 and .releaseSha == $sha and .versionName == $version and
    .approved == true and .reviewer == $reviewer and .reviewTicket == $ticket and
    (.reviewedAtUtc | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")) and
    ((.reviewedAtUtc | fromdateiso8601?) != null)
  ' "$source_review" >/dev/null 2>&1 || source_ready=false
fi
if $source_ready; then
  pass 'clean reviewed source is the exact annotated release tag on origin/main ancestry'
else
  block 'Wear source lacks clean exact annotated-tag/main ancestry and independently bound review evidence'
fi

printf '\n%d blocker(s) remain. This report is diagnostic and never marks the goal complete.\n' "$failures"
(( failures == 0 ))
