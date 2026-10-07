# Agent dispatch and evidence templates

Use these templates with the [execution plan](../../architecture/javascript-unified-layer-research.md). Replace every placeholder before dispatch. `manage.py brief TASK-ID` supplies the task fields; it does not claim or execute work. The coordinator alone updates `plan.json`.

## Implementation prompt

```text
Implement TASK-ID from docs/migration/effect-refactor/plan.json.

Read the execution entrypoint, the task brief produced by manage.py, the
nearest applicable AGENTS.md, and only the design/source sections listed
in the brief. Use the assigned base revision and worktree.

Outcome: COPY THE TASK'S ONE OBSERVABLE OUTCOME.
Write scope: COPY EXACT ALLOWED PATHS AND RESERVED SHARED RESOURCES.
Dependencies: COPY ACCEPTED TASKS/DECISIONS AND THEIR RECEIPT REFERENCES.
Input fixtures: COPY THE PINNED CASE IDS/DIGESTS OR INVENTORY LOCATION.
Acceptance: COPY THE TASK'S ACCEPTANCE CHECKLIST.
Verification: COPY COMMANDS, WORKING DIRECTORIES AND AVAILABILITY.
Reviewer: ASSIGNED REVIEWER; coordinator: ASSIGNED COORDINATOR.

Complete the authorized bounded work and its checks. Preserve production
authority and existing public/state contracts except the specific reviewed
change named in this task. Request a scope amendment before writing outside
the claim; continue independent in-scope work if an external prerequisite
is missing. Record the exact blocker rather than selecting an open product
decision silently.

Write the sanitized receipt at RECEIPT-PATH. Report changed paths, exact
checks/results, contract/state impact, limitations and the next dependency.
Do not mark a parent phase, native host, production service or retirement
gate qualified from this task's completion. Return the handoff in this task;
cross-thread messaging requires the human user's authorization.
```

## Review prompt

```text
Review TASK-ID against its accepted base, scoped diff, pinned source/fixtures
and receipt. Read the task brief and its exact design obligations.

Check every acceptance item; common-operation ownership; exact bytes and
numeric/time semantics; caller/source grants and coverage; bounded memory,
resources and cancellation; persisted-state/rollback; affected consumers;
required checks and actual proof class. Inspect the full diff, including
manifests, generated files, lockfiles and workflow path maps.

Prioritize observable correctness and omitted obligations. State actionable
findings with path/line, trigger, impact and correction. Identify checks you
actually ran versus receipt claims. If no blocking findings remain, report
accepted at EXACT SOURCE/PATCH FINGERPRINT with known limitations. Review
acceptance is not production, physical-device or release qualification.
Do not regenerate frozen expected results to agree with the implementation.
```

## Coordinator prompt

```text
Coordinate the Effect refactor using the execution entrypoint and plan.json.
Validate the plan. Select dependency-ready atomic tasks, reconcile input
revisions, claim disjoint write paths/shared resources, then dispatch the
selected task briefs. Start with the preferred model/reasoning profile in
the manifest unless the user changes it.

Keep at most the configured number of coding writers active. Use read-only
auditors/reviewers for independent work. Collect receipts and independent
review, integrate the scoped change, run affected checks on the integrated
revision, then update task/review/qualification state. Recompute readiness.

For an unexpanded family, dispatch its stream's decomposition recipe first.
Require exact source paths, fixtures, checks and bounded child outcomes
before implementation. Record remaining family scope explicitly. Track
open decisions and technical proof obligations by affected task, not by a
global phase stop. Advance a parent gate only with its complete host/profile
matrix and current receipts. Keep release/rollout/retirement as separately
authorized tasks with the design's qualification and rollback prerequisites.
```

## Receipt format

Write one JSON receipt under `receipts/TASK-ID.json`. The file is task evidence, not a payload log. Leave no invented result or example fingerprint in an actual receipt.

```json
{
  "task_id": "TASK-ID",
  "result": "passed",
  "proof_class": "planning",
  "source_sha": "actual 40-character source revision",
  "patch_digest": null,
  "changed_paths": [],
  "inputs": {
    "contract_and_fixture_digests": {},
    "locks_and_runtime": {},
    "artifact_and_native_interface": {},
    "policy_migration_key_versions": {}
  },
  "target": {"platform": "portable", "channel": "development", "profile": "scoped task"},
  "acceptance_results": [{"criterion": "exact task item", "result": "passed", "evidence": "safe evidence reference"}],
  "checks": [{"cwd": "repository-relative path", "argv": ["actual", "command"], "result": "passed", "evidence": "safe case IDs/counts"}],
  "inspection_summary": "planning-only source/case inventory evidence when no executable checks apply",
  "observations": [],
  "limitations": [],
  "remaining_qualification": [],
  "rollback": "concrete retained authority/recovery route",
  "review": {"status": "accepted", "reviewer": "actual independent reviewer", "fingerprint": "source_sha or source_sha+patch_digest"}
}
```

Allowed proof classes are `planning`, `portable_synthetic`, `host_integration`, `physical_device`, `signed_distribution`, `external_client`, and `deployed_operational`. Use `passed`, `failed`, or `partial` results and name every unrun/pending check. For planning, evidence includes source inventories, actual fixture/check paths and reviewed decisions; execution of product tests may be `not_applicable` with a reason. Claiming product behavior requires executed relevant checks.

For an actual manual device/client/operational qualification, `observations` records passed cases with `case_id`, `procedure`, `expected`, `observed` and a safe `evidence` reference. Pin the actual environment/artifacts in `target` and `inputs`. Inspection summaries cannot replace executed checks or actual observations for a non-planning proof; observations do not waive the task's required commands.

Copy the exact task `target` and accepted `review` into the receipt. Every declared verification command needs a matching working directory, argument array, passed result and evidence. A failed or partial check keeps the task open. Planning work without executable checks supplies an inspection summary. Keep proof state `pending` while independent review is pending; a `passed` proof is a validated JSON receipt with accepted review in task state `review` or `done`. Keep `patch_digest` null for committed source; for a dirty patch, use an actual SHA-256 and record the reproducible digest method and claimed tracked/untracked inputs. The reviewer must recompute it; review fingerprints use `source_sha+patch_digest` for that patch. Integrated qualification uses committed source.

Receipts contain safe case IDs, revisions, digests, counts, fixed errors and measurements. Health/location/usage values, credentials, account/device identifiers, private paths and raw parser/provider/Effect errors belong outside this evidence repository. Replace sensitive operational evidence with a restricted evidence reference and safe summary. Physical, client and deployed evidence must identify their actual environment without exposing customer data.

Relevant source, lock, runtime, native interface, contract/profile, fixture, key/policy/migration or artifact changes invalidate affected qualification. Preserve the old receipt as historical evidence and add current evidence. Final release and authority promotion require exact committed-source/artifact fingerprints; an uncommitted patch receipt is useful for review only.

## Family, phase and validation-gate qualification

Before closing a rollup, the coordinator records its complete `qualification_matrix` in `plan.json`. Each row names a stable case ID, the exact design requirement, host/channel/profile `target`, `proof_class`, and accepted prerequisite task IDs in `required_tasks`. Decomposition packets may add rows incrementally; closure requires independent review that the matrix covers the whole design obligation, including allowed exceptions and remaining follow-ups. A planning receipt or first slice cannot qualify a native, signed, physical, client or deployed gate.

The rollup's `matrix_review` records `status: accepted`, reviewer, `scope_complete: true`, `design_digest` and `fingerprint`. The design digest is SHA-256 of the UTF-8 exact row/section indexed by `manage.py reference ID`. The matrix fingerprint is SHA-256 of its canonical JSON (`sort_keys=True`, `separators=(",", ":")`, `ensure_ascii=False` in Python). The helper's `matrix ID` command prints both digests. If either design or matrix changes, review and qualification become stale.

Write a separate rollup JSON receipt and list its path in `qualification_receipts`:

```json
{
  "rollup_id": "V13",
  "result": "passed",
  "source_sha": "actual integrated 40-character revision",
  "patch_digest": null,
  "design_digest": "current indexed design SHA-256",
  "matrix_digest": "current reviewed matrix SHA-256",
  "cases": [{"case_id": "exact matrix case", "result": "passed", "proof_receipts": ["repository-relative task receipt.json"]}],
  "review": {"status": "accepted", "reviewer": "actual independent reviewer", "fingerprint": "source_sha"}
}
```

Every matrix case needs a passed task proof at one common integrated source, exact target and proof class. Multiple rollup receipts must qualify that same revision. Its required tasks must be done and independently reviewed. V gates require their actual environment classes; V12 needs external-client evidence and V13 deployed operational evidence. A family also needs accepted decomposition and no unassigned remaining scope. `manage.py check` rejects structurally premature closure, but evidence inspection and the complete normative design matrix remain the reviewer's responsibility.
