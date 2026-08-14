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
