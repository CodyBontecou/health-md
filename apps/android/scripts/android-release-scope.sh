#!/usr/bin/env bash
# Side-effect-free source release scope. Only a validated deferred declaration permits phone and
# Wear development versions to advance independently; artifact publication retains paired checks.

android_release_wear_mode() {
  local scope=$1 phone_version=$2 phone_code=$3
  [[ "$phone_version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ &&
     "$phone_code" =~ ^[1-9][0-9]*$ && "$phone_code" -lt 1000000 ]] || return 1
  jq -er --arg version "$phone_version" --argjson code "$phone_code" '
    select(
      .schemaVersion == 1 and .releaseVersionName == $version and
      .googlePlay.phone.module == ":app" and
      .googlePlay.phone.status == "release_candidate" and
      .googlePlay.phone.versionCode == $code and
      .googlePlay.phone.testingTrack == "internal" and
      .googlePlay.phone.productionTrack == "production" and
      .googlePlay.wear.module == ":wear" and
      (
        (
          .googlePlay.wear.status == "deferred" and
          .googlePlay.wear.published == false and
          .googlePlay.wear.runtimeAdvertisedByPhone == false and
          (.googlePlay.wear.targetVersionName | type == "string" and
            test("^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$")) and
          (.googlePlay.wear.reason | type == "string" and test("[^[:space:]]"))
        ) or (
          .googlePlay.wear.status == "release_candidate" and
          (.googlePlay.wear.published | type) == "boolean" and
          .googlePlay.wear.runtimeAdvertisedByPhone == true
        )
      )
    ) | if .googlePlay.wear.status == "deferred" then "deferred" else "paired" end
  ' "$scope"
}
