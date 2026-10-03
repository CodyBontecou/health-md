#!/usr/bin/env bash
# Shared, side-effect-free Google Play track policy used by upload/promotion implementations and
# fixture tests. This file intentionally performs no HTTP requests or edit commits.

play_policy_fail() { printf 'Google Play paired policy: %s\n' "$*" >&2; return 1; }

play_assert_distinct_tracks() {
  local phone_track=$1 wear_track=$2
  [[ "$phone_track" != wear:* && "$wear_track" == wear:* && "$phone_track" != "$wear_track" ]] \
    || play_policy_fail 'phone and Wear must use distinct default/form-factor tracks'
}

play_release_payload() {
  local code=$1 status=$2
  [[ "$code" =~ ^[0-9]+$ ]] || play_policy_fail "invalid versionCode $code" || return
  case "$status" in completed|draft) ;; *) play_policy_fail "unsupported release status: $status"; return ;; esac
  jq -nc --arg code "$code" --arg status "$status" \
    '{releases:[{versionCodes:[$code],status:$status}]}'
}

play_validate_track_response() {
  local response_file=$1 code=$2 status=$3
  jq -e --arg code "$code" --arg status "$status" '
    (.releases | length == 1) and
    .releases[0].status == $status and
    .releases[0].versionCodes == [$code]
  ' "$response_file" >/dev/null || play_policy_fail "track response does not contain only $code/$status"
}

play_select_release() {
  local source_file=$1 code=$2
  jq -ce --arg code "$code" '
    first(.releases[]? | select(any(.versionCodes[]?; tostring == $code)))
  ' "$source_file"
}

play_promotion_payload() {
  local source_file=$1 destination=$2 code=$3 output=$4 release
  [[ "$destination" =~ ^(wear:)?production$ ]] \
    || play_policy_fail "invalid production destination $destination" || return
  if [[ "$destination" == wear:* ]]; then
    [[ "$code" -ge 1000000 ]] || play_policy_fail 'Wear versionCode outside reserved range' || return
  else
    [[ "$code" -lt 1000000 ]] || play_policy_fail 'phone versionCode outside reserved range' || return
  fi
  release=$(play_select_release "$source_file" "$code") \
    || play_policy_fail "source release $code is missing" || return
  printf '%s' "$release" | jq -ce --arg code "$code" --arg track "$destination" '
    .versionCodes = [$code]
    | .status = "completed"
    | del(.userFraction, .countryTargeting, .inAppUpdatePriority)
    | {track: $track, releases: [.]}
  ' >"$output"
  jq -e --arg code "$code" --arg track "$destination" '
    .track == $track and (.releases | length == 1) and
    .releases[0].status == "completed" and .releases[0].versionCodes == [$code]
  ' "$output" >/dev/null || play_policy_fail 'promotion payload postcondition failed'
}
