#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 5 ]]; then
  echo "usage: $0 <owner/repository> <release-id> <expected-tag> <expected-sha> <destination>" >&2
  exit 64
fi

repository="$1"
release_id="$2"
expected_tag="$3"
expected_sha="$4"
destination="$5"

[[ "$repository" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]
[[ "$release_id" =~ ^[1-9][0-9]*$ ]]
[[ "$expected_tag" =~ ^healthmd-cli/v[0-9A-Za-z.+-]+$ ]]
[[ "$expected_sha" =~ ^[0-9a-f]{40}$ ]]
mkdir -p "$destination"
test -z "$(find "$destination" -mindepth 1 -maxdepth 1 -print -quit)"

release="$(gh api "repos/$repository/releases/$release_id")"
test "$(jq -r '.id' <<<"$release")" = "$release_id"
test "$(jq -r '.draft' <<<"$release")" = true
test "$(jq -r '.tag_name' <<<"$release")" = "$expected_tag"
test "$(jq -r '.target_commitish' <<<"$release")" = "$expected_sha"
asset_count="$(jq '.assets | length' <<<"$release")"
test "$asset_count" -gt 0

while IFS= read -r encoded; do
  asset="$(base64 --decode <<<"$encoded")"
  asset_id="$(jq -r '.id' <<<"$asset")"
  name="$(jq -r '.name' <<<"$asset")"
  digest="$(jq -r '.digest' <<<"$asset")"
  state="$(jq -r '.state' <<<"$asset")"

  [[ "$asset_id" =~ ^[1-9][0-9]*$ ]]
  [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]]
  [[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]]
  test "$state" = uploaded
  test ! -e "$destination/$name"

  gh api \
    -H 'Accept: application/octet-stream' \
    "repos/$repository/releases/assets/$asset_id" > "$destination/$name"
  actual="$(sha256sum "$destination/$name" | cut -d ' ' -f 1)"
  test "sha256:$actual" = "$digest"
done < <(jq -r '.assets[] | @base64' <<<"$release")

test "$(find "$destination" -mindepth 1 -maxdepth 1 -type f | wc -l | tr -d ' ')" = "$asset_count"
