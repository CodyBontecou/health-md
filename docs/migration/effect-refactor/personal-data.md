# Personal data, acquisition and donor tasks

Read this branch for P01–P03, L00–L05, S00–S06, C14–C17 and O08–O11. The [product/domain reference](../../architecture/javascript-unified-layer-design-reference.md#one-product-for-health-location-and-screen-time) preserves source-specific semantics and history requirements. Common domain IDs/profile names remain proposed until their contracts are reviewed.

## Start with sources and contracts

Separate location, Mac usage and mobile usage audits record candidate donor revisions/patches/licenses. `BASE-DOMAINS` reconciles their feature/state/egress maps; accepted source selection is recorded under Q-DONOR-SOURCE before import. Donor files/databases/user data and services are separate authorities: inspect source without importing live records or adopting dirty patches. Record exact source/rewrite maps before importing code.

`PERSONAL-CONTRACT-DRAFT` defines bounded identity/time/provenance/coverage/detail/selection and one summary/record fixture per domain. `PERSONAL-CONTRACT-REVIEW` resolves that scoped candidate before the combined synthetic slice. These tasks do not establish mobile capture/export eligibility. Reuse Health.md health profiles and complete operations; keep the existing native health corpus authoritative.

## Decompose by source and outcome

| Design coverage | Bounded child tasks | Required evidence |
| --- | --- | --- |
| P01/C14 | Tagged codecs; source catalog; coverage; scoped repository transaction; correction/tombstone; retention | Exact source precision/identity and observed/aggregate/inferred meanings; protected data, replay/crash/rollback. One logical dataset need not be one physical store. |
| P02/C15–C16/O08–O09 | One source-aware query; one reducer; one combined/selected summary renderer; record/archive manifest; one schedule occurrence | Explicit overlap/source/detail grants, strict/partial behavior, frozen request/profile/accounting and bounded streams. No three independent export engines/jobs. |
| L00/L01 | Source inventory; iOS point inbox; Android point inbox by channel; native checkpoint; pure outlier/visit/correction/outing algorithm | Physical background/permission/accuracy/battery proof and provenance. CLVisit, inferred stays and watch counters retain distinct identities. |
| L02 | One visit correction/Undo; saved-place model; bounded map adapter; photo-reference adapter | Preserve raw facts and certainty; inference/network geocoding and native asset authorization stay explicit. |
| L03 | Independent watch batch/ack; phone receiver; Stop Live Activity route; one intent | Phone absent/offline/reboot/retry/dedup/revoke and old/new identity/queue fixtures. |
| L04/L05 | One donor format renderer; enrolled webhook/destination; schedule handoff; installed-user transition | Exact format/order/units/merge and secret rebinding; authenticated routing; no automatic retransmission. |
| S00/S02 | Mac app-transition/checkpoint; device state; idle derivation; separate focused-title adapter | Full observed short-session retention, unknown crash boundaries and all available donor history; supported signed channel/API and title exclusions before persistence. |
| S01 | iOS historical aggregate reconciliation; eligible data-access adapter; standard display-only report; Android UsageEvents checkpoint | Production entitlement/purpose/region/account/authorization/destination evidence; source lookback/gaps and historical buckets. Development signing is not qualification. |
| S03 | Paged full-history model; aggregate reducer; category assignment; title detail | No daily/hourly duplication, false exact iOS sessions or cross-device double count. Missing title is distinct from empty title. |
| S04/P03/C17/O11 | One complete donor archive; bounded validator; staging/import/conflict transaction; Undo; source handoff | Original IDs/precision/settings/annotations/categories/queues, repeat/crash recovery and no snapshot echo. Preserve donor data/readers and explicit support/entitlement transition. |
| S05/S06 | Later Windows/Linux collector research; required exact iOS-session feasibility follow-up | Keep concrete owners and milestones. Initial labeled iOS aggregates satisfy the accepted exception; exact sessions remain open. |

## History and authority gates

Retain all future observed macOS sessions, including short sessions, and import all available retained donor history beyond summary windows. Missing/discarded/pre-collector/clock/crash-tail data cannot be reconstructed as exact sessions. iOS ships the available historical aggregates honestly; the standard report sandbox and eligible export path have different authority. Deferred browser/input acquisition stays excluded, including browser window titles under the current design default.

Validate source-purpose/destination policy before materialization, transfer or cloud use. Source permissions cannot be granted from a CLI flag. Domain/detail/capture controls, local querying, exportability and external-agent sharing are separate capabilities. A donor's analytics, commerce, CloudKit/Worker wiring or release channel does not transfer with code.

Cross-platform contract tasks inspect both producers and every consumer, classify equivalence truthfully, pin independently versioned profiles and retain frozen health bytes. Native and physical admission tasks follow the corresponding source contract; repository/renderer implementation does not qualify acquisition. P03 cannot close until the complete retained-state/import/rollback matrix passes for each accepted donor.
