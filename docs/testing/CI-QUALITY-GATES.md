# CI Quality Gates

This document describes all CI quality gates, how to run them locally, and how to update their configuration.

## Overview

| Gate | Script | Config | PR CI | Nightly CI |
|------|--------|--------|-------|------------|
| Coverage threshold | `scripts/check-coverage.sh` | `.ci/coverage-thresholds.json` | Yes | Yes |
| Warning gate | `scripts/check-warnings.sh` | `.ci/warning-baseline.json` | Yes | Yes |
| TDD evidence guard | `scripts/check-tdd-evidence.sh` | — | No | Yes |

## Coverage Threshold Gate

Fails CI when overall code coverage drops below the configured minimum.

### Local commands

```bash
# Generate coverage (runs macOS tests with coverage enabled)
make coverage

# Check threshold against last coverage run
make check-coverage

# Or run the script directly
scripts/check-coverage.sh build/coverage/HealthMd.xcresult
```

### Configuration

Edit `.ci/coverage-thresholds.json`:

```json
{
  "minimum_coverage": 10.0,
  "warn_below": 30.0
}
```

- `minimum_coverage` — CI fails below this percentage
- `warn_below` — CI warns (but passes) below this percentage

### Example output

**Pass:**
```
Overall coverage: 24.46% (14336/58608 lines)
Minimum required: 10.0%
PASS: Coverage 24.46% meets minimum threshold 10.0%.
```

**Fail:**
```
Overall coverage: 5.00% (2930/58608 lines)
Minimum required: 10.0%
FAIL: Coverage 5.00% is below minimum threshold 10.0%.
```

### Updating thresholds

1. Edit `.ci/coverage-thresholds.json`
2. Run `make coverage && make check-coverage` to verify locally
3. Commit the updated config

## Warning Gate

Detects targeted compiler warnings (especially Swift concurrency warnings) in build logs. Prevents warning debt from growing silently.

### Local commands

```bash
# Build and capture logs
mkdir -p build/logs
make test 2>&1 | tee build/logs/build-test.log

# Check for targeted warnings
make check-warnings

# Or run the script directly
scripts/check-warnings.sh build/logs/build-test.log
```

### Configuration

Edit `.ci/warning-baseline.json`:

```json
{
  "allowed_count": 0,
  "patterns": [
    "concurrency",
    "Sendable",
    "actor-isolated",
    "non-isolated",
    "global actor",
    "nonisolated\\(unsafe\\)"
  ]
}
```

- `allowed_count` — max number of targeted warnings before CI fails (set to 0 for zero-tolerance)
- `patterns` — regex patterns matched against lines containing `warning:`

### Example output

**Pass (no warnings):**
```
No targeted warnings found.
PASS: 0 targeted warnings within allowed count of 0.
```

**Fail (new warnings):**
```
Found 2 targeted warning(s):
  Foo.swift:42:5: warning: capture of 'self' with non-sendable type...
  Bar.swift:10:3: warning: passing argument of non-sendable type...
FAIL: 2 targeted warnings exceed allowed count of 0.
```

### Updating the baseline

If you intentionally introduce code with known warnings and need to temporarily raise the allowed count:

1. Edit `.ci/warning-baseline.json` and increase `allowed_count`
2. Run `make check-warnings` to verify locally
3. Commit with a note explaining why the baseline was raised
4. File a follow-up to reduce it back

## TDD Evidence Guard

Validates that all testing todos marked "done" include RED/GREEN/REFACTOR evidence sections. Runs in the nightly workflow only (not on PR) to avoid blocking active development.

### Local commands

```bash
# Check all completed testing todos for TDD evidence
make check-tdd

# Or run the script directly
scripts/check-tdd-evidence.sh
```

### How it works

1. Scans `.pi/todos/*.md` for files with `"testing"` tag and `"status": "done"`
2. For each, checks that the file contains `### RED`, `### GREEN`, and `### REFACTOR` sections
3. Fails with a list of offending todo IDs if any are missing

### Example output

**Pass:**
```
Checked 30 completed testing todo(s).
PASS: All completed testing todos have TDD evidence.
```

**Fail:**
```
  FAIL: TODO-abc12345 — missing: RED, GREEN, REFACTOR
Checked 30 completed testing todo(s).
FAIL: 1 todo(s) missing required TDD evidence:
  - TODO-abc12345: missing RED,GREEN,REFACTOR
```

### Fixing a failure

1. Open `.pi/todos/<id>.md`
2. Append TDD evidence using the template from `docs/testing/TDD-COMPLETION-TEMPLATE.md`
3. Re-run `make check-tdd` to verify

## CI Workflow Structure

### PR workflow (`.github/workflows/tests.yml`)

Two parallel jobs:

- **test-ios** — iOS unit tests + UI smoke tests + warning gate + log artifacts
- **test-macos** — macOS unit tests + coverage + coverage threshold + warning gate + xcresult/log artifacts

### Nightly workflow (`.github/workflows/nightly.yml`)

Runs daily at 4:00 AM UTC. Two parallel jobs with extended checks:

- **extended-ios** — full UI test suite + strict warning gate + 30-day artifact retention
- **extended-macos** — full test suite + coverage + warning gate + TDD evidence guard + 30-day artifacts

### Concurrency

Both workflows use `cancel-in-progress: true` to avoid wasting resources on superseded runs.

## Troubleshooting

### "Coverage data unavailable"

The xcresult bundle may not have been generated. Re-run:
```bash
make coverage
```

### "No coverage data found in xcresult bundle"

The xcresult exists but contains no coverage data. Ensure the test scheme has code coverage enabled:
```bash
xcodebuild test -enableCodeCoverage YES ...
```

### Script exits non-zero but no clear error

All scripts use `set -euo pipefail`. Check stderr output. Common causes:
- Missing `python3` (used for JSON parsing)
- Malformed config JSON in `.ci/` directory
- Missing build artifacts (logs/xcresult not generated yet)

### Adding a new warning pattern

1. Add the pattern string to the `patterns` array in `.ci/warning-baseline.json`
2. Test locally: `scripts/check-warnings.sh build/logs/build-test.log`
3. Commit the updated baseline
