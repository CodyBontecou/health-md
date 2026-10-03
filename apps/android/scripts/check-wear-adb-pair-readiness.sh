#!/usr/bin/env bash
set -euo pipefail

# Availability check only. Physical OEM identity, installed Play artifacts, pairing, and behavior are
# verified by the protected paired-QA evidence gate; this helper merely refuses to call two generic
# ADB rows a phone/watch pair.
adb_bin=${ADB:-${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb}
[[ -x "$adb_bin" ]] || { echo "adb not found: $adb_bin" >&2; exit 69; }

phone_serials=()
watch_serials=()
ready_serials=$($adb_bin devices 2>/dev/null | awk 'NR > 1 && $2 == "device" { print $1 }')
while IFS= read -r serial; do
  [[ -n "$serial" ]] || continue
  characteristics=$($adb_bin -s "$serial" shell getprop ro.build.characteristics 2>/dev/null | tr -d '\r' || true)
  features=$($adb_bin -s "$serial" shell pm list features 2>/dev/null | tr -d '\r' || true)
  if [[ ",$characteristics," == *,watch,* ]] || grep -q '^feature:android\.hardware\.type\.watch$' <<<"$features"; then
    watch_serials+=("$serial")
  else
    phone_serials+=("$serial")
  fi
done <<<"$ready_serials"

if (( ${#phone_serials[@]} < 1 || ${#watch_serials[@]} < 1 )); then
  printf 'ADB phone/watch availability missing: phone_candidates=%d watch_candidates=%d\n' \
    "${#phone_serials[@]}" "${#watch_serials[@]}" >&2
  exit 1
fi

printf 'ADB phone/watch candidates available (availability only): phones=%d watches=%d\n' \
  "${#phone_serials[@]}" "${#watch_serials[@]}"
