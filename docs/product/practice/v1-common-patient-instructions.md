# Health.md Practice v1 common patient instructions

- **Template ID:** `practice-bp-common`
- **Template version:** `1.0-draft.1`
- **Status:** Draft — founder and pilot-practice approval pending
- **Related protocol:** [`v1-pilot-protocol.md`](v1-pilot-protocol.md)

## Purpose

This is the exact common operational text shown in the request preview and patient acceptance flow.
It deliberately does not prescribe measurement technique; each practice must supply and clinically
approve any positioning, rest, cuff, repeat-measurement, or contact instructions in a separately
versioned practice variant.

The renderer substitutes only the defined, structured variables. Bracketed annotations below define
rendering behavior and are not displayed.

## Structured variables

| Variable | Required | Rule |
| --- | --- | --- |
| `practice_display_name` | Yes | Verified practice name; plain text; not supplied by the patient |
| `care_context_label` | Yes | Approved label for pre-visit, medication follow-up, or recurring collection |
| `collection_period_text` | Yes | Exact resolved local dates and fixed request timezone |
| `schedule_text` | Yes | Approved windows/counts, or “all available readings” |
| `submission_cadence_text` | Yes | End, daily, weekly, every-N-days, or patient-initiated wording |
| `requested_values_text` | Yes | Systolic/diastolic and the approved pulse policy |
| `practice_collection_instructions` | No | Exact text from an approved, versioned practice variant |
| `practice_contact_text` | No | Approved non-emergency contact direction; no patient-specific contact data |

The renderer must escape every value as plain text. It must not accept HTML, links with embedded
authority, script, Markdown interpretation, or undeclared variables.

## Exact common text

> **Blood-pressure document request from {{practice_display_name}}**
>
> Your practice requested a {{care_context_label}} blood-pressure document.
>
> **Collection period:** {{collection_period_text}}
>
> **Requested schedule:** {{schedule_text}}
>
> **Submission schedule:** {{submission_cadence_text}}
>
> **Requested values:** {{requested_values_text}}
>
> Health.md reads eligible blood-pressure and heart-rate records from Apple Health or Health Connect.
> Health.md Practice does not let you enter or change measurement values. Records marked as manually
> entered by the source can be included and will be labeled in the document.
>
> [Render this paragraph only when `practice_collection_instructions` is present.]
>
> **Instructions from your practice:** {{practice_collection_instructions}}
>
> Review the requested dates, timezone, schedule, identity, readings, sources, and any proposed pulse
> associations before submitting. If a source value is wrong, correct it in the app or health source
> that recorded it and generate a new document.
>
> Health.md Practice exchanges a document. It does not continuously monitor your readings, provide
> medical advice or emergency alerts, or promise that a clinician will respond within a particular
> time.
>
> If you need medical help or have a time-sensitive concern, use the contact and emergency channels
> provided by your practice or local emergency services. Do not rely on this document submission for
> urgent help.
>
> [Render this paragraph only when `practice_contact_text` is present.]
>
> **Practice contact direction:** {{practice_contact_text}}

## Practice variant record

A practice variant supplies only the optional exact paragraphs and references this common version.
Do not put patient-specific instructions or identity in a reusable template.

```text
Practice alias: Practice A | Practice B
Variant ID:
Variant version:
Common template ID/version: practice-bp-common/1.0-draft.1
Exact practice_collection_instructions:
Exact practice_contact_text:
Clinical approver role:
Approval date:
Approval evidence reference:
Protocol revision reviewed:
Status: draft | approved | rejected
```

## Review checklist

- [ ] Clinical owner approved the exact practice collection wording.
- [ ] Operations owner approved contact and no-response wording.
- [ ] Privacy/security owner approved variables and notification boundaries.
- [ ] Text contains no patient identity, appointment, diagnosis, medication, or other patient-specific
      content.
- [ ] The rendered request shows fixed dates/timezone and exact schedule/cadence.
- [ ] No wording implies monitoring, threshold alerts, medical advice, or response SLA.
- [ ] Accessibility, localization, escaping, length, and truncation behavior were reviewed.

A template change applies only to new request revisions or successor requests. An accepted request
retains the exact common and variant versions shown to the patient.
