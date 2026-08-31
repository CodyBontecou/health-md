#!/usr/bin/env bash
set -euo pipefail

manifest="${1:?manifest path required}"
crate="${2:?crate name required}"
version="${3:?version required}"
: "${CARGO_REGISTRY_TOKEN:?temporary or bootstrap crates.io token required}"

workspace_dir="$(cd "$(dirname "$manifest")" && pwd)"
manifest="$workspace_dir/$(basename "$manifest")"
api="https://crates.io/api/v1/crates/${crate}/${version}"
download="${api}/download"
curl_user_agent="healthmd-cli-release/0.1 (+https://github.com/CodyBontecou/health-md)"

echo "Packaging ${crate} ${version} from ${manifest}"
cargo package --manifest-path "$manifest" --locked -p "$crate"
metadata="$(cargo metadata --manifest-path "$manifest" --no-deps --format-version=1)"
target_directory="$(jq -r .target_directory <<<"$metadata")"
archive="${target_directory}/package/${crate}-${version}.crate"
test -f "$archive"
local_sha="$(sha256sum "$archive" | awk '{print $1}')"

version_exists() {
  curl --proto '=https' --tlsv1.2 --fail --silent --show-error \
    --user-agent "$curl_user_agent" "$api" >/dev/null 2>&1
}

wait_for_index() {
  for attempt in $(seq 1 60); do
    if cargo info "${crate}@${version}" >/dev/null 2>&1; then
      echo "${crate} ${version} is visible through Cargo's registry index"
      return 0
    fi
    echo "Waiting for ${crate} ${version} index visibility (${attempt}/60)"
    sleep 10
  done
  echo "${crate} ${version} did not become visible through Cargo's registry index" >&2
  return 1
}

verify_existing() {
  local downloaded
  downloaded="$(mktemp)"
  curl --proto '=https' --tlsv1.2 --fail --location --silent --show-error \
    --user-agent "$curl_user_agent" "$download" --output "$downloaded"
  downloaded_sha="$(sha256sum "$downloaded" | awk '{print $1}')"
  if [[ "$downloaded_sha" != "$local_sha" ]]; then
    echo "${crate} ${version} already exists with different archive checksum" >&2
    echo "local=${local_sha} registry=${downloaded_sha}" >&2
    rm -f "$downloaded"
    return 1
  fi
  rm -f "$downloaded"
  echo "${crate} ${version} already exists with the identical archive; publication is complete"
}

if version_exists; then
  verify_existing
  wait_for_index
  exit 0
fi

set +e
cargo publish --manifest-path "$manifest" --locked -p "$crate"
publish_status=$?
set -e
if [[ $publish_status -ne 0 ]]; then
  echo "cargo publish returned ${publish_status}; checking for an accepted upload" >&2
fi

for attempt in $(seq 1 60); do
  if version_exists; then
    verify_existing
    wait_for_index
    exit 0
  fi
  if [[ $publish_status -eq 0 ]]; then
    echo "Waiting for ${crate} ${version} registry visibility (${attempt}/60)"
  else
    echo "Waiting to resolve unknown ${crate} ${version} publish outcome (${attempt}/60)" >&2
  fi
  sleep 10
done

echo "${crate} ${version} did not become visible on crates.io" >&2
exit 1
