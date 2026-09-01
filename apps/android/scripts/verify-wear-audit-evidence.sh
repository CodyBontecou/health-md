#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
fail() { echo "Wear audit evidence: $*" >&2; exit 1; }

# These are evidence-link checks, not substitutes for the underlying tests/manual gates. Derive the
# release identity from source so this validator cannot silently bless yesterday's version.
phone_version=$(sed -n 's/.*versionName = "\([^"]*\)".*/\1/p' app/build.gradle.kts | head -1)
wear_version=$(sed -n 's/.*versionName = "\([^"]*\)".*/\1/p' wear/build.gradle.kts | head -1)
phone_code=$(sed -n 's/.*versionCode = \([0-9][0-9]*\).*/\1/p' app/build.gradle.kts | head -1)
wear_code=$(sed -n 's/.*versionCode = \([0-9_][0-9_]*\).*/\1/p' wear/build.gradle.kts | head -1 | tr -d '_')
[[ "$phone_version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ &&
   "$wear_version" == "$phone_version" && "$phone_code" =~ ^[1-9][0-9]*$ &&
   "$wear_code" =~ ^[1-9][0-9]*$ && "$phone_code" -lt 1000000 && "$wear_code" -ge 1000000 ]] \
  || fail 'unable to derive a valid paired release identity from Gradle' 
[[ $(grep -c 'ComplicationService" android:exported' wear/src/main/AndroidManifest.xml) -eq 10 ]] || fail 'complication count drift'
[[ $(grep -c 'TileService" android:exported' wear/src/main/AndroidManifest.xml) -eq 2 ]] || fail 'Tile count drift'
[[ -f docs/features/wear-os-completion-audit.md ]] || fail 'completion audit missing'

# Every explicit blocked row must remain represented in the blocker preflight. This prevents a
# documentation-only completion claim from silently dropping an external gate.
audit=docs/features/wear-os-completion-audit.md
blockers=scripts/report-wear-release-blockers.sh
for evidence in \
  'wear-app.png' \
  'wear-tile.png' \
  'Pixel/Samsung battery evidence is missing, invalid, unbound, too short, or exceeds threshold' \
  'Pixel/Samsung paired/OEM evidence is missing, inconsistent, unbound, or fails state validation' \
  'verified remote x86_64 Wear CI receipt missing or invalid' \
  'required protected GitHub Wear release environments' \
  'Play exact qa/wear:qa pair' \
  'Play production exact paired promotion remains unproven' \
  'Play-generated APK signer identity receipt missing or invalid' \
  'Wear screenshot release-binding evidence missing or invalid' \
  'authorized release signing environment unavailable' \
  'lacks clean exact annotated-tag/main ancestry and independently bound review evidence'; do
  grep -q "$evidence" "$blockers" || fail "blocker preflight missing: $evidence"
done
grep -q 'retained protected paired-QA evidence, not current ADB presence, is the completion gate' "$blockers" \
  || fail 'current ADB presence is still treated as completion evidence'
grep -q 'signer-bound retained base-master APK evidence remains the completion gate' "$blockers" \
  || fail 'generated inventory counts are still treated as completion evidence'
grep -q 'qaUploadRunId' scripts/verify-wear-release-evidence-bundle.sh \
  || fail 'release evidence is not bound to exact-SHA QA upload provenance'
grep -q 'screenshotUploadRunAttempt' scripts/verify-wear-release-evidence-bundle.sh \
  || fail 'release evidence is not bound to protected screenshot workflow provenance'
grep -q 'android-wear-screenshots.yml' ../../.github/workflows/android-wear-evidence.yml \
  || fail 'protected ingest does not re-query exact screenshot publication provenance'
grep -q 'verify-wear-play-screenshot-upload-evidence.py' scripts/verify-wear-release-evidence-bundle.sh \
  || fail 'release evidence omits committed Play screenshot transaction receipt'
grep -q 'verify-github-source-review-evidence.py' scripts/verify-wear-release-evidence-bundle.sh \
  || fail 'release evidence omits authenticated GitHub source-review proof'
grep -q 'source-review' scripts/extract-wear-release-evidence-archive.py \
  || fail 'submitted archives may inject the protected source-review namespace'
for audit_phrase in \
  'battery testing' \
  'OEM physical behavior' \
  'Wear emulator CI' \
  'Play assets' \
  'protected GitHub release environments' \
  'production upload signer' \
  'Play App Signing identity' \
  'Wear form factor' \
  'closed-track install/upgrade/delete' \
  'exact paired promotion' \
  'release source state'; do
  grep -q "$audit_phrase" "$audit" || fail "audit row missing: $audit_phrase"
done

# Stale substitute-artifact hashes in the audit are dangerous: update proof whenever exact release
# outputs change. Outputs may be absent on a clean checkout; when present, they must match the audit.
local_emulator_receipt=$(git rev-parse --show-toplevel)/.pi/evidence/wear-emulator/receipt.json
if [[ -f "$local_emulator_receipt" ]]; then
  debug_apk=wear/build/outputs/apk/debug/wear-debug.apk
  [[ -f "$debug_apk" ]] || fail 'retained emulator receipt exists without its exact debug APK'
  debug_sha=$(shasum -a 256 "$debug_apk" | awk '{print $1}')
  jq -e --arg sha "$debug_sha" --argjson wearCode "$wear_code" '
    .schemaVersion == 1 and .result == "pass" and .api == 34 and .wearVersionCode == $wearCode and
    .apkSha256 == $sha and .rotaryEncoderDiscovered == true and
    .exactTiles == 2 and .exactComplications == 10 and .crashAnrFree == true
  ' "$local_emulator_receipt" >/dev/null || fail 'retained local emulator receipt is stale or malformed'
  grep -q "$debug_sha" "$audit" || fail 'exact retained local emulator APK hash is absent from audit'
fi

for spec in \
  'phone:app/build/outputs/bundle/playRelease/app-play-release.aab' \
  'Wear:wear/build/outputs/bundle/release/wear-release.aab'; do
  label=${spec%%:*}; artifact=${spec#*:}
  if [[ -f "$artifact" ]]; then
    digest=$(shasum -a 256 "$artifact" | awk '{print $1}')
    grep -q "$digest" "$audit" || fail "$label current release AAB hash is absent from audit: $digest"
  fi
done

# A final positive decision is forbidden while the audit contains any explicit blockers.
if grep -Eq '^\|.*\| \*\*(BLOCKED|UNVERIFIED)' "$audit"; then
  grep -q '^\*\*NOT COMPLETE\.\*\*' "$audit" || fail 'blocked rows exist without NOT COMPLETE decision'
else
  fail 'audit has no blocked/unverified rows; perform a fresh manual completion audit before changing this guard'
fi

echo 'Wear prompt-to-artifact audit evidence links valid; completion remains blocked'
