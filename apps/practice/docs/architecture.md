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
The simulator creates no credentials, makes no network request and activates no paid access. Dormant native adapters now live in the Apple Practice and Android Practice/data packages; no app bootstrap or URL handler installs them. Standalone native review/inbox screens now consume an injectable presentation transport that defaults unavailable.
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
uploader or wearable synchronization implementation. The Apple adapter uses `APIEndpointExportRunner.export` with a reviewed frozen destination; the Android adapter uses `APIEndpointExportRunner.exportDates` with the existing destination fingerprint and snapshot restore. Dormant adapters now call `APIEndpointExportRunner` on both platforms and retain the full saved native profile snapshot. App/service integration and device qualification remain planned. The Android `ExportRepository` filesystem pipeline is not a clinic API transport. Locked HealthKit data can be
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
- Qualify and install the implemented Apple and Android review/inbox screens and dormant existing-export
  adapters against that authenticated contract. Both platforms remain `planned` in the capability
  inventory. Preserve native OS permissions and independent consumer purchases.
- Replace the resettable service stores with authoritative isolated persistence and qualify the native crash-safe journals. Actor values must come from validated
  sessions; callers cannot select their role, clinic, patient or device in JSON.
  `ClinicFactories.authenticate` is a trusted test injection, not an identity provider.
  The model bounds retained setups to 100 and refresh requests to 1,000, fails closed
  at capacity and retains idempotency until reset; restart discards all state.
- Resolve the clinic-paid store/distribution route and commercial source of grants.
  Keep the default policy gate closed until that decision and review are complete.
- Qualify foreground lifecycle, locked data, secure auth, crash recovery, retries,
  patient revocation and physical devices; retain all existing Practice production
  security/privacy/BAA/ownership gates. No deployment or real patient data is authorized.


### Dormant native adapters and durable local records

Apple `Shared/Practice/ClinicNativeAdapters.swift` and Android
`data/practice/ClinicNativeAdapters.kt` accept a locally mapped full profile snapshot
from a future authenticated enrollment adapter. Preview binds the exact reviewed
settings, clinic, endpoint and schedule; Apply checks the review and current secure
destination identity, reserves a durable setup intent, adds a separate native profile,
and stores a disabled schedule. Existing active profiles and output options remain
intact. No credential is read from an imported bundle or written by onboarding.
An interrupted Apply is blocked on retry so it cannot silently create duplicate
profiles; recovery must inspect the saved profile before another enrollment.

`ClinicRefresh.swift` and `ClinicRefresh.kt` persist the complete native-local request
scope before export gates, execution before capture, and upload evidence before
reporting. A restarted coordinator replays an upload receipt without recapture;
interrupted execution becomes a terminal failure. Corruption, unknown versions,
symlinks, changed scope and capacity exhaustion fail closed. Apple uses atomic,
backup-excluded protected files; Android callers must use app-private
`Context.noBackupFilesDir` storage, atomic replacement, file sync and directory sync.
These files contain local identity/routing metadata and settings, never health payloads
or credentials. They are native clinical-boundary state, never Shared Setup content.

The adapters require whole calendar-day boundaries in the approved zone and reject
partial-day scope. Android also rejects a changed device zone because its existing
runner resolves the current device calendar; Apple restores the reviewed calendar.
Fresh capture goes through the same native API runners as manual export. Optional
runner authority callbacks check before each day and every upload/retry; default
callbacks preserve all existing callers. Profile changes, imported-profile execution
blocks, destination/credential rotation and mismatched account/device/connection
cannot silently retarget a request. Locked Health data, foreground state, sharing
consent and entitlement must be supplied by the trusted native session/gate adapter;
they remain independent. The clinic entitlement route defaults disabled even when a
provider says a grant exists. No notification or wearable sync implementation is added.

Both native entry points default to the existing unqualified Practice feature policy,
so merely compiling these adapters does not expose them. The remaining exact external
input is an authenticated enrollment/inbox/refresh/status/receipt contract and its
endpoint-bound auth delivery. Without it, installing a transport or automatically
binding a SetClinic endpoint would invent authority. The native review/inbox screens and their controllers are implemented with explicitly injected synthetic previews. Authenticated network transport, app-route activation, backend durability and production entitlement activation remain uninstalled. Source-matched Swift/Kotlin domain tests cover the local journal/state
machine; they do not establish HealthKit/Health Connect or full native app behavior.


### Native review and refresh inbox presentation

Apple `ClinicInboxView.swift` and Android `presentation/clinic/ClinicInboxScreen.kt`
provide standalone clinic inbox/review screens using native Form/List and existing
Geist components. `ClinicInbox.swift` / `ClinicInbox.kt` own the flow state across
loading, review, explicit consent, Apply, export, cancellation, receipt reporting and
withdrawal of sharing consent. Only an explicit patient action starts export.
The screens show clinic, profile, destination, selected metrics, export option facts,
paused schedule intent, review expiry, and separate access/Health permission notices.
Uploaded and explicitly clinic-processed states remain distinct. An unacknowledged
upload has a receipt-report action that cannot initiate another export.

The injected presentation port is an internal native interface, not a proposed HTTP
API. A future qualified mapper must derive all display facts and the exact review
digest from the same local full snapshot used by `ClinicNativeOnboarding.preview`;
a remote label or client Boolean is never application authority. The default port
has no session, credentials, URL or network implementation. Explicit synthetic fixtures
and IDE previews exercise the whole UI/controller flow without Health or billing reads.

Controllers reject expired review, missing consent and changed account context.
Reload/dismiss/background clears review and consent; stale asynchronous results cannot
replace newer state. Busy actions coalesce, and uncertain side effects require reload
before retry. The host must clear the controller on account change and connect its
transport actions to the existing native authorization/journal/export adapters. Production
route activation remains gated by `PracticeFeaturePolicy.current`, whose qualification
attestation is still absent. UI strings currently have the English source/fallback;
localization and rendered accessibility/layout qualification are release work.

No new product decision was needed to implement these screens. The exact remaining
transport decision is which authenticated service owns clinic enrollment, pending
refreshes, cancellation/revocation and receipt/status persistence, plus its endpoint-bound
auth and upload/idempotency/processing contract. This is blocked by the existing
clinical-service ownership/security/BAA gates above and the unapproved mobile contract
recorded in the component README. Selecting a base URL, auth header or production
backend without those inputs would invent the missing contract. The commercial/store
entitlement route is a separate decision and remains disabled.
