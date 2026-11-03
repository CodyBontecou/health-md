# Practice portal runtime and deployment boundary

- **Status:** Proposed synthetic foundation
- **Runtime owner:** Health.md Practice application owner (unassigned/blocking for production)
- **Security/privacy/operations owners:** unassigned/blocking for production
- **Rendering:** React client bundle with semantic HTML and same-origin CSS
- **Runtime:** one Cloudflare Worker fetch boundary plus Worker static assets
- **Supported browsers:** latest two stable Chrome/Edge, Firefox, and Safari

## Boundary

`apps/practice` owns its lockfile, source, tests, build output, Worker configuration, and future deployment. It has no dependency edge to `apps/website`, `apps/apple/worker`, or root `worker`. The same clinical origin serves fixed portal paths, assets, and relative `/api/v1/*` requests. No cross-origin API or CORS contract exists.

The checked-in environment is deliberately non-deployable as a production clinical service: `workers_dev=false`, no routes, no deployment workflow, no storage/queue/analytics binding, no credential, and a runtime parser that accepts only `synthetic`. Wrangler dry-run verifies packaging only.

Milestone 1 adds an in-memory clinical-domain simulator at the one static, query-free `POST /api/v1/operation` path. Its clock, identifiers, hashing, and tokens are injectable so tests remain deterministic; the HTTP runtime uses Web Crypto UUIDs and random bytes. Process restart/reset discards all state. It models server-derived tenant membership/capabilities, expiring MFA challenges, session-bound consumed step-up facts, refresh-safe `session_bootstrap` CSRF rotation, immutable templates/request representations/packet artifacts, explicit workflow facts, tenant-partitioned bounded health-free audit state, and synthetic retention receipts solely as a test double. Invitation claim consumes the original hash, canonicalizes the claimant device IANA timezone, materializes fixed local-date boundaries to half-open UTC bounds, and returns exact server-derived acceptance instructions plus a separately hashed, short-lived claimant receipt. Acceptance binds the reviewed acceptance SHA-256 before persisting immutable acceptance facts. Issue/renew commits and coalesced replays reauthorize after async hashing; renewal stays pending until successor acceptance. It is not an identity, authorization, persistence, audit, retention, or cryptographic production design.

## Rendering and routing

The SPA bundle uses no inline script or eval requirement. The 26-entry canonical route inventory is scoped exactly to client-visible fixed portal page routes. Fixed HTTP surfaces are inventoried separately: `POST /api/v1/operation`, `GET /api/v1/meta`, `GET /api/v1/catalog`, `GET /styles.css`, and `GET /assets/app.js`; unknown `/api/*` paths fail closed. The route manifest contains only static paths and must never accept patient, relationship, request, packet, audit, date, filter, sort, or cursor data in a path or query. Resource selection uses authorized same-origin request bodies and short-lived server session state. The foundation does not implement browser persistence.

React's escaped text interpolation is the only fixture rendering path. `dangerouslySetInnerHTML`, arbitrary HTML/Markdown, third-party scripts/fonts, and remote images are prohibited. Route and root error states are generic and contain no clinical values.

## HTTP policy

The Worker applies `Cache-Control: no-store` and a restrictive CSP, no-referrer, frame denial, nosniff, permissions denial, HSTS, and cross-origin isolation/resource policy to HTML, assets, API success, and error responses. It emits no CORS header. Static assets are intentionally no-store at this milestone because the whole origin is treated as clinical.

## Deliberately blocked draft semantics

The simulator materializes only fixed-date request boundaries whose local midnights resolve uniquely in the acceptance-time IANA timezone. It rejects rather than guesses relative-date preview materialization, ambiguous or nonexistent local-midnight boundaries, schedule-window DST materialization, recurring cadence anchors, overnight/touching windows, and other combinations lacking a language-neutral contract oracle. Pulse `required` is represented as a requested policy only and is not interpreted as packet rejection. Renewal is an explicit immutable successor with a newly entered non-overlapping fixed period; there is no rollover job.

## Blocked production decisions

Identity/MFA vendor and session design, production CSRF/session implementation, tenant persistence, database isolation, private object storage, KMS, audit, retention/purge, notification, observability, support access, incident response, hostname/network, Cloudflare service eligibility/BAA, IaC, backup/recovery, release ownership, and independent penetration testing remain blocked. Synthetic handlers and fixtures are not evidence that those controls exist.

## SetClinic integration simulator

`src/clinic/` implements an internal, synthetic-only integration model for the
three requested SetClinic workflows. Run `npx vitest run test/clinic-integration.test.ts`
from this component for executable examples. Nothing in this module is mounted on
an HTTP endpoint, imported into the portal bundle, or wired into either native app.
It creates no credentials, makes no network request and activates no paid access.
The existing invitation claim/acceptance API remains independent: its fixed-date
clinical instructions are not generalized into arbitrary metric or export consent.
The model reuses its canonical JSON and SHA-256 review primitives.

### Onboarding and consent

An authenticated clinic creates a bounded, expiring setup intent. The fictional
patient reads their authenticated inbox, reviews the clinic, endpoint, canonical
metric IDs, cadence and UTC hour, and explicitly accepts the exact review digest.
Acceptance creates an isolated profile identity bound to that patient and phone;
retries return that same connection. Schedules start disabled and require a
separate patient action to enable the intent. The simulator does not execute schedules.
Changing destination, metrics or cadence requires a new review/connection; clinic
requests cannot override the approved profile. Patient revocation disables the
schedule intent and stops pending work.

The proposed QR payload is the constant `healthmd://clinic/setup`; refresh handoff
uses `healthmd://clinic/refresh`. These are navigation hints only. No identifiers,
credential, endpoint, entitlement or health context goes in the URL. They are not
registered/shipped links, and no QR renderer is enabled. Native apps must resolve
the authenticated inbox after foreground handoff; a personal SetClinic URL is not
an implemented Health.md configuration-parameter contract. Shared Setup v2 remains
unchanged and cannot carry these identities, credentials, paid access, permissions,
or enabled schedules. The two test metrics are existing registry IDs `steps` and
`heart_rate_avg`; other metrics deliberately fail closed in this simulator.

### Clinic-paid access

`ClinicAccessPolicy` preserves a consumer export entitlement first. A trusted
provider can separately return a grant bound to clinic, patient and approved
connection, with revocation and expiry checks. The default clinic route returns
`store_decision_required`. Only the explicit synthetic route can exercise the
fictional seat provider. `SyntheticClinicLicenses` takes an explicit capacity and
expiry, counts distinct patients, permits repeated assignments without consuming
extra seats, and supports revocation/reassignment. Tests configure twenty seats;
that is neither a contract acceptance nor an annual subscription or charge.
No key, QR, imported setup or client Boolean grants paid access. Native StoreKit
and Play billing/purchase code remains the consumer authority. Distribution,
store review and the commercial entitlement source need a product/store decision
before installing any production clinic provider. Sharing consent and OS Health
permission remain separate from this payment decision.

### Fresh export and correlated status

The clinic supplies a request ID, approved connection and explicit half-open UTC
interval, ending no later than the request time and spanning at most 366 days.
The broker freezes that scope and permits only one pending request per connection.
The same ID with different scope conflicts; a retry of the same ID returns the
same result. A new ID requests fresh capture even for an unchanged interval.
Requests expire after five minutes, including while running. These conservative
synthetic limits need a reviewed production contract.

`PatientClinicExports` checks the authenticated account/device, foreground state,
local profile/destination snapshot, consent, entitlement and Health-data availability
before starting and through an injected check before every capture/publication/retry.
The adapter must call the existing native exporter; this module contains no renderer,
uploader or wearable synchronization implementation. The intended Apple seam is
`APIEndpointExportRunner.export` with a reviewed frozen destination, and the Android
seam is the existing `ExportRepository`/API destination pipeline. Their adapters are
**planned**, not implemented or runtime-verified here. Locked HealthKit data can be
unavailable even after permission was requested. Foreground execution is the only
mode modeled; background wake would be best effort. The existing notification-only
Wake Worker is not a clinic request store or health transport.

Status distinguishes `requested`, `running`, `uploaded` and explicitly
clinic-confirmed `processed`; upload never implies clinic processing or clinical
review. Receipts bind request, connection, profile revision, destination and exact
interval. The local journal records execution before side effects and persists
upload evidence before acknowledgment. An acknowledgment retry replays only the
receipt. An interrupted execution is terminal and requires checking history and a
new request ID, preventing a blind second export. Cancellation/revocation/expiry
stop remaining work; existing files are retained, and late receipts remain visible
without resurrecting work or changing a terminal state into processing success.
The adapter must enforce cancellation before each publication, including retries.
A receipt is adapter-reported upload evidence, not authenticated proof of SetClinic
processing; only the clinic actor can explicitly record processing.

### Remaining integration and release inputs

- Approve an authenticated SetClinic service/tenant/patient enrollment and secure
  endpoint binding contract, including destination allowlisting, redirect behavior,
  authorization delivery, upload idempotency and receipt/processing semantics.
  Credentials must be bound to the reviewed endpoint in secure native storage,
  never URL/imported fields. The simulator uses only the relative same-origin hint `/synthetic-upload`; no uploader is mounted there. Native HTTPS endpoint binding remains a separate reviewed contract.
- Implement the Apple and Android review UI, authenticated inbox and existing-export
  adapters against that contract. Both platforms remain `planned` in the capability
  inventory. Preserve native OS permissions and independent consumer purchases.
- Replace resettable stores and the synthetic journal with authoritative isolated
  persistence and crash-safe local journaling. Actor values must come from validated
  sessions; callers cannot select their role, clinic, patient or device in JSON.
  `ClinicFactories.authenticate` is a trusted test injection, not an identity provider.
  The model bounds retained setups to 100 and refresh requests to 1,000, fails closed
  at capacity and retains idempotency until reset; restart discards all state.
- Resolve the clinic-paid store/distribution route and commercial source of grants.
  Keep the default policy gate closed until that decision and review are complete.
- Qualify foreground lifecycle, locked data, secure auth, crash recovery, retries,
  patient revocation and physical devices; retain all existing Practice production
  security/privacy/BAA/ownership gates. No deployment or real patient data is authorized.
