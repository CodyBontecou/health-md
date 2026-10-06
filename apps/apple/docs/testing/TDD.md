# Test-Driven Development Protocol (Red/Green/Refactor)

This project uses **strict TDD** for all testing-related work items.

## Required cycle for every testing task

1. **RED**
   - Add or update a test that expresses the behavior change.
   - Run the smallest relevant test command.
   - Confirm it fails for the expected reason.

2. **GREEN**
   - Implement the minimal production/test-support code to make the RED test pass.
   - Re-run the same focused test command.
   - Confirm it passes.

3. **REFACTOR**
   - Improve code structure/readability while keeping behavior unchanged.
   - Re-run focused tests after relevant inputs change; retain the GREEN result if nothing affecting it changed.
   - Run the impacted module's broader regressions once at the end of a coherent change/batch, not after every tiny edit or todo. Escalate contract/security/FFI changes according to the root [verification policy](../../../../AGENTS.md#verification-policy).
   - Record passing commands and any blocked/opt-in verification gap. Simulator/device/Argent workflows require explicit authorization for the current task; use host-side orchestration tests for script/CI changes.

## Required evidence before closing a testing todo

Every testing todo must include this evidence in its notes/body before being marked closed:

- **RED evidence**
  - exact test name(s)
  - exact command run
  - failure output summary
- **GREEN evidence**
  - exact command run
  - passing output summary
- **REFACTOR evidence**
  - what was refactored
  - confirmation command(s) and pass result

## Closure rule

If RED/GREEN/REFACTOR evidence is missing, the testing todo is **not complete**.

## Completion template

Use `docs/testing/TDD-COMPLETION-TEMPLATE.md` when appending evidence to todos.
