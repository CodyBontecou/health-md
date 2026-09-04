#!/usr/bin/env bash
set -euo pipefail

# Read-only preflight for the paired phone/Wear Play release. This never creates an edit.
usage() {
  echo "Usage: PLAY_CONSOLE_KEY_PATH=... $0 [OUTPUT_JSON]" >&2
  exit 64
}
key=${PLAY_CONSOLE_KEY_PATH:-}
[[ -n "$key" && -r "$key" ]] || usage
out=${1:-}
package=com.healthmd.android
phone_expected=${EXPECTED_PHONE_VERSION_CODE:-}
wear_expected=${EXPECTED_WEAR_VERSION_CODE:-}
[[ "$phone_expected" =~ ^[1-9][0-9]*$ && "$wear_expected" =~ ^[1-9][0-9]*$ ]] || {
  echo 'EXPECTED_PHONE_VERSION_CODE and EXPECTED_WEAR_VERSION_CODE are required positive integers' >&2
  exit 64
}
(( phone_expected < 1000000 && wear_expected >= 1000000 )) || {
  echo 'expected phone/Wear codes are outside their reserved ranges' >&2
  exit 64
}
private_key=$(mktemp)
trap 'rm -f "$private_key"' EXIT
jq -er .private_key "$key" >"$private_key"
base64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
now=$(date +%s)
header=$(printf '%s' '{"alg":"RS256","typ":"JWT"}' | base64url)
claims=$(jq -nc --arg iss "$(jq -er .client_email "$key")" --arg aud "$(jq -er .token_uri "$key")" --argjson iat "$now" '{iss:$iss,scope:"https://www.googleapis.com/auth/androidpublisher",aud:$aud,iat:$iat,exp:($iat+1200)}' | base64url)
unsigned="$header.$claims"
signature=$(printf '%s' "$unsigned" | openssl dgst -sha256 -sign "$private_key" | base64url)
token=$(curl --fail-with-body --retry 3 --retry-all-errors --max-time 30 -sS -X POST "$(jq -er .token_uri "$key")" \
  --data-urlencode 'grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer' \
  --data-urlencode "assertion=$unsigned.$signature" | jq -er .access_token)

work=$(mktemp -d); trap 'rm -f "$private_key"; rm -rf "$work"' EXIT
for track in qa beta production wear:qa2 wear:beta wear:production; do
  curl --fail-with-body --retry 3 --retry-all-errors --max-time 30 -sS \
    -H "Authorization: Bearer $token" \
    "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/$package/tracks/$track/releases" \
    >"$work/${track//:/-}.json"
done
# Generated APK inventory is a read-only post-upload proof surface: an expected Wear-range version
# must have Play-generated variants before form-factor/install claims are allowed. A missing version
# before its first upload is represented as unavailable rather than turning the preflight into a
# mutation or a false failure.
for code in "$phone_expected" "$wear_expected"; do
  http=$(curl --retry 3 --retry-all-errors --max-time 30 -sS \
    -H "Authorization: Bearer $token" \
    -o "$work/generated-$code.json" -w '%{http_code}' \
    "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/$package/generatedApks/$code")
  if [[ "$http" != 200 && "$http" != 404 ]]; then
    echo "Generated APK query for $code failed with HTTP $http" >&2
    cat "$work/generated-$code.json" >&2
    exit 1
  fi
  [[ "$http" == 200 ]] || printf '{"generatedApks":[]}' >"$work/generated-$code.json"
done

jq -n \
  --arg package "$package" \
  --arg captured "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson phone "$phone_expected" --argjson wear "$wear_expected" \
  --slurpfile qa "$work/qa.json" --slurpfile beta "$work/beta.json" --slurpfile production "$work/production.json" \
  --slurpfile wearQa "$work/wear-qa.json" --slurpfile wearBeta "$work/wear-beta.json" --slurpfile wearProduction "$work/wear-production.json" \
  --slurpfile phoneGenerated "$work/generated-$phone_expected.json" --slurpfile wearGenerated "$work/generated-$wear_expected.json" '
  def codes($track): [$track[0].releases[]?.activeArtifacts[]?.versionCode | tonumber];
  def releases($track): [$track[0].releases[]? | {
    name: .releaseName,
    lifecycle: .releaseLifecycleState,
    versionCodes: [.activeArtifacts[]?.versionCode | tonumber]
  }];
  (codes($qa)) as $qaCodes |
  (codes($beta)) as $betaCodes |
  (codes($production)) as $productionCodes |
  (codes($wearQa)) as $wearQaCodes |
  (codes($wearBeta)) as $wearBetaCodes |
  (codes($wearProduction)) as $wearProductionCodes |
  {
    capturedAtUtc: $captured,
    package: $package,
    expected: {phoneVersionCode: $phone, wearVersionCode: $wear},
    tracks: {
      qa: releases($qa),
      beta: releases($beta),
      production: releases($production),
      wearQa: releases($wearQa),
      wearBeta: releases($wearBeta),
      wearProduction: releases($wearProduction)
    },
    observed: {
      maxPhoneVersionCode: ([$qaCodes[], $betaCodes[], $productionCodes[]] | max // 0),
      maxWearVersionCode: ([$wearQaCodes[], $wearBetaCodes[], $wearProductionCodes[]] | max // 0),
      expectedPairAlreadyInternal:
        (any($qa[0].releases[]?; any(.activeArtifacts[]?; (.versionCode | tonumber) == $phone)) and
         any($wearQa[0].releases[]?; any(.activeArtifacts[]?; (.versionCode | tonumber) == $wear))),
      expectedPairAlreadyProduction:
        (any($production[0].releases[]?; any(.activeArtifacts[]?; (.versionCode | tonumber) == $phone)) and
         any($wearProduction[0].releases[]?; any(.activeArtifacts[]?; (.versionCode | tonumber) == $wear))),
      anyWearArtifact: any([$wearQaCodes[], $wearBetaCodes[], $wearProductionCodes[]][]; . >= 1000000),
      expectedPhoneGeneratedSigningKeys: ($phoneGenerated[0].generatedApks // [] | length),
      expectedWearGeneratedSigningKeys: ($wearGenerated[0].generatedApks // [] | length),
      expectedWearGeneratedSplitApks: ([$wearGenerated[0].generatedApks[]?.generatedSplitApks[]?] | length),
      expectedWearGeneratedStandaloneApks: ([$wearGenerated[0].generatedApks[]?.generatedStandaloneApks[]?] | length),
      expectedWearGeneratedUniversalApks: ([$wearGenerated[0].generatedApks[]?.generatedUniversalApk | select(. != null)] | length),
      expectedWearGeneratedDownloads: ([
        $wearGenerated[0].generatedApks[]? |
        (.generatedSplitApks[]?, .generatedStandaloneApks[]?, .generatedUniversalApk?) |
        select(.downloadId? != null)
      ] | length),
      expectedWearCertificateSha256Hashes: ([
        $wearGenerated[0].generatedApks[]?.certificateSha256Hash? | ascii_downcase
      ] | unique)
    }
  }
' >"$work/report.json"

if [[ -n "$out" ]]; then
  mkdir -p "$(dirname "$out")"
  cp "$work/report.json" "$out"
fi
cat "$work/report.json"
