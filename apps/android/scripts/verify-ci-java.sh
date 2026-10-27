#!/usr/bin/env bash
set -euo pipefail

# A floating 17 selector admitted both 17.0.20.1 and 17.0.21 in one matrix.
# Check the actual runtime as well as the setup action's requested version.
if ! settings=$(java -XshowSettings:properties -version 2>&1); then
  echo 'Unable to verify the pinned CI Java runtime.' >&2
  exit 1
fi
runtime=$(printf '%s\n' "$settings" | sed -n 's/^[[:space:]]*java.runtime.version = //p')
vendor=$(printf '%s\n' "$settings" | sed -n 's/^[[:space:]]*java.vendor = //p')
if [[ "$runtime" != '17.0.21+9' || "$vendor" != 'Eclipse Adoptium' ]]; then
  echo 'CI requires Temurin Java 17.0.21+9; runtime identity differs.' >&2
  exit 1
fi
echo 'Verified Temurin Java 17.0.21+9.'
