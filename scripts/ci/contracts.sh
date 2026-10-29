#!/usr/bin/env bash
set -euo pipefail
python3 -m unittest discover -s scripts/ci -p 'test_*.py'
python3 -m unittest discover -s scripts/native -p 'test_*.py'
# Bounded native-copy boundary; no SDK or simulator is required.
python3 -m unittest discover -s apps/apple/scripts/tests -p 'test_metric_selection_localizations.py'
python3 -m unittest discover -s apps/apple/scripts/tests -p 'test_frontmatter_localizations.py'
python3 -m unittest discover -s apps/apple/scripts/tests -p 'test_daily_note_localizations.py'
python3 -m unittest discover -s apps/apple/scripts/tests -p 'test_individual_tracking_localizations.py'
# All manifests, fixtures and producer/consumer mirrors; source-only checkout omits media links.
python3 packages/contracts/validate.py --product-parity-only
python3 packages/healthmd-core-rust/scripts/import-native-registry.py --check
python3 packages/healthmd-core-rust/scripts/generate-registry-adapters.py --check
