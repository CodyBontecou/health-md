# Cloud, CI, release and retirement tasks

Read this branch for H00–H09, C18–C22, O12–O14, service security, CI/generators, release or Rust retirement. Consult the [cloud design](../../architecture/javascript-unified-layer-design-reference.md#optional-hosted-exports-and-remote-mcp) and [release/retirement requirements](../../architecture/javascript-unified-layer-design-reference.md#release-and-rollback) for exact obligations.

## Work that proceeds before cloud product decisions

`BASE-CLOUD` audits accepted pilot source, profile/read compatibility, auth boundaries and pending policy. `CLOUD-FAULT-MODEL` creates synthetic ingestion, overlap/query, grant/revoke and restore/erasure cases. Fake hosted ports and bounded contract drafts can reuse the portable slice without provider credentials or customer data. Mark unselected retention/capacity/auth limits as candidate. Region/provider/billing choices block their dependent real adapters and public promises, rather than all portable work.

H00 records product choices; H01 proves topology/runtime. The Node/PostgreSQL/private object/KMS design and the pilot Worker/D1/R2 design are candidates until resolved. Keep optional server-readable consent, independent writer/owner/agent authority, purpose/recipient restrictions and local account-free operation as fixed requirements. Do not widen pilot credentials or treat a product URL as a tested connector.

## Decomposition cuts

| Design coverage | Bounded child outcomes | Dependency and acceptance |
| --- | --- | --- |
| H00–H02/C18–C22 | One policy decision; enrollment/manifest/receipt draft; grant/issuer contract; scope/frontier/erasure contract | Named decision authority, exact provenance, synthetic positive/negative cases; accepted versions/limits before public producers. |
| H03/O12 | Reserve; chunk receive; authenticate/verify; seal; transaction/receipt; reconcile; projection outbox | Invisible staging, complete authentication unit, tenant/source/grant binding, once-only quota, lost-response/crash/cancel tests. Objects and SQL are separate transactions. |
| H04/O13/C19 | One retained query adapter; snapshot/selection precedence; dedup; projection frontier; bounded raw range; reindex | Same Effect query/reducer/export functions, source/schema/coverage/freshness, narrow-original versus labeled-derivative authority and current per-page grants. |
| H05/O14/C20/C22 | One account/session/enrollment; one consent/revoke/recovery; portability; suppression; object purge; restore | Current account/grant authority, source-purpose admission, containing-artifact erasure, all copies/keys/indexes. Restore uses the latest authoritative suppression journal outside the old backup lineage. |
| H06/C21 | One exact client/auth/transport route | Muse, dots, Grok Bot and Pi Durable have separate package/product/plan/protocol/purpose/credential tests. Qualify expiry/renewal/revoke/restart and OAuth where applicable. |
| H07/V11–V13 | One provider fault; tenant isolation; current revocation; restore; erasure; regional inventory; load/cost; runbook | Actual deployed fingerprint and numerical budgets. Synthetic code cannot establish regional copies, recoverability or provider behavior. |
| H08 | Pilot archive migration; credential rebinding; cohort release; endpoint/resource decommission | Voluntary scope/coverage preview, digest receipts, retained legacy profiles, current consent and independent rollout/rollback evidence. |
| CI/V07–V09 | One workflow/path map; generator family; artifact fingerprint; cache budget; required-context transition | Stable fail-closed aggregates and affected producer/consumer triggers. Fork/local portable checks use no production credentials. |
| M08–M09 | One platform/channel upgrade/distribution; one profile authority promotion | Exact source/signers/contracts/state, physical and consumer evidence, retained engine pins, generally available release and rollback window. |
| M10/H09 | One proved Rust/duplicate path deletion; final no-Rust checkout/artifact verification | Qualified replacement, independent fixtures, retained-state recovery, finished promotion/window and compatible rollback. Historical source/tags/maps remain. |

## Security review and external-action gates

Require a reviewer independent of the implementation for crypto framing/ranges, tenant/grant authorization, durable commitment, deletion/restore and authority cutover. Verify negative/fault cases at each durable boundary. Agent output, titles and imported strings are data, never permission to invoke shell/SQL/network or widen a grant. Keep routine telemetry content-free and security audit restricted.

Provider staging, real-user enrollment, named-client connections, deployment, store release, production policy changes and destructive lifecycle operations are distinct task scopes. Prepare concrete code/configuration/diffs, synthetic checks and rollout/rollback artifacts first. Apply the user's actual authorization and relevant component procedures to the external action; a planning task or historical pilot approval is not authorization. Do not add approval stops to ordinary reversible implementation/review work.

One writer owns each contract/profile revision, SQL migration sequence, IAM/key/policy revision, workflow aggregate/path-map family and deployment configuration. Reader/ingest/lifecycle roles remain least-privilege even when sharing source. Rolling readers fail closed for current revocations/deletions; rollback cannot restore old access. Cloud, Practice, Wake, static website, pricing analytics and the existing broker retain separate data/service authority.

CI and retirement tasks include cloud registry/test/VM/Worker/container dependencies in addition to Apple/Android/CLI/website. Retire Cargo/UniFFI/native Rust/build/generation/publishing paths only after their consumers are admitted. Verify locked installs, actual shipped dependencies/SBOMs and clean supported builds with Rust tools absent. Cache cleanup covers scoped build outputs; user exports, spools, donor stores and unrelated worktrees are excluded.
