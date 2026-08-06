# Health.md Practice pilot discovery and approval guide

- **Template version:** `1.0-draft.2`
- **Related protocol:** [`v1-pilot-protocol.md`](v1-pilot-protocol.md)
- **Purpose:** Collect Practice A and Practice B workflow decisions without collecting real patient data

## Safety rules for the interview

The interviewer must begin by asking participants not to share:

- patient names, dates of birth, MRNs, contact details, appointment dates, or account identifiers;
- real readings, exports, reports, screenshots, portal messages, or medical-record excerpts;
- patient-specific clinical histories, medications, diagnoses, or anecdotes that could identify a
  person; or
- production credentials, URLs containing tokens, security answers, or access instructions.

Use fictional examples and abstract workflow descriptions only. Do not record the session unless a
separately approved process permits it. Store the completed artifact in the approved project location;
do not paste answers into general analytics, issue trackers, or public chat.

If PHI is disclosed accidentally, stop note-taking, follow the incident/escalation process, and do not
copy the disclosure into this template.

## Interview metadata

Record roles and organizational context, not unnecessary personal identifiers.

```text
Practice alias: Practice A | Practice B
Interview date:
Participant roles represented:
Clinical approval role present: yes | no
Operations approval role present: yes | no
Privacy/security approval role present: yes | no
EHR/integration role present: yes | no
Protocol draft reviewed: 1.0-draft.2
Interviewer:
```

## 1. Pilot workflow

1. Which v1 contexts will this practice pilot?
   - [ ] Pre-visit document exchange
   - [ ] Medication follow-up
   - [ ] Bounded recurring collection
2. For each selected context, what event starts the request?
3. Who is allowed to create, cancel, renew, and acknowledge a request?
4. Is acknowledgment only confirmation of receipt?
5. Does the practice require a separate explicit “reviewed” attestation?
6. Confirm that the pilot promises no response time, active monitoring, threshold alert, or emergency
   escalation.

Structured decision:

```text
Contexts:
Request creators:
Request cancellers/renewers:
Maximum recurring episode/request duration:
Renewal lead time:
Patient reacceptance of successor required: yes | no
Expiration behavior:
Successor request/reference semantics approved: yes | no
Acknowledgment meaning:
Review attestation enabled: yes | no
Document-exchange/no-response language approved: yes | no
Deviation from protocol:
```

## 2. Existing systems and document path

Do not demonstrate a real patient chart or message.

1. EHR product, edition/version, and deployment model, if known.
2. Patient-portal product, if separate.
3. Does the portal accept patient-uploaded PDF files?
4. Can staff attach a downloaded PDF to the EHR?
5. Are CSV, JSON, or structured observations required for the pilot?
6. Which FHIR version, SMART authorization mode, and read/write resources are enabled, if known?
7. Does integration require a vendor marketplace agreement, sandbox qualification, interface engine,
   VPN, Direct Secure Messaging, or another process?
8. What evidence tells the practice that a document was accepted by its system?

Structured decision:

```text
EHR product/version:
Patient portal:
Patient PDF upload: yes | no | unknown
Staff PDF attachment: yes | no | unknown
Required pilot formats: PDF | JSON | CSV | structured FHIR | other
Enabled integration capabilities:
Vendor onboarding prerequisites:
Pilot fallback document path:
Capability verification: synthetic test | unknown
Verification date:
Synthetic-test evidence reference:
Practice attestation reference, supplemental only:
Synthetic PDF upload/attachment result: passed | failed | not supported | not run
Structured-import result: passed | failed | not required | not run
If structured import is not required, rationale:
Integration owner role:
Does an unknown verification result block this path: yes | no
Deviation from protocol:
```

## 3. Request templates and windows

Review each template using fictional dates and values.

### All readings

```text
Enabled: yes | no
Default period: fixed | previous 7 | previous 14 | previous 30 | other
Submission cadence:
```

### Once daily

```text
Enabled: yes | no
Window name:
Local start time:
Local end time:
Minimum readings per window:
Default period:
Submission cadence:
```

### Morning and evening

```text
Enabled: yes | no
Morning local start/end:
Morning minimum count:
Evening local start/end:
Evening minimum count:
Default period:
Submission cadence:
```

### Custom windows

```text
Enabled: yes | no
Who may create custom windows:
Maximum windows per day:
Maximum request duration:
Allowed submission cadences:
Additional validation rules:
```

Confirm explicitly:

- [ ] Every qualifying source reading remains in the report.
- [ ] Extra readings are not hidden after a minimum is met.
- [ ] Nearby readings are not averaged into inferred sessions.
- [ ] Missing slots use neutral language, not compliance judgments.
- [ ] Recurring collection has a finite end; continued collection requires a clinician-created successor and patient reacceptance.
- [ ] Immediate after-reading delivery is not guaranteed.

## 4. Timezone and travel

Review the acceptance-time timezone policy:

1. Request acceptance captures the patient's current device IANA timezone.
2. That timezone remains fixed for the request.
3. Source instant/offset remains available as provenance.
4. An intentional timezone change creates a new effective-dated schedule revision.
5. Prior slot interpretation is not rewritten.

```text
Policy approved: yes | no
Requested deviation:
Clinical reason for deviation, without patient example:
```

## 5. Data sources, manual records, and corrections

Confirm:

- [ ] Apple Health and Health Connect are the only v1 measurement-value sources.
- [ ] Health.md Practice does not let patients type or edit BP/pulse values.
- [ ] All readable BP sources are included.
- [ ] Manual source records are included and labeled.
- [ ] Unknown recording method is labeled unknown rather than automatic.
- [ ] Source/device metadata is not presented as cuff certification.
- [ ] Corrections occur upstream and create a new immutable packet revision.
- [ ] Empty Apple Health results do not prove the patient had no readings.

```text
Required source-display fields:
Any excluded source categories:
Correction workflow approved: yes | no
Deviation from protocol:
```

An exclusion based on a source name requires separate evidence and a maintained source policy; do not
create an informal allowlist during the interview.

## 6. Pulse association

Use a synthetic example to explain that current Apple and Android BP records do not necessarily link
the separate HR record.

Review the proposed v1 rule:

- same source application identity;
- within plus or minus 120 seconds;
- unique deterministic one-to-one candidate;
- patient confirms that the existing HR and BP records came from the same measurement;
- ties, ambiguity, cross-source matches, or reuse produce no candidate; and
- missing pulse does not invalidate BP data.

```text
Policy approved: yes | no
Pulse requested by default: required | preferred | not requested
Preferred report label for confirmed candidate:
How should missing pulse be displayed:
Requested tolerance change:
Clinical rationale, without patient example:
Deviation from protocol:
```

A requested tolerance or automatic-association change remains open until the shared contract and
clinical/security review approve it.

## 7. Patient identity matching

Review the minimum proposal:

- patient-confirmed full name;
- patient-confirmed date of birth;
- optional practice-supplied reference or MRN;
- request/relationship ID; and
- identity provenance.

```text
Full name required: yes | no
Date of birth required: yes | no
Practice reference/MRN available at request creation: always | sometimes | no
Additional field requested:
Why the additional field is minimum necessary:
Who resolves mismatches:
Can a mismatched submission be quarantined safely: yes | no
Deviation from protocol:
```

Do not enter a real name, date of birth, MRN, or example identifier in this artifact.

## 8. Patient instructions

Review the exact [`v1-common-patient-instructions.md`](v1-common-patient-instructions.md) text using
fictional dates and a fictional practice name. Record requirements, not patient-specific
instructions. If a practice variant is required, prepare its exact text in the governed template
record and review the complete rendered result rather than approving a summary.

```text
Common template ID/version reviewed: practice-bp-common/1.0-draft.1
Common exact text approved: yes | no
Practice-specific variant needed: yes | no
Practice variant ID/version:
Exact variant text or governed evidence reference:
Complete rendered text approved: yes | no
Clinical approver role:
Required preparation/positioning/cuff instructions:
Required contact/no-response wording:
Maximum custom text needs:
Translation/localization needs:
Accessibility/reading-level needs:
Approval date:
Approval evidence reference:
Deviation from protocol:
```

Confirm that instructions are versioned, plain text, bounded, escaped, previewed before issuance, and
frozen when accepted.

## 9. Report and trend presentation

Review fictional reports representing small, medium, large, complete, partial, empty, manual-source,
and missing-pulse cases.

Confirm desired content:

- [ ] Complete reading list
- [ ] Request-local date/time
- [ ] Systolic and diastolic with `mmHg`
- [ ] Associated pulse with provenance label when available
- [ ] Source/manual disclosure
- [ ] Requested window
- [ ] Pair count and represented days
- [ ] Slot coverage/missing status
- [ ] Neutral mean and observed marginal minimum/maximum
- [ ] Trend chart for larger sets
- [ ] Limitations and empty/partial-capture language

```text
PDF required: yes | no
Canonical JSON useful: yes | no
CSV required: yes | no
Structured observations required for pilot: yes | no
Maximum useful report size/pages:
Source/device detail preference:
Chart/table changes:
Terminology changes:
Deviation from protocol:
```

Confirm no guideline stages, alert colors, diagnosis, treatment advice, inferred adherence, or hidden
rows.

## 10. Accounts, access, acknowledgment, and engagement

Review proposed pilot roles and manually provisioned MFA/passkey accounts.

```text
Practice admin capabilities approved:
Clinician capabilities approved:
Additional/restricted role needed:
Who approves account creation:
Who performs access review:
Who may download:
Who may acknowledge:
Who may explicitly attest reviewed:
Shared accounts prohibited: yes | no
Deviation from protocol:
```

Confirm:

- [ ] Opening is not acknowledgment.
- [ ] Time-on-page is an engagement metric only.
- [ ] Acknowledgment requires an explicit clinician action.
- [ ] Review requires a separate explicit attestation if enabled.
- [ ] No patient-facing response SLA is promised.

## 11. Notifications

```text
Invitation channel:
Clinician notification channel:
Generic wording approved: yes | no
Notification owner:
Delivery-failure escalation:
Deviation from protocol:
```

Confirm that notifications contain no patient identity, health date, value, attached PDF, or bare
authorized artifact link.

## 12. Retention, deletion, and legal hold

Review the starting proposal:

- packet deletion 30 days after explicit acknowledgment;
- unacknowledged packet maximum 90 days;
- prompt active deletion after approved revocation/deletion;
- backup expiry through documented rotation, initially targeted at 35 days;
- separately approved metadata/audit retention; and
- auditable legal holds.

```text
30-day post-acknowledgment approved: yes | no
90-day unacknowledged maximum approved: yes | no
Backup expiry target approved: yes | no
Metadata retention:
Audit retention:
Legal-hold authority:
Patient deletion workflow owner:
Practice termination/export workflow:
Deviation from protocol:
```

Retention is not accepted by relying on a generic “industry standard.” The practice and Health.md
legal/privacy owners must approve exact policy.

## 13. Support, incident, and pilot readiness

```text
Practice operational owner role:
Health.md support contact/process approved: yes | no
Security incident contact/process approved: yes | no
Safe support workflow without packet access approved: yes | no
Criteria to pause the pilot:
Expected staff training:
Requested pilot cohort size:
Requested pilot duration:
```

Cohort answers must be counts and eligibility rules only, never patient identities.

## Deviation summary

Copy every non-empty deviation into the protocol's open deviation register. Do not resolve a
disagreement informally in free-form notes.

| Protocol deviation ID | Practice decision | Owner role | Required evidence | Blocks pilot? |
| --- | --- | --- | --- | --- |
| | | | | |

## Practice approval

Approval is role-based evidence; this repository document should not collect unnecessary signatures,
credentials, or personal contact details. Link to the approved organizational record if signatures
are stored in a governed system.

```text
Practice alias:
Protocol version reviewed:
Clinical workflow approved by role:
Operations/document path approved by role:
Privacy/security/retention approved by role:
Integration assumptions approved by role:
Approval date:
Approval evidence reference:
Exceptions/deviations accepted:
Status: approved | approved with listed deviations | not approved
```

The interviewer then updates the protocol approval table and deviation register in a reviewed commit.
An `unknown` document-path capability blocks that workflow until a fictional document test verifies
it. A governed practice attestation may supplement the test but cannot replace it.

After discovery changes are incorporated, the owners prepare the final-version approval candidate
and commit it. The founder and both pilot practices must approve the same candidate commit SHA and
name the exact protocol, common instruction, and applicable practice-variant versions. Acceptance may
change only status and approval evidence; any normative change requires a new candidate and new
approvals.
