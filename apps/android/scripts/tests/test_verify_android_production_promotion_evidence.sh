#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
root="$tmp/evidence"; mkdir "$root"
sha=1111111111111111111111111111111111111111
app=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
tile=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
printf '%s\n' '{"releases":[{"activeArtifacts":[{"versionCode":"29"}]}]}' >"$root/google-play-qa.json"
printf '%s\n' '{"releases":[{"activeArtifacts":[{"versionCode":"1000029"}]}]}' >"$root/google-play-wear-qa.json"
printf '%s\n' '{"releases":[]}' >"$root/google-play-production-before.json"
printf '%s\n' '{"releases":[]}' >"$root/google-play-wear-production-before.json"
printf '%s\n' '{"releases":[{"versionCodes":["29"]}]}' >"$root/google-play-qa-edit.json"
printf '%s\n' '{"releases":[{"versionCodes":["1000029"]}]}' >"$root/google-play-wear-qa-edit.json"
printf '%s\n' '{"track":"production","releases":[{"versionCodes":["29"],"status":"completed"}]}' >"$root/google-play-production-payload.json"
printf '%s\n' '{"track":"wear:production","releases":[{"versionCodes":["1000029"],"status":"completed"}]}' >"$root/google-play-wear-production-payload.json"
phone_release='{"releases":[{"activeArtifacts":[{"versionCode":"29"}],"releaseLifecycleState":"RELEASE_LIFECYCLE_STATE_IN_REVIEW"}]}'
wear_release='{"releases":[{"activeArtifacts":[{"versionCode":"1000029"}],"releaseLifecycleState":"RELEASE_LIFECYCLE_STATE_IN_REVIEW"}]}'
for name in google-play-production-after.json google-play-production-review.json; do printf '%s\n' "$phone_release" >"$root/$name"; done
for name in google-play-wear-production-after.json google-play-wear-production-review.json; do printf '%s\n' "$wear_release" >"$root/$name"; done
printf '{"images":[{"sha256":"%s"},{"sha256":"%s"}]}\n' "$tile" "$app" >"$root/google-play-wear-screenshots-before.json"
jq -n --arg sha "$sha" --arg app "$app" --arg tile "$tile" '{
  schemaVersion:1, repository:"owner/repo", workflow:".github/workflows/android-promote-production.yml",
  runId:123, runAttempt:1, releaseSha:$sha, versionName:"1.8.0",
  phoneVersionCode:29, wearVersionCode:1000029,
  sourceTracks:["qa","wear:internal"], destinationTracks:["production","wear:production"],
  promotionEditId:"edit-1", commitResponseReceived:true,
  pairedEditCommitted:true, productionPairVerified:true,
  reviewLifecycleVerified:true, wearAppScreenshotSha256:$app, wearTileScreenshotSha256:$tile,
  completedAtUtc:"2026-08-14T12:00:00Z"
}' >"$root/receipt.json"
seal() {
  (cd "$root" && find . -maxdepth 1 -type f ! -name SHA256SUMS -print | sed 's#^./##' | LC_ALL=C sort \
    | while IFS= read -r file; do sha256sum "$file"; done >SHA256SUMS)
}
verify() {
  EXPECTED_RELEASE_SHA="$sha" EXPECTED_VERSION_NAME=1.8.0 \
  EXPECTED_PHONE_VERSION_CODE=29 EXPECTED_WEAR_VERSION_CODE=1000029 \
  EXPECTED_WEAR_APP_SCREENSHOT_SHA256="$app" EXPECTED_WEAR_TILE_SCREENSHOT_SHA256="$tile" \
    ./scripts/verify-android-production-promotion-evidence.sh "$root" >/dev/null
}
seal
verify
cp -R "$root" "$tmp/good"
printf '%s\n' '{"releases":[{"activeArtifacts":[{"versionCode":"29"}]}]}' >"$root/google-play-production-before.json"
seal
if verify 2>/dev/null; then echo 'accepted phone code already on production before edit' >&2; exit 1; fi
rm -rf "$root"; cp -R "$tmp/good" "$root"
printf '%s\n' '{"images":[{"sha256":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"},{"sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}]}' >"$root/google-play-wear-screenshots-before.json"
seal
if verify 2>/dev/null; then echo 'accepted mismatched pre-promotion screenshot set' >&2; exit 1; fi
printf '%s\n' 'Android production promotion evidence tests passed'
