# Health.md Effect refactor: agent execution plan

**Status:** End-to-end goal active. The manifest records current implementation, review and qualification progress; source inventories and technical decisions do not establish product admission.

**Design baseline:** 2026-10-07, repository revision `1b02fcc69f4706bca56de67698d2dc85996047b6`.

This is the entry point for coding agents implementing the selected Effect/React refactor. The full [design and research reference](javascript-unified-layer-design-reference.md) preserves the original scope, source evidence, contracts and acceptance obligations. Load its relevant sections for a task, rather than treating the entire rewrite as one assignment.

## Start here

From the repository root:

```bash
python3 docs/migration/effect-refactor/manage.py check
python3 docs/migration/effect-refactor/manage.py ready --limit 3
python3 docs/migration/effect-refactor/manage.py brief BASE-CORE
python3 docs/migration/effect-refactor/manage.py reference K01
```

These commands inspect the execution kit; they neither claim tasks nor execute builds, launch agents or change state. The preferred starting agent profile is recorded in [plan.json](../migration/effect-refactor/plan.json). Use bounded assignments with that profile; exact checks and independent review establish correctness.

The first recommended dispatch is `BASE-CORE`, `BASE-CLI` and `BASE-HOST`: three independent source/fixture/state inventories. Their accepted outputs enable the local successor decision, portable pins and first shared health-query slice. Native, donor and cloud inventories can follow in parallel within the configured writer limit. The manifest records current task progress; “ready” means declared dependencies permit assignment, and does not imply completion.

## Sources of truth

| Material | Authority | When an agent reads it |
| --- | --- | --- |
| Root/nearest component `AGENTS.md` and cross-platform policy | Current repository, component, contract and release rules | Before work in the affected component |
| This entry point | Dispatch, scope, state, review and integration procedure | Every refactor assignment |
| [Task manifest](../migration/effect-refactor/plan.json) | Task graph, claims, open choices, remaining scope and recorded progress | Through `manage.py brief/ready/catalog/phase`; coordinator maintains it |
| [Design reference](javascript-unified-layer-design-reference.md) | Selected D01–D18 constraints, C/K/O/U/P/L/S/H obligations, F risks and V gates | Only the task's IDs/sections and affected source references |
| Scoped workstream brief | Decomposition rules and branch-specific implementation boundaries | Read the one branch assigned below |
| [Dispatch/evidence templates](../migration/effect-refactor/templates.md) | Concrete worker/reviewer/coordinator prompts and receipt schema | At dispatch, review and handoff |
| Actual source, manifests, fixtures and executable scripts | Current implementation/version/check facts | Verify against the task's pinned inputs; record drift |

The four branches are [core/CLI](../migration/effect-refactor/core-cli.md), [native/UI](../migration/effect-refactor/native-ui.md), [personal data/donors](../migration/effect-refactor/personal-data.md), and [cloud/CI/release](../migration/effect-refactor/cloud-release.md). Their task recipes point to the complete design; they do not replace its acceptance criteria. Proposed package paths/commands/versions become qualified only through implementation evidence.

## Fixed scope and decisions

The selected architecture removes all maintained Rust application/tooling paths, uses one portable Effect core and complete common operations for UI/CLI/MCP, and shares React UI/feature logic across qualified hosts. Native SDK/security/background capabilities stay native. Health.md remains the product; health, location and device usage have separate typed payloads and grants, with combined or scoped exports at existing depth. Local use requires no cloud account.

macOS is the first desktop collector, with window titles and full future observed sessions plus all available historical donor sessions. iOS retains available historical aggregates; exact historical app sessions remain required S06 follow-up under the accepted aggregate-first exception. Windows/Linux collectors, browser/input acquisition and unrelated health-profile convergence remain separately tracked. The detailed source exclusions and platform/purpose limits remain in the design.

Optional hosted exports and read-only remote MCP use the same operations with explicit retained-source provenance/freshness, server-readable consent and independently scoped device/owner/agent authority. Named agent targets remain individually unverified until their client-specific gates pass. Practice, Wake, static website and existing non-personal-data services retain their isolated authority.

D01–D18 are architecture constraints. Q decisions in the manifest are actual pending choices; F01–F20 are technical proof obligations. A technical owner may resolve implementation choices from evidence within the user's selected requirements. Product/support/privacy/commercial choices go to their assigned authority with concrete alternatives. Record the resolution, evidence, scope and reconsideration trigger; update only dependent tasks. An open cloud region/billing choice does not block portable health work or synthetic cloud fault models.

## Dispatch and completion procedure

1. **Select.** Validate the manifest and choose an atomic dependency-ready task. Read its scoped design IDs and actual inputs. Record source SHA, dirty-state fingerprint, existing fixture identity and command availability. Complete when the outcome, inputs and checks can be stated precisely; unresolved prerequisites remain explicit.
2. **Claim.** The coordinator assigns agent, base revision, worktree, exact allowed write paths, shared resources and reviewer. Complete when claims do not conflict with another writer. A task requiring broader files receives an amended scope before those writes.
3. **Implement.** Execute one observable behavior or proof. Keep current production authority during candidate work. Complete every acceptance item using independent source/fixtures and appropriate checks; a partial result is a handoff with named remaining work, rather than an implied success.
4. **Review.** Write a sanitized receipt and obtain an independent scoped-diff review. Complete when all blocking findings are fixed and review names its exact source/patch fingerprint. Crypto, tenant/grant auth, durable commitment, restore/deletion and cutover always receive independent review.
5. **Integrate.** The coordinator reconciles shared changes, integrates them onto the recorded source, runs affected checks, and records integrated evidence. Complete when dependency consumers use the intended source and unresolved failures are recorded. A stale task-branch receipt cannot qualify the integration.
6. **Advance.** Update task/review/proof state and remaining family scope; recompute readiness. Complete a family/phase only after its whole required matrix passes. Production rollout and Rust deletion have their own evidence, rollback and actual action authorization.

Use the [templates](../migration/effect-refactor/templates.md) for the concrete assignment. Every task specifies one outcome, prerequisites, design IDs, allowed paths/resources, checks/availability, consumers, receipt, reviewer and retained rollback route. M00–M10 and the 86 C/K/O/U/P/L/S/H families are coverage rollups, never executable mega-tasks.

## Concurrency and context

The manifest is the coordinator's single-writer state. Workers own their claimed implementation/tests and receipt, then return the handoff. One writer at a time owns a package lock/manifest, contract revision, registry authority, generated family, migration sequence, Xcode/Gradle project graph, shared public interface, workflow aggregate or deployment policy. Integrate shared interfaces before parallel consumers.

Read-only agents can share a checkout. Coding writers can use disjoint claims in a coordinated checkout or managed worktrees; reserve shared resources in either case. Establish an accepted committed execution-kit/source baseline before creating other worktrees, since uncommitted files do not appear there automatically. Start each from the recorded integration revision, rather than an arbitrary remote default. Keep active worktrees/writers bounded and reuse immutable caches; mutable outputs stay scoped. Cleanup follows the design's explicit build-output policy and excludes user exports/spools/donor data.

A worker loads this entry point, one task brief, the nearest instructions and its selected reference IDs. `manage.py reference ID` prints the exact design row or K section. Reach additional source only when an acceptance item requires it. If another independent behavior, host/channel or durable boundary enters the task, split it and declare its dependency. Whole “port K05/O02,” “rewrite the Apple UI” or “implement M04” tasks require decomposition first.

## Task and gate states

| Record | States | Meaning |
| --- | --- | --- |
| Task | `not_started`, `in_progress`, `blocked`, `review`, `done` | Bounded deliverable progress. Readiness is derived, not manually asserted. |
| Review | `pending`, `changes_requested`, `accepted` | Independent review of an exact source/patch |
| Proof | `pending`, `passed`, `failed`, `stale`, `not_applicable` | Evidence for a named proof class and exact host/profile/channel |
| Family/phase | `not_started`, `in_progress`, `blocked`, `qualified`, `retired` | Complete design obligation and admission/retirement matrix |
| Choice | `open`, `accepted`, `deferred` | A recorded resolution from its assigned authority |

A task is `done` only with a passed bounded receipt, matching required checks and accepted review of the same fingerprint. That does not qualify its parent or a native, signed, physical, external-client or deployed environment. Those proof classes have separate tasks/receipts. Rollup closure requires a reviewed complete qualification matrix and current integrated proofs for every case; `manage.py matrix ID` identifies its inputs. Changed source/locks/runtime/contracts/artifacts/policy make affected evidence stale. `manage.py check` validates structure and referenced evidence; it cannot verify an agent's claim that tests or external qualification occurred.

Use `blocked` for a concrete task prerequisite, access/environment or failure with a recorded unblock condition. Continue independent ready work. S06 and unavailable source/client paths retain explicit follow-up owners/targets; label exceptions rather than inventing parity or declaring the missing capability done.

## Expand and close the backlog

The manifest contains concrete initial tasks and every design family as remaining coverage. Families begin `needs_decomposition`; their exact design obligation remains open after a first slice. Each `SPLIT-*` task produces a reviewed packet of at most six child cards for its named scope, with the next packet trigger and remaining obligations explicit. The coordinator adds accepted cards, decisions, edges and claims, then validates the graph. No implementation is dispatched from an unexpanded family alone.

For a child card, identify the exact source/fixture/check list, observable outcome, one module/profile/entrypoint/platform/channel or durable boundary, independent expected result, state/contract impact, consumers and later admission/deletion gates. If a design row contains multiple outcomes, represent all of them as children or explicit remaining scope. Family closure needs accepted decomposition and evidence for the entire row, rather than a count of completed cards.

Phases report M00 baseline/decisions, M01 foundation/slice, M02 feasibility, M03 contracts/core, M04 operations, M05 native acquisition, M06 primary UI, M07 remaining interfaces/consumers, M08 qualification, M09 promotion/window, and M10 retirement. Their applicable dependencies are task-specific. The [final definition of done](javascript-unified-layer-design-reference.md#final-definition-of-done) and V01–V13 govern completion of the whole selected scope.

## Actions and final gates

Ordinary reversible implementation, source inspection, synthetic checks and review proceed within the assigned scope. Real-data access, provider/client connection, production deployment, store publication, authority promotion and destructive data operations are separately scoped actions with the user's actual authorization and applicable component procedures. Prepare reviewable code/configuration, checks and rollback first. Historical pilot consent or this execution kit does not authorize a new account/client/deployment.

Preserve frozen public bytes, retained state/engine pins and source truth throughout. Run the affected producer/consumer gates; proposed commands are marked as such until created and verified. Rust retirement waits for qualified replacements, independent fixtures, installed-state recovery, exact-source promotion and the required rollback window. The final proof includes cloud/CLI/native/artifact dependency graphs and a clean supported checkout with Rust tooling absent.
