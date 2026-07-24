#!/usr/bin/env bash
set -euo pipefail

crate="${1:?crate name required}"
version="${2:?crate version required}"

for attempt in $(seq 1 30); do
  if cargo info "${crate}@${version}" >/dev/null 2>&1; then
    echo "${crate} ${version} is visible in the crates.io index"
    exit 0
  fi
  echo "Waiting for ${crate} ${version} index propagation (${attempt}/30)"
  sleep 10
done

echo "Timed out waiting for ${crate} ${version} index propagation" >&2
exit 1
