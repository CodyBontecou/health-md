# Health.md Practice v1 pilot protocol

- **Protocol version:** `1.0-draft.4`
- **Status:** Draft — founder input recorded; founder and pilot-practice approval pending
- **Draft input date:** 2026-08-06
- **Decision owners:** Health.md founder, Pilot Practice A, Pilot Practice B
- **Scope:** Blood-pressure document exchange through Health.md Practice on iPhone and Android
- **Related architecture:** [Shared Rust core ADR](../../architecture/adr-0001-shared-rust-uniffi-core.md), [deferred unified-v8 RFC](../../architecture/rfc-0002-unified-health-data-v8.md)

## Purpose

This document freezes the proposed first pilot behavior for Health.md Practice. It gives product,
clinical-workflow, mobile, portal, backend, privacy, and QA work one reviewable protocol before
implementation creates incompatible meanings.

The pilot is a **document-exchange workflow**, not a continuous-monitoring or emergency-response
service. Apple Health and Health Connect remain the measurement sources of truth. Health.md Practice
selects, normalizes, presents, and transmits source records for an explicit request; it does not let
a patient create or edit measurement values.

Normative terms such as **must**, **must not**, **should**, and **may** describe intended v1 behavior.
The protocol becomes accepted only after the approval gate at the end of this document is complete.

## Approval status

| Owner | Candidate commit SHA | Protocol ID/version | Common instruction ID/version | Applicable practice variant ID/version | Input status | Approval status | Approval date | Approver role | Evidence reference |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Health.md founder | — | `1.0-draft.4` | `practice-bp-common/1.0-draft.1` | not applicable | Input received 2026-08-06 | Pending | — | — | Founder answers informed this draft, but no protocol revision review or final approval is yet evidenced. |
| Pilot Practice A | — | `1.0-draft.4` | `practice-bp-common/1.0-draft.1` | Pending discovery | Pending interview | Pending | — | — | Use [`pilot-practice-discovery-and-approval.md`](pilot-practice-discovery-and-approval.md). |
| Pilot Practice B | — | `1.0-draft.4` | `practice-bp-common/1.0-draft.1` | Pending discovery | Pending interview | Pending | — | — | Use [`pilot-practice-discovery-and-approval.md`](pilot-practice-discovery-and-approval.md). |

No real-patient pilot may begin while any required approval is pending. Final approval applies only
when all three rows name the identical immutable candidate commit SHA, final protocol and common
instruction identifiers, and the applicable final practice variant or `none`.

## Recorded founder input — pending protocol approval

1. The product model must support pre-visit exchange, medication follow-up, and bounded recurring
   collection.
2. The pilot should support both iPhone and Android when qualification gates pass.
3. Requests may use fixed or relative periods and practice-configured collection schedules.
4. A practice configures submission cadence.
5. Collection follows the patient's device timezone; v1 fixes that timezone when the patient accepts
   a request so later travel cannot reinterpret prior expectations.
6. Apple Health and Health Connect remain the measurement sources of truth. Practice does not offer
   measurement-value entry or editing.
7. All readable blood-pressure sources are eligible. Manually entered source records are included and
   disclosed.
8. The report's primary presentation is the complete list needed to inspect a trend. It includes
   systolic, diastolic, and pulse when pulse can be associated without inventing a value or source
   relationship.
9. Practice-specific instruction templates may vary while sharing a common structured model.
10. V1 includes a clinician portal with manually provisioned accounts and MFA.
11. The workflow is document exchange only. It promises no clinical response or response time.
12. Patient identity defaults to patient-confirmed full name and date of birth, plus an optional
    practice reference or MRN.
13. A packet is available until 30 days after explicit acknowledgment, with a 90-day maximum while
    unacknowledged, subject to approved legal holds and final practice policy.
14. EHR integration must be standards-ready, but connector selection follows discovery of the actual
    pilot systems rather than an assumed universal interface.

## Pilot population and evidence policy

The proposed pilot contains two practices and a small, explicitly approved patient cohort. Exact
cohort size, enrollment criteria, and consent language remain compliance-gated rather than being
encoded in this product protocol.

Discovery, design review, fixtures, screenshots, demonstrations, tests, and training must use only:

- fictional people and practice identifiers;
- synthetic blood-pressure and heart-rate values;
- non-production tenants and credentials; and
- redacted workflow descriptions that cannot identify a patient.

Interview notes must not contain patient names, dates of birth, MRNs, appointment dates, screenshots,
exports, readings, or anecdotes specific enough to identify a patient. A practice may describe its
workflow abstractly, for example “our portal accepts PDF,” without sharing a patient document.

## Care contexts

A request declares one of these v1 contexts:

| Context | Purpose | Required bound |
| --- | --- | --- |
| `pre_visit` | Supply readings for a future visit | Fixed end or visit-relative end resolved to dates |
| `medication_follow_up` | Supply readings for a bounded follow-up episode | Explicit start/end and submission plan |
| `recurring_collection` | Repeated document exchange over a finite episode | Explicit end date; continued collection requires a successor request |

The context changes explanatory text and templates, not the meaning of a reading. It must not trigger
clinical interpretation, thresholds, or response promises.

The UI must use **recurring collection**, not “continuous monitoring,” until a separately approved
service defines staffing, alerts, response obligations, and clinical escalation.

### Recurring renewal

A renewal date is an expiration checkpoint, not automatic rollover. Continued collection requires:

1. an authorized clinician action before or after expiration;
2. a new immutable successor request with its own identifier and a reference to the prior request;
3. explicit start/end bounds, schedule, cadence, instructions, and identity requirements;
4. patient review and acceptance of the successor request; and
5. a newly captured acceptance-time device timezone.

Expiration stops future collection authority. A successor must not capture the expired gap
retroactively unless it separately and visibly requests a retrospective fixed period. The practice
must approve maximum episode duration, renewal lead time, authorized renewal role, and expiration
behavior. Changes to an active request use a revision only when they do not extend collection beyond
its accepted end; an extension uses a successor request and renewed patient acceptance.

## Collection period

A request supports:

- `fixed_dates`: explicit inclusive start date and exclusive end date; or
- `relative_completed_days`: a positive number of completed calendar days, resolved when the patient
  accepts the request.

At acceptance, the app must persist:

- the requested rule;
- the device's current IANA timezone;
- inclusive local start and exclusive local end dates; and
- resolved half-open UTC bounds `[start, end)`.

Regeneration must use those saved bounds. It must not reevaluate “today” or silently reinterpret the
period in a new timezone.

### Timezone changes and travel

The acceptance-time timezone remains fixed for the request. Source instants and source offsets remain
available for provenance. If the patient relocates or intentionally wants the schedule to follow a
new timezone, the app may offer an explicit effective-date change. That action creates a new request
schedule revision and new resolved slots; it does not rewrite earlier periods.

Daylight-saving gaps and overlaps must be resolved deterministically and materialized as UTC bounds
before readings are assigned. The language-neutral request contract will define the exact resolution
rule and fixtures.

## Collection templates

The portal offers these structured templates. Practices may save approved variants.

| Template | Meaning | Required configuration |
| --- | --- | --- |
| `all_readings` | Include every eligible reading in the period | Period only |
| `once_daily` | Expect a minimum count in one daily window | Named window, start/end local time, minimum count |
| `morning_evening` | Expect readings in two non-overlapping daily windows | Two named windows and minimum count per window |
| `custom_windows` | Expect readings in one or more named windows | Explicit non-overlapping windows and minimum counts |

The system must retain every qualifying source reading. It must not select one “best” reading,
deduplicate by similar values/times, average nearby readings into an inferred session, or hide extra
readings after a slot's minimum is satisfied.

The practice must explicitly approve its production window times and minimum counts. Suggested UI
values are not a clinical default until approved. A request with overlapping or ambiguous windows
must fail validation.

Slot presentation uses neutral language:

- `satisfied`;
- `underfilled`;
- `no_qualifying_reading_found`; or
- `indeterminate_due_to_partial_capture`.

The product must not label a patient compliant or non-compliant.

## Submission cadence

A practice chooses one bounded cadence:

- `at_period_end`;
- `daily`;
- `weekly`;
- `every_n_days`; or
- `patient_initiated`.

“Immediately after each reading” is not a v1 guarantee. Apple and Android background execution and
source synchronization may delay observation. Scheduled work is best effort, and the patient must be
able to submit manually.

Each original cadence slot covers an explicit, non-overlapping submission period within the request.
It produces an immutable packet. A correction or recapture must have bounds exactly equal to the
packet it supersedes and must identify that packet. It must not partially overlap any cadence slot or
packet; overlap is valid only when the bounds exactly equal the identified superseded packet. A
revision never mutates bytes already made available to a practice.

## Source-of-truth and eligible records

Apple Health and Health Connect are the only measurement-value sources for v1.

Health.md Practice must not:

- offer fields for entering or editing systolic, diastolic, or pulse values;
- silently write corrected values back to HealthKit or Health Connect;
- claim that source metadata proves a cuff is clinically validated; or
- reconstruct blood-pressure pairs from independent daily averages.

If a patient needs to correct a measurement, the UI directs them to the upstream health source. A
subsequent Practice packet is a new immutable revision.

All readable sources are eligible. The packet discloses the platform source and recording-method
evidence. Manual records remain included and are labeled without overstating absent metadata:

- `manual`;
- `not_marked_manual`;
- `automatic_or_device_recorded`; or
- `unknown`.

An empty successful Apple Health query must not be described as proof that the patient had no
readings, because unavailable read authorization can appear empty.

## Blood-pressure and pulse rows

One report row represents one source-backed paired blood-pressure measurement:

- observation date/time in the fixed request timezone;
- systolic value and `mmHg`;
- diastolic value and `mmHg`;
- associated pulse and `beats/minute` when available;
- source/manual disclosure; and
- assigned request window, when applicable.

On Apple, the authoritative pair comes from a blood-pressure HealthKit correlation and its component
relationships. On Android, it comes from one Health Connect blood-pressure record. Daily summary
averages must not be used to manufacture a pair.

### Pulse association

Apple and Android store heart rate separately from the blood-pressure pair in the currently inspected
source models. V1 may propose an association only when a heart-rate source record:

1. comes from the same source application identity as the blood-pressure record;
2. is within plus or minus 120 seconds;
3. participates in a unique deterministic one-to-one match; and
4. is confirmed by the patient as coming from the same measurement.

Exact timestamps are preferred. Ties, ambiguity, cross-source matches, or reuse of one heart-rate
record must produce no candidate. Confirmation associates two existing source records; it never
changes either value.

The report must distinguish:

- source-declared association, if a future source explicitly supplies one;
- patient-confirmed same-source nearby heart rate; and
- no associated pulse available.

A missing pulse does not invalidate an otherwise valid BP packet. Pulse coverage is reported
separately, including when HR permission or source data is unavailable.

This pulse policy requires explicit practice review because it affects how the third requested value
is interpreted.

## Patient identity

The v1 packet supports:

- patient-confirmed full name;
- patient-confirmed date of birth;
- optional practice-supplied patient reference or MRN;
- request and patient-practice relationship identifiers; and
- identity provenance (`practice_supplied`, `patient_confirmed`, or `unverified`).

The practice must confirm which fields are required to attach a document safely to its chart. Names,
dates of birth, MRNs, relationship IDs, and health dates must not appear in invitation URLs, email
subjects, general analytics, public logs, or notification bodies.

## Instructions

Each practice owns versioned patient-facing collection instructions. The portal should provide the
exact [`v1-common-patient-instructions.md`](v1-common-patient-instructions.md) starting template and
constrained customization. It must display the exact rendered instructions before request issuance
and again before patient acceptance. A request records the instruction template and variant IDs and
versions that were reviewed.

V1 must not accept arbitrary HTML. Any free text permitted after security and clinical review must be
length-bounded, plain text, safely escaped, and treated as PHI-capable content. Template changes apply
to new request revisions, not already accepted requests.

The practice interview must establish whether both practices can use the same template or require
approved variants.

## Clinician roles

The proposed minimum roles are:

- `practice_admin`: manage clinician access, practice templates, retention settings, and audit access;
- `clinician`: create requests, access authorized submissions, download documents, and explicitly
  acknowledge receipt.

All clinician accounts are manually provisioned for the pilot and require MFA or passkeys. Shared
accounts are prohibited. Pilot-practice interviews must confirm role names and whether request
creation or acknowledgment needs narrower permissions.

## Report and document expectations

The clinician report always contains the complete reading list. Presentation adapts without removing
rows:

- small set: neutral summary and complete table;
- medium set: neutral summary, trend chart, and complete table;
- large set: neutral summary and trend chart followed by a paginated complete appendix.

Neutral summary content may include pair count, represented days, satisfied/underfilled slots,
systolic/diastolic mean and observed marginal minimum/maximum, pulse coverage, and source/manual
counts. It must not include guideline stages, alert colors, diagnosis, treatment advice, inferred
adherence, or averages of daily averages.

V1 provides a print-ready PDF and canonical versioned packet JSON. Whether a practice also needs CSV,
a particular portal import format, or structured FHIR observations is an explicit discovery item.
Email and SMS may contain only a generic notice to authenticate; they must not carry the PDF, health
values, patient identity, health dates, or a bare authorized artifact link.

## Portal and integration baseline

V1 includes a standalone Health.md Practice portal with:

- manually provisioned MFA clinician accounts;
- practice-scoped patient relationships;
- request templates and constrained custom requests;
- generic invitation/QR delivery;
- submission inbox and report viewer;
- PDF and canonical packet download;
- explicit acknowledgment; and
- practice-scoped audit and retention controls.

The pilot does not assume a universal patient-portal or EHR write interface. The implementation will
remain standards-ready for FHIR R4 and SMART/vendor adapters, but connector priority follows the
actual pilot systems and enabled operations. Candidate market products are not a substitute for
practice discovery.

Manual PDF attachment remains the v1 fallback. No PHI-bearing PDF is sent as an ordinary email
attachment.

## Workflow truth and engagement

The server may establish these distinct facts:

- `submitted`: immutable packet storage and request binding succeeded;
- `opened`: an authorized clinician rendered or downloaded the report;
- `engaged`: the report was visibly active for a coarse duration bucket;
- `acknowledged`: a clinician explicitly confirmed receipt; and
- `reviewed`: a clinician explicitly made a separately worded review attestation, if the practice
  enables that state.

Elapsed time must never automatically produce `acknowledged` or `reviewed`. A page can be idle,
backgrounded, printed, read with assistive technology, or opened without clinical review.

The patient-facing product promises document exchange only. It provides no response SLA and directs
patients to normal practice and emergency channels for time-sensitive concerns.

## Retention baseline

Subject to legal/compliance and practice approval:

- a packet remains available until 30 days after explicit acknowledgment;
- an unacknowledged packet remains available for at most 90 days;
- revocation or approved deletion removes the active packet promptly;
- backup copies expire through a documented rotation, initially targeted at 35 days;
- metadata and audit retention are governed separately by approved practice/legal policy; and
- legal holds suspend normal deletion with an auditable policy receipt.

This service should remain an exchange layer rather than the authoritative longitudinal medical
record. A practice's imported EHR copy follows that practice's retention policy.

## Explicit v1 non-goals

The pilot must not implement or imply:

1. continuous or real-time monitoring;
2. emergency detection, escalation, or response;
3. threshold alerts or automated triage;
4. diagnosis, prognosis, causation, or risk classification;
5. medication recommendations or treatment changes;
6. a promised clinician-response or review SLA;
7. inferred acknowledgment or review from time-on-page;
8. patient-clinician messaging, comments, or care-plan negotiation;
9. measurement-value entry or editing in Health.md Practice;
10. source-device certification or accuracy claims;
11. an authoritative longitudinal patient chart;
12. unrestricted multi-metric request design;
13. automatic EHR writes before a connector is separately qualified;
14. ordinary-email delivery of packet attachments; or
15. changes to Apple `healthmd.health_data` v7, Android frozen v4, Android analytical v5, or the
    deferred unified-v8 contract.

Any proposed exception requires a new reviewed decision, explicit clinical/security analysis, and an
appropriate protocol version or revision.

## Open deviation register

Every unresolved practice-specific choice is listed here rather than hidden in prose or assumed from
market norms.

| ID | Decision needed | Baseline proposal | Practice A | Practice B | Owner | Required before |
| --- | --- | --- | --- | --- | --- | --- |
| `PRACTICE-01` | EHR product/version and enabled API | Standalone portal plus manual PDF fallback | Pending | Pending | Practice integration owners | Connector selection |
| `PRACTICE-02` | Patient-portal/document-ingest capability | PDF download/import; canonical JSON retained | Pending | Pending | Practice operations | Pilot workflow approval |
| `PRACTICE-03` | Default request templates | All, once daily, morning/evening, custom | Pending | Pending | Clinical owners | Production template creation |
| `PRACTICE-04` | Exact daily windows and minimum counts | Practice must specify; no hidden clinical default | Pending | Pending | Clinical owners | Schedule issuance |
| `PRACTICE-05` | Default submission cadence | Practice selects bounded cadence | Pending | Pending | Clinical owners | Request-template approval |
| `PRACTICE-06` | Instruction wording | Exact common `practice-bp-common/1.0-draft.1` text plus an approved versioned practice variant | Pending | Pending | Clinical owners | Patient-facing approval |
| `PRACTICE-07` | Clinician permissions | Admin and clinician baseline | Pending | Pending | Practice admins | Account provisioning |
| `PRACTICE-08` | Identity matching | Full name, DOB, optional practice reference/MRN | Pending | Pending | Privacy/operations | Pilot enrollment |
| `PRACTICE-09` | Report/document formats | PDF plus canonical JSON | Pending | Pending | EHR/operations | Report approval |
| `PRACTICE-10` | Pulse interpretation | Same-source +/-120s unique match with patient confirmation | Pending | Pending | Clinical owners | Pulse feature qualification |
| `PRACTICE-11` | Retention and legal holds | 30 days after acknowledgment; 90-day maximum | Pending | Pending | Privacy/legal owners | Real-PHI launch |
| `PRACTICE-12` | Meaning of acknowledgment/review | Explicit receipt; review requires separate attestation | Pending | Pending | Clinical/operations | Workflow approval |
| `PRACTICE-13` | Recurring renewal | Finite request; clinician-created successor and patient reacceptance; no automatic rollover | Pending | Pending | Clinical owners | Recurring pilot |
| `PRACTICE-14` | Structured EHR requirement | Discover first; no automatic write in initial baseline | Pending | Pending | Integration owners | EHR scope decision |

A deviation is resolved only through this resolution ledger. Keep the row in the open register until
its status is incorporated or accepted as a scoped practice variant.

| ID | Practice | Affected contexts / Path IDs | Approved value | Disposition | Blocks pilot or scoped workflow | Excluded scope | Scope-exclusion evidence | Protocol revision reviewed | Approver role | Approval date | Evidence reference | Incorporated revision |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| — | — | — | — | Pending interviews | — | — | — | — | — | — | — | — |

Allowed dispositions are `baseline accepted`, `incorporated`, `scoped variant accepted`, and
`blocking`. `Incorporated revision` is required only when approved input changed the protocol;
`Protocol revision reviewed` always records the exact text the approver evaluated.

A `blocking` row must state whether it blocks the complete pilot or named scoped workflows, identify
the exact excluded contexts and Path IDs, and reference evidence that those scopes were excluded.
Exclusion cannot leave any in-scope context without at least one selected document path that passed
every required fictional ingest-test step.

A disagreement may remain an explicit per-practice variant when it does not change packet meaning or
safety. A disagreement that changes semantics must produce a versioned contract decision rather than
runtime free text. Every approval and resolution must identify the exact reviewed protocol revision.

## Pilot exit evidence

Before real-patient enrollment, the owners must provide evidence that:

- both practices reviewed a fictional complete, partial, empty, manual-source, and missing-pulse
  report;
- both practices approved their template windows, cadence, exact versioned instruction text, identity fields, roles,
  document path, acknowledgment meaning, and retention policy;
- every in-scope care context is mapped to at least one selected portal/EHR Path ID, and at least one
  mapped path per context passed the complete authorization, retrieval, acceptance-evidence,
  structured-import-if-required, and test-document-cleanup rule in the discovery guide;
- every selected portal/EHR ingest path was verified with the pinned
  [`practice-ingest-test-v1`](fixtures/README.md) fictional PDF, with a dated evidence reference and
  exact fixture SHA-256; an `unknown`, omitted, partially run, or non-passing result blocks that path;
- Apple and Android produce equivalent Practice meaning from synthetic source records while retaining
  platform provenance;
- the portal flow works with fictional identities and no PHI in email, URLs, analytics, or logs;
- document-exchange/no-monitoring language appears in the clinician and patient flows;
- compliance/security launch gates are complete; and
- every open deviation is resolved, explicitly accepted as a scoped per-practice difference, or
  blocks the affected pilot workflow.

## Change control

While discovery is pending, revisions use `1.0-draft.N`. Any semantic change updates this document's
version and decision record.

Before requesting final approval, the owners must:

1. resolve or explicitly block every deviation;
2. assign the intended final protocol identifier/version `1.0` and common instruction identifier/version
   `practice-bp-common/1.0`;
3. assign final versioned IDs to each practice instruction variant;
4. set status to **Approval candidate** without changing the intended normative text afterward; and
5. commit that complete candidate, do not amend or replace it, and record its full Git commit SHA in
   governed approval evidence outside the candidate commit.

The founder and both practices approve the same immutable candidate commit and explicitly name the
full SHA, protocol `1.0`, common instructions `practice-bp-common/1.0`, and each applicable final
practice-variant ID/version or `none`. After all approvals exist, a later acceptance-only commit
copies the SHA, identifiers, approval status, dates, roles, and governed evidence references into the
approval table. That acceptance commit must not change normative content or identifiers. Any
normative change after candidate approval invalidates those approvals and requires a new candidate
commit.

After acceptance:

- editorial corrections that do not change meaning may increment a document revision;
- collection, pulse, timezone, identity, workflow, retention, or non-goal changes require explicit
  owner review; and
- request/packet wire changes follow their independent contract versioning and fixture policy.
