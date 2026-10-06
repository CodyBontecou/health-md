# CI Quality Gates

This runbook explains how to investigate the Apple gates. Their scripts, configuration, and workflow files own the current thresholds, warning patterns, runner versions, job graph, and schedule; those values are not copied here.

Run the commands below from `apps/apple`. The repository-root [verification policy](../../../../AGENTS.md#verification-policy) still applies: a workflow or linked runbook does not authorize local simulator/device QA. Use the root [test selection guide](../../../../docs/testing-strategy.md) for focused iteration and build reuse; these gates are not a per-edit checklist.

## Gate owners

| Gate | Implementation | Configuration |
|---|---|---|
| Coverage threshold | [`check-coverage.sh`](../../scripts/check-coverage.sh) | [`coverage-thresholds.json`](../../.ci/coverage-thresholds.json) |
| Compiler warnings | [`check-warnings.sh`](../../scripts/check-warnings.sh) | [`warning-baseline.json`](../../.ci/warning-baseline.json) |
| Local task TDD evidence | [`check-tdd-evidence.sh`](../../scripts/check-tdd-evidence.sh) | Ignored root `.pi/todos`, or explicit `TODOS_DIR` |
| APNs scheduling preflight | [`check-apns-scheduling-preflight.sh`](../../scripts/check-apns-scheduling-preflight.sh) | [Entitlements](../../HealthMd/HealthMd.entitlements) and [Info.plist](../../HealthMd/Info.plist) |

## Coverage Threshold Gate

```bash
make coverage
make check-coverage
```

The threshold configuration distinguishes the failing minimum from the warning threshold. Inspect the JSON for their current values; the coverage script reports the measured result and required minimum.

Change the configuration deliberately, rerun the gate against a fresh coverage result, and record the reason in the PR. A stale or missing xcresult bundle does not establish coverage. If extraction fails, use the [Makefile](../../Makefile) to regenerate the result and inspect the script's diagnostics.

## Warning Gate

```bash
mkdir -p build/logs
make test-macos 2>&1 | tee build/logs/build-test.log
scripts/check-warnings.sh build/logs/build-test.log
```

The warning baseline owns both the allowed count and targeted patterns. A passing gate applies only to the log supplied to it. When intentionally changing the baseline, explain the debt and track its removal; do not raise it simply to hide a regression.

## TDD Evidence Guard

```bash
scripts/check-tdd-evidence.sh
```

The guard checks completed, testing-tagged local todos for RED/GREEN/REFACTOR evidence. A clean CI checkout has no ignored local todos and passes without validating anyone's private task records. An explicitly configured missing `TODOS_DIR` is an error.

Use the [TDD protocol](TDD.md) and [completion template](TDD-COMPLETION-TEMPLATE.md) when recording evidence. Keep task IDs, ownership, progress, and completion receipts in the tracker rather than another Markdown index.

## APNs Scheduling Preflight

```bash
make check-apns-scheduling
```

The [APNs runbook](apns-scheduling-preflight.md) owns fixture setup and focused test guidance. The source guard validates the production bridge; it is not proof of a delivered notification or successful physical-device recovery.

## Workflow ownership and troubleshooting

- [Apple PR/main CI](../../../../.github/workflows/apple-ci.yml) owns its job selection, commands, artifacts, and runner configuration.
- [Apple nightly CI](../../../../.github/workflows/apple-nightly.yml) owns extended checks and its schedule.
- The [workflow index](../../../../.github/workflows/README.md) explains repository-wide boundaries.

Inspect the failing script, current configuration, and the exact run's logs/results before changing a gate. Check missing tools, malformed JSON, missing build output, and mismatched coverage/log paths first. Workflow summaries and archived measurements are receipts for specific runs, not current test counts or release approval.
