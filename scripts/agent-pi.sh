#!/usr/bin/env bash
# Explicitly load the worktree guard even when Pi starts inside a component.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
exec pi --extension "${ROOT}/.pi/extensions/verification-guard.ts" "$@"
