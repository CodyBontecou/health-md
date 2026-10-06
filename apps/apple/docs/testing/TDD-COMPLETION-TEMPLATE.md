# TDD Todo Completion Template

Use this block when updating a testing todo before closing it. Select checks using the root [test selection guide](../../../../docs/testing-strategy.md); reference an unchanged passing receipt where appropriate rather than rerunning a broad suite for every edit.

```md
## TDD Evidence

### RED
- Test(s):
  - `...`
- Command:
  - `...`
- Expected failure observed:
  - `...`

### GREEN
- Minimal implementation added:
  - `...`
- Command:
  - `...`
- Pass result:
  - `...`

### REFACTOR
- Refactor performed:
  - `...`
- Focused verification command:
  - `...`
- Broader verification command:
  - `...`
- Final result:
  - `...`

## Files Changed
- `...`
- `...`

## Notes / Follow-ups
- `...`
```

## Example command pattern

From `apps/apple`, for a macOS-compatible test:

- Focused test: use the [macOS XCTest command](../../../../docs/testing-strategy.md#focused-feedback) with `-only-testing:HealthMdTests/<TestClass>/<testMethod>`.
- Affected module: select the owning class with `-only-testing:HealthMdTests/<TestClass>`; `make test-macos` runs the macOS app suite.

iOS-only and UI tests require the current task's explicit simulator/device authorization under the root [verification policy](../../../../AGENTS.md#verification-policy).
