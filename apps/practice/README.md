# Health.md Practice clinician portal

> **Synthetic foundation only. No production or real-PHI environment exists.**

This independent component is the future Health.md Practice clinical origin. It does not reuse the static marketing website or any existing analytics, attribution, or OAuth Worker. The current milestones provide a partial, production-disabled synthetic clinician portal, reusable accessible clinical components, deterministic fictional fixtures, and a typed, resettable in-memory clinical service behind one static same-origin operation endpoint. Component-state coverage is tracked in `docs/component-state-coverage.md`; it is representative automated evidence, not a claim that every route, transition, browser, or assistive-technology state is complete. The service remains a UI-development test double, not an authoritative backend.

## Status and blocked decisions

The portal follows draft protocol `1.0-draft.4` and draft common instructions `practice-bp-common/1.0-draft.1`. Founder and pilot-practice approval, exact clinical templates/windows/cadence, identity provider and MFA configuration, hosting/BAA/subprocessors, storage/retention, audit, notification, packet contracts, security review, hostname, and deployment ownership are **blocked and unapproved**. A green build and substantial synthetic automation are partial evidence only: qualification manifests are indexes, not proof, and no child TODO, epic, or decomposed parent completion is attested while those named dependencies and external gates remain open.

The checked-in Worker has no deployment route, public `workers.dev` hostname, persistence binding, credential, analytics binding, or deployment workflow. Its parser rejects every runtime mode except `synthetic`.

## Commands

Requires Node 24 and npm.

```bash
npm ci                 # reproducible install
npm run typecheck      # TypeScript boundary
npm test               # unit, component, jsdom integration, and automated axe tests
npm run check:synthetic       # scan source, built assets, fixtures, and qualification fields
npm run check:scanner-canary  # prove seeded prohibited data is rejected
npm run check:security        # verify exact route/34-operation traceability inventory
npm run build                 # browser production bundle
npx playwright install chromium firefox webkit
npm run test:e2e              # serial Chromium, Firefox, WebKit against local Wrangler
npm run check:qualification   # prove synthetic gates are configured and production is disabled
npm run build:provenance      # ignored metadata-only provenance receipt
npm run dry-run               # package only; never deploy
npm start                     # build and serve synthetic mode at http://127.0.0.1:8787
```

A local smoke check:

```bash
curl -i http://127.0.0.1:8787/api/v1/meta
```

The response must report `"mode":"synthetic"`, use `Cache-Control: no-store`, and include the restrictive component security headers.

## Architecture

- TypeScript and React SPA compiled by a component-owned esbuild script.
- Fixed, identifier-free browser paths from `src/web/routes.ts`.
- Typed same-origin API contracts in `src/contracts/`; browser calls use relative paths only.
- Cloudflare Worker fetch boundary in `src/worker.ts`, with static assets routed through the Worker so headers apply consistently.
- Deterministic fictional development data in `src/synthetic/catalog.ts` and injected-factory domain behavior in `src/synthetic/service.ts`; tests inject deterministic values while the HTTP runtime uses Web Crypto randomness.
- Stable blocking validation codes for unresolved relative date, DST, cadence-anchor, and overnight/touching-window semantics; no browser date-library defaults.
- Draft synthetic retention receipts explicitly report `legalApproval: false`; only explicit acknowledgment changes the synthetic schedule, and fake audit records are health-value/token free.
- Invitation claim and acceptance use separate expiring one-time hashes with per-secret abuse buckets; the browser keeps the one-time artifact only in invitation-route memory and destroys it on navigation/pagehide/action/logout. QR and mobile deep-link rendering remain blocked pending an approved mobile contract. Immutable packet artifact bytes exclude mutable workflow and availability.
- A cookie-authenticated `session_bootstrap` operation rotates CSRF after refresh without browser storage and supplies authoritative role/capabilities after MFA. Protected terminal-session handling clears client state fail-closed. Issue/renew commits reauthorize after hashing, each preview intent owns a unique memory-only retry key, and renewal remains pending until successor acceptance.
- No inline scripts, eval, raw HTML rendering API, remote asset, service worker, browser persistence, or runtime third-party request.

See `docs/architecture.md`, `docs/threat-model.md`, and the proposed repository ADR at `docs/architecture/adr-0003-practice-clinical-boundary.md`.

## Browser and qualification evidence

Playwright runs exact-pinned bundled Chromium, Firefox, and WebKit serially against the real local same-origin Wrangler runtime. The suite observes workflow DOM, generic JSON download bytes, print media, rendered axe including color contrast, keyboard/focus behavior, reduced motion, forced colors where supported, narrow 400%-equivalent reflow, request paths/referrers, cookie flags, browser persistence surfaces, and console/page errors. Success creates no screenshot, video, or trace; ignored synthetic-only artifacts are retained only on failure.

The versioned evidence index is `qualification/v1/`. It classifies every fixed route and all 34 operations, maps the 13 portal child TODOs and parent requirements to direct commands/tests, records supported synthetic states, and explicitly keeps production disabled. `qualification/generated/provenance.json` is ignored because SHA/dirty/tool/build metadata changes per run.

Qualification targets the latest two stable releases of Chrome/Edge, Firefox, and Safari, but bundled-engine automation is not that manual claim. Actual screen-reader/manual AT, latest-two manual browser review, touch/physical mobile devices, native print/PDF review, external penetration testing, authoritative backend/recovery/purge, compliance/BAA, and pilot approvals remain pending. QR/deep-link remains blocked pending an approved mobile contract.

## Ownership

Practice application, security, privacy, and operations owners must jointly approve later production boundaries. Until named owners and external gates exist, this component is maintained as synthetic development infrastructure only under AGPL-3.0-only.
