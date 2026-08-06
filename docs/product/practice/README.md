# Health.md Practice product decisions

This directory contains the product and workflow decisions that must be approved before Health.md
Practice handles real patient information.

## Current artifacts

- [`v1-pilot-protocol.md`](v1-pilot-protocol.md) — versioned BP document-exchange protocol, recorded
  founder input, non-goals, approval gate, and open deviation register.
- [`v1-common-patient-instructions.md`](v1-common-patient-instructions.md) — exact versioned common
  operational/no-monitoring text for practice review and constrained variants.
- [`pilot-practice-discovery-and-approval.md`](pilot-practice-discovery-and-approval.md) — structured,
  PHI-prohibiting interview and approval guide for Pilot Practice A and Pilot Practice B.
- [`pilot-ehr-vendor-discovery-aid.md`](pilot-ehr-vendor-discovery-aid.md) — dated, non-normative
  official-source aid for disambiguating candidate EHRs without assuming tenant capability.
- [`fixtures/`](fixtures/README.md) — deterministic PHI-free PDF and generator for verifying the actual
  portal/EHR document path selected by each practice.

## Current status

`v1-pilot-protocol.md` is `1.0-draft.3`.

Founder decision input has been incorporated, but final founder approval and both practice approvals
are pending. The protocol must not be relabeled accepted and the pilot must not use real PHI until the
approval table and deviation register are complete for the same reviewed revision.

## Completion procedure

1. Interview Practice A and Practice B using the discovery guide and fictional examples only.
2. Identify each practice's actual EHR/patient portal and document-ingest capabilities.
3. Record exact template windows, counts, cadence, versioned instruction text, roles, identity
   matching, document formats, acknowledgment meaning, pulse policy, retention, and
   recurring-renewal choices.
4. Copy every deviation into the protocol's open deviation register.
5. Incorporate approved decisions in a new `1.0-draft.N` revision and verify each selected document
   path with the pinned [`practice-ingest-test-v1`](fixtures/README.md) fictional PDF; `unknown` blocks
   that path.
6. Resolve or explicitly block deviations, then assign final protocol `1.0`, common instruction
   `practice-bp-common/1.0`, and practice-variant versions.
7. Commit the complete **Approval candidate** and record its Git commit SHA.
8. Obtain founder, Practice A, and Practice B approval naming that same commit and exact identifiers.
9. Record governed approval evidence without adding patient data.
10. Change only status and approval evidence to **Accepted** in a reviewed commit. Any normative change
    requires a new candidate and new approvals.

Practice-specific differences may remain only when the protocol explicitly identifies them and they
do not create ambiguous packet meaning or weaken a launch gate. Semantic differences require a
versioned contract decision.

## Data hygiene

These artifacts must never contain real patient names, dates of birth, MRNs, readings, appointment
dates, exports, screenshots, portal messages, or production credentials. Use abstract workflow facts,
fictional fixtures, practice aliases, and approver roles.
