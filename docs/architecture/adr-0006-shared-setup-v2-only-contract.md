# ADR-0006: `healthmd.shared_setup` v2 becomes the one and only profile contract

- **Status:** Accepted
- **Date:** 2026-09-05
- **Decision owners:** Repo owner (the deliberate, separately reviewed gate-4 decision recorded verbatim below); shared-setup contract, Apple, and Android maintainers as executing owners
- **Scope:** The `healthmd.shared_setup` portable setup-profile contract and its platform readers/writers only — not `healthmd.health_data`, direct protocols, or any `ExportTarget`

## Context

Share My Setup v1 was designed and landed pre-canonical: the contract is `deferred`, the capability `setup.share-portable-configuration` is classified `planned` on both platforms, and nothing has shipped to end users. Cycles 2–6 then landed `healthmd.shared_setup` **version 2** — the multi-profile root bundle, inert destination intent, disabled schedule imports, typed per-profile extensions, the per-profile compatibility sidecar, blocked fail-closed execution with explicit rebind gates, atomic apply with verified rollback, and one-shot Undo — specified, implemented, and host-side tested behind explicit, caller-supplied seams.

Through cycle 9 both versions therefore coexisted in a dual-dispatch interim state: every production default writer still emitted `schema_version: 1`, v2 was reachable only through explicit writer seams, and the readers accepted strict integer `1`/`2`.

The [v2 QA record](../qa/shared-setup-v2.md) reserves exactly this kind of change to its remaining gate 4: *"A deliberate, separately reviewed decision changes status, capability classification, or the default writer — never silently through integration work."* This ADR records that decision.

The v1 capability was never released. Its only consumers ever created were contract fixtures, platform test suites, and development artifacts produced by the unreleased binaries themselves — there are **no in-the-wild v1 documents** because no build that writes them has shipped.

## Decision

On 2026-09-05 the repo owner decided, in direct conversation with the cycle-9 coordinator (verbatim, never paraphrased):

1. *"let's move away from the v1 contract and work towards making v2 the one and only profile contract"*
2. *"okay, i like your read - implement them, use our fleet loop skill if relevant"*

The fleet loop was re-armed expressly to execute this decision. It resolves as follows:

- **v2 is the one and only profile contract.** `healthmd.shared_setup` version 2 is the sole portable setup-profile contract; there is no v1 contract alongside it.
- **v1 sunsets by removal, not by deprecation shim.** The v1 contract family is removed from `packages/contracts/shared-setup/v1/`, and the v1 dispatch arms, mappers, and era-specific tests are removed from both platforms. No compatibility aliasing, no read-window, and no v1-accepting mode remains.
- **Default production writers emit `schema_version: 2` exclusively** on both platforms. The normal production Share/export paths produce v2 documents; the former explicit v2 writer seams are no longer the only v2 producers.
- **v1 input fails closed as an unsupported version.** A document declaring `schema_version: 1` is rejected exactly like any other unknown version, before review, with a bounded non-secret error and zero writes.

### Rationale

v1 was pre-canonical and the capability is unreleased (`planned`, needs-QA). There are no in-the-wild v1 consumers — only fixtures, tests, and development artifacts — so making v2 "the one and only" is a **clean removal, not a deprecation**. Carrying a dual-version reader/writer surface would have doubled the physical-device QA matrix and preserved a contract that no shipped consumer depends on, contrary to the cross-platform policy of never fabricating parity or carrying dead contract surface.

## What did NOT change

- The capability classification stays **`planned` on both platforms** in `packages/contracts/product-capabilities.json`; this decision is not an availability flip.
- Canonicalization stays **`deferred`**.
- The [v2 physical-device execution matrix](../qa/shared-setup-v2.md#cycle-6-amendment-2026-09-05) (24 rows, all `Not run`) remains outstanding and is still **required before any availability decision**. The availability path continues to require the user-run matrix plus a follow-on, separately reviewed call.
- The shared-setup contract still versions independently of Apple `healthmd.health_data` v8, Android v4/v5, the direct protocols, and any `ExportTarget`. This ADR changes no public export schema and no direct-protocol version.

## Consequences

- The reader/writer surface to qualify shrinks to one version: v2. The v2 QA record's matrix was true'd up to the v2-only reality (v1 documents now expected to fail closed), with every row's status still `Not run`.
- The [v1 QA record](../qa/shared-setup-v1.md) is mooted as an executable gate: its matrices and rows no longer govern any shipped code path. Its simulator/emulator/physical receipts remain valid **history** for the v1-era binaries that produced them, per the disposition recorded in that file.
- Development-era v1 artifacts (fixtures, host-staged files) are regenerated or staged as v2; none were ever user-produced.
- Every producer and consumer of the shared-setup family — contracts manifest, shared-core consumers, Apple, Android, CLI gates, website references — must acknowledge the removal in the same integration cycle, per the repository contract-change checklist.

## Provenance and cross-references

- Decision quotes above: repo owner, 2026-09-05, direct instruction to the cycle-9 coordinator; executed by fleet cycle 10 (contracts, Apple, Android, docs lanes).
- [v2 QA record](../qa/shared-setup-v2.md) — [cycle-10 amendment](../qa/shared-setup-v2.md#cycle-10-amendment-2026-09-05) records the gate-4 execution and the matrix true-up.
- [v1 QA record](../qa/shared-setup-v1.md) — dated disposition of the mooted v1 surface.
- Capability registry: `setup.share-portable-configuration` in [`packages/contracts/product-capabilities.json`](../../packages/contracts/product-capabilities.json).
