#!/usr/bin/env bash
set -euo pipefail
python3 -m unittest discover -s scripts/ci -p 'test_*.py'
python3 -m unittest discover -s scripts/native -p 'test_*.py'
# Bounded native-copy boundary; no SDK or simulator is required.
python3 -m unittest discover -s apps/apple/scripts/tests -p 'test_metric_selection_localizations.py'
python3 -m unittest discover -s apps/apple/scripts/tests -p 'test_frontmatter_localizations.py'
python3 -m unittest discover -s apps/apple/scripts/tests -p 'test_daily_note_localizations.py'
python3 -m unittest discover -s apps/apple/scripts/tests -p 'test_individual_tracking_localizations.py'
python3 -m unittest discover -s apps/apple/scripts/tests -p 'test_apple_localization_*.py'
python3 -m unittest discover -s apps/apple/scripts/tests -p 'test_merge_reviewed_localizations.py'
# All manifests, fixtures and producer/consumer mirrors; source-only checkout omits media links.
python3 packages/contracts/validate.py --product-parity-only
python3 -m unittest discover -s packages/contracts -p 'test_validate_manifest.py'
python3 packages/contracts/test_watch_capability_governance.py
python3 packages/healthmd-core-rust/scripts/tests/test_registry_capability_scope.py
python3 packages/healthmd-core-rust/scripts/import-native-registry.py --check
python3 packages/healthmd-core-rust/scripts/generate-registry-adapters.py --check

# Manual clinic licensing is metadata-only and has no installed dependencies.
node --test apps/licensing/test/*.test.mjs
python3 -m unittest scripts.tests.test_clinic_export_authorization
python3 packages/healthmd-core-rust/scripts/update-package-fixtures.py --check
