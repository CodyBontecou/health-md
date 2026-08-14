# Health.md Practice pilot EHR vendor discovery aid

- **Status:** Non-normative research aid — not pilot approval or tenant-capability evidence
- **Research access date:** 2026-08-06
- **Scope:** Candidate vendor disambiguation for Pilot Practice A and Pilot Practice B
- **Related guide:** [`pilot-practice-discovery-and-approval.md`](pilot-practice-discovery-and-approval.md)

## Purpose and limits

The actual EHR and patient-portal products used by Pilot Practice A and Pilot Practice B remain
unknown. This aid gives interviewers official starting points for four plausible candidate platforms.
The list is not a market-share ranking, vendor endorsement, connector decision, or claim that either
practice uses one of them.

Public documentation proves only that a capability exists in a documented product or version. It
does not prove that a specific practice has licensed, enabled, configured, mapped, authorized, or
operationally approved it. Every selected pilot path still requires the exact per-path fictional PDF
test defined in [`fixtures/README.md`](fixtures/README.md).

No official source reviewed established a platform-wide guarantee that patients may upload arbitrary
PDF files through every MyChart, athenaPatient, healow, or Oracle Health Patient Portal tenant.
Patient-side upload therefore remains `unknown` until tested in the actual tenant.

## Standards vocabulary

Do not treat all FHIR resources as interchangeable attachment envelopes:

- [`DocumentReference`](https://hl7.org/fhir/R4/documentreference.html) indexes a document, clinical
  note, or other binary object.
- [`Observation`](https://hl7.org/fhir/R4/observation.html) represents measurements and simple
  assertions, including blood pressure.
- [`ServiceRequest`](https://hl7.org/fhir/R4/servicerequest.html) records a request for a procedure,
  diagnostic, or other service.
- [`Task`](https://hl7.org/fhir/R4/task.html) tracks an activity and its completion state.

Creating a `ServiceRequest` or `Task` may initiate real clinical work. Neither resource is evidence
of a report-carrier path; any proposed use belongs in the versioned protocol and explicit practice
approval rather than this research aid.

FHIR create uses `POST [base]/[type]`, while update uses `PUT [base]/[type]/[id]`; a POST to
`[type]/_search` is a search, not a create operation. See the
[FHIR R4 RESTful API](https://hl7.org/fhir/R4/http.html).

[SMART App Launch](https://hl7.org/fhir/smart-app-launch/) defines user-facing app authorization and
launch behavior. [SMART Backend Services](https://hl7.org/fhir/smart-app-launch/backend-services.html)
defines pre-authorized service access. Advertised scopes remain subject to server- and client-specific
policy; they do not prove tenant enablement.

## Candidate capability matrix

| Candidate platform | Public document capability | Public structured BP capability | Public request/task capability | Developer path | Required tenant verification |
| --- | --- | --- | --- | --- | --- |
| Epic | Clinical Notes create is plain-text only, not PDF; Document Information create is limited to Hyperdrive Scan Acquisition and update is scanning-integration-specific; no generic public FHIR PDF-write path was established | R4 Vital Signs `Observation` create | ServiceRequest create/update is named-workflow-specific, not generic; public Task support reviewed here is Community Resource update, not generic create | Epic on FHIR sandbox and client registration | Customer release, licensing, installed client, mappings, scopes, chart destination, attachment limits, and actual MyChart/EpicCare Link workflow |
| athenahealth | Public R4 `DocumentReference` catalog is read/search; separate proprietary athenaOne multipart chart-document POST exists | Public R4 `Observation` catalog is read/search | Public R4 `ServiceRequest` is read/search; no public Task path established in this review | Developer Portal, SMART/OAuth, Preview sandbox | Exact athena product, practice/brand/chart-sharing IDs, Certified FHIR versus proprietary API entitlement, document subclass/destination, scopes, and actual athenaPatient attachment behavior |
| eClinicalWorks | R4 PDF `DocumentReference` POST; documented App Data or conditional direct Patient Documents/Chart Documents routing | R4 Vital Signs `Observation` POST includes BP components; normally staged in App Data for reconciliation | R4 ServiceRequest order POST is normally staged for reconciliation; R4 Task Actions POST creates an Action directly | Dev Portal registration, sandbox, publication, activation-code and per-customer enablement | eCW version/patch, licensed APIs, app type/scopes, staging versus direct destination, folder and encounter/authenticator rules, reconciliation owner, and actual healow attachment behavior |
| Oracle Health Millennium | R4 `DocumentReference` POST/PUT; documented PDF support | R4 `Observation` POST/PUT for supported categories including Vital Signs with BP components | Public R4 ServiceRequest index is read/search; no Task entry found in the reviewed public endpoint index | Developer program, open read-only sandbox, authenticated registration/testing path | Millennium versus Soarian, exact R4 release/root, app authorization mode/scopes, enabled writes, document type/destination, local configuration, and actual portal attachment behavior |

“Public” in this table means documented by the linked vendor sources as of the access date. It does
not mean generally available to every customer or appropriate for the pilot.

## Vendor-specific interview disambiguation

### Epic / MyChart

Ask the practice:

1. Exact Epic release, deployment, and customer instance.
2. Whether the patient portal is MyChart and whether inbound message/file attachments are enabled.
3. Whether EpicCare Link is used and whether authorized external staff can upload chart documents.
4. Whether the intended document lands in chart documents, Media Manager, a portal message, a work
   queue, or another reconciliation path.
5. Whether any tenant-specific interface provides an approved PDF path. The reviewed Clinical Notes
   create profile is plain-text only; Document Information create is limited to Hyperdrive Scan
   Acquisition and update is scanning-integration-specific. None establishes a generic public FHIR
   PDF-write path. Separately confirm
   whether Vital Signs `Observation` create is enabled.
6. Which user type, SMART launch, scopes, MIME types, size limits, document type/LOINC, encounter,
   author/authenticator, and duplicate behavior apply.
7. Who installs and approves the client in this customer instance.

Official starting points:

- [Epic on FHIR catalog](https://fhir.epic.com/)
- [Clinical Notes create specification](https://fhir.epic.com/Specifications?api=1046)
- [Document Information create specification](https://fhir.epic.com/Specifications?api=10050)
- [Document Information update specification](https://fhir.epic.com/Specifications?api=10051)
- [Vital Signs create specification](https://fhir.epic.com/Specifications?api=963)
- [Community Resource Task specification](https://fhir.epic.com/Specifications?api=10087)
- [Epic developer sandbox and client registration](https://fhir.epic.com/Developer/Index)
- [Epic implementation guidance](https://fhir.epic.com/Documentation?docId=implementing)
- [MyChart public feature page](https://www.mychart.org/l/en-us/)

### athenahealth / athenaOne

Ask the practice:

1. Whether it uses athenaOne, athenaClinicals, athenaCollector, or another athena product.
2. Practice, brand, department, and chart-sharing-group identifiers needed by the intended interface.
3. Whether the route is Certified FHIR R4 or the proprietary athenaOne document API.
4. Whether the proprietary chart-document POST is contracted, enabled, and authorized for the
   practice and integration.
5. Required document subclass, provider, department, status, and chart destination.
6. Whether patients can attach files to messages in this exact athenaPatient tenant and whether those
   files become chart documents or remain message attachments.
7. Whether system/backend or user/patient SMART authorization is required and which scopes are
   granted.

Official starting points:

- [athenahealth FHIR base URLs](https://docs.athenahealth.com/api/guides/base-fhir-urls)
- [R4 DocumentReference operations](https://docs.athenahealth.com/api/fhir-r4/document-reference)
- [R4 Observation operations](https://docs.athenahealth.com/api/fhir-r4/observation)
- [R4 ServiceRequest operations](https://docs.athenahealth.com/api/fhir-r4/service-request)
- [Certified APIs and SMART](https://docs.athenahealth.com/api/guides/certified-apis)
- [Developer onboarding](https://docs.athenahealth.com/api/guides/onboarding-overview)
- [Preview sandbox](https://docs.athenahealth.com/api/guides/testing-sandbox)
- [Document API reference](https://docs.athenahealth.com/api/api-ref/document)
- [athenaPatient public page](https://www.athenahealth.com/patient-login)

### eClinicalWorks / healow

Ask the practice:

1. Exact eCW release and cumulative patch, because resource support may be build-specific.
2. Whether the required create APIs are licensed and activated.
3. Whether the app is provider, system/backend, EHR-launch, or standalone.
4. Whether PDFs should enter App Data for reconciliation or go directly to Patient Documents/Chart
   Documents, and under what status/authenticator/context rules.
5. Required folder, encounter, authenticator, and reconciliation owner.
6. Whether structured BP observations are preferred and who reconciles App Data.
7. Whether creating a ServiceRequest or Task would initiate unwanted clinical work.
8. Whether the practice and developer have completed per-customer activation.
9. Whether healow in this tenant supports inbound file attachments.

Official starting points:

- [eClinicalWorks API catalog](https://fhir.eclinicalworks.com/ecwopendev/documentation)
- [PDF DocumentReference create](https://fhir.eclinicalworks.com/ecwopendev/documentation/create-resources?name=DocumentReference+%28PDF%29)
- [Vital Signs Observation create](https://fhir.eclinicalworks.com/ecwopendev/documentation/create-resources?name=Observation+%28Vital+Signs%29)
- [ServiceRequest order create](https://fhir.eclinicalworks.com/ecwopendev/documentation/create-resources?name=ServiceRequest+%28Lab-DI-Procedure+orders%29+%28Create%29)
- [Task Actions create](https://fhir.eclinicalworks.com/ecwopendev/documentation/create-resources?name=Task+%28Actions%29)
- [Sandbox guidance](https://fhir.eclinicalworks.com/ecwopendev/documentation/getting-started/guidelines/sandbox-testing)
- [healow public portal page](https://healow.com/apps/jsp/webview/signIn.jsp)

### Oracle Health Millennium

Ask the practice:

1. Whether the tenant is Millennium Platform or Soarian Clinicals, plus exact release and service root.
2. Whether the integration is patient, provider, or system authorized.
3. Whether `DocumentReference` and `Observation` create/update are enabled for the app and tenant.
4. Required document type, MIME type, encounter, author, chart/staging destination, and review path.
5. Whether patients can attach files in the exact portal configuration.
6. Whether staff portal-message PDF attachments become chart documents.
7. Which local Millennium configuration and interface work remains customer-responsible.
8. Whether the deployment requires Oracle's multi-tenant validation or a beta-site process.

Official starting points:

- [Oracle Health Millennium R4 API](https://docs.oracle.com/en/industries/health/millennium-platform-apis/mfrap/)
- [Public R4 endpoint index](https://docs.oracle.com/en/industries/health/millennium-platform-apis/mfrap/rest-endpoints.html)
- [DocumentReference create](https://docs.oracle.com/en/industries/health/millennium-platform-apis/mfrap/op-documentreference-post.html)
- [Observation create](https://docs.oracle.com/en/industries/health/millennium-platform-apis/mfrap/op-observation-post.html)
- [Tenant-specific service roots](https://docs.oracle.com/en/industries/health/millennium-platform-apis/mfrap/srv_root_url.html)
- [Oracle Health developer program](https://www.oracle.com/health/developer/program/)

## How to use this aid

1. Ask the practice to name its actual product, version, tenant, portal, and integration owner before
   selecting a candidate section.
2. Obtain the tenant's live FHIR `CapabilityStatement` and SMART configuration without patient data,
   when applicable.
3. Record licensed/enabled operations and scopes; do not infer writes from resource read access or an
   advertised wildcard scope.
4. Identify the exact destination and human reconciliation workflow.
5. Run `practice-ingest-test-v1` through every selected path and record each result separately.
6. Keep a platform candidate marked `unknown` until tenant evidence and fictional testing establish
   the path.
7. Use the resulting practice record—not this research aid—to resolve the pilot protocol deviations.

## Research confidence and change policy

Confidence is high that the official catalogs documented the operations summarized above on the
access date. Confidence is intentionally low for patient-side upload, tenant enablement, licensing,
local configuration, and workflow destination until the practice supplies evidence.

Vendor documentation changes independently. Recheck every cited operation and onboarding rule before
implementation or production qualification. Updating this aid does not change the versioned pilot
protocol; changing request, packet, or workflow semantics does.
