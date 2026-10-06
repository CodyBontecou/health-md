# Apple testing

Use the test sources and [component Makefile](../../Makefile) for the current suite and commands. Test counts, task IDs, and execution waves from past sessions are not a maintained test inventory. Track current work in the issue tracker or ignored repository-root `.pi/` state rather than duplicating it in documentation.

## Sources

| Area | Source |
|---|---|
| Export byte/structure contracts and fixtures | [Export tests](../../HealthMdTests/Export/) and [fixtures](../../HealthMdTests/Fixtures/) |
| Managers and HealthKit adapters | [Manager tests](../../HealthMdTests/Managers/) and [runtime protocols](../../HealthMd/Shared/Protocols/) |
| Lifecycle and concurrency support | [Support tests and harness](../../HealthMdTests/Support/) |
| UI journeys | [UI tests](../../HealthMdUITests/) |
| CI configuration and gates | [Workflow index](../../../../.github/workflows/README.md) and [CI quality-gate runbook](CI-QUALITY-GATES.md) |

## Policies and runbooks

- [TDD protocol](TDD.md) and [completion-evidence template](TDD-COMPLETION-TEMPLATE.md).
- [Lifecycle retention rationale](lifecycle-audit.md): preserve this workaround knowledge while the referenced tests depend on it.
- [HealthKit partial failures](healthkit-partial-failures.md) and [scheduled-export recovery](scheduled-export-recovery-qa.md).
- [Export performance instrumentation](export-performance.md) and [physical performance lab](physical-export-lab.md).
- [UI-test development](UI-TESTS.md), [accessibility qualification](accessibility-ios-implementation.md), and [Shortcuts runtime validation](shortcuts-runtime-validation.md).
- [APNs scheduling preflight](apns-scheduling-preflight.md).

The repository-root [verification policy](../../../../AGENTS.md#verification-policy) governs execution: simulator/device QA and Argent require explicit authorization for the current task. A linked UI or physical-lab runbook is not permission to run it.
