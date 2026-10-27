#!/usr/bin/env bash
set -euo pipefail
python3 -m unittest discover -s scripts/ci -p 'test_*.py'
# All manifests, fixtures and producer/consumer mirrors; source-only checkout omits media links.
python3 packages/contracts/validate.py --product-parity-only
python3 packages/healthmd-core-rust/scripts/import-native-registry.py --check
python3 packages/healthmd-core-rust/scripts/generate-registry-adapters.py --check
python3 apps/cli/scripts/update-mcp-shared-assets.py --check
