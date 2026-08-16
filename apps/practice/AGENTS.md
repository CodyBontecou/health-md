# Health.md Practice Agent Instructions

## Clinical boundary

Everything served after authentication, including identity and request metadata, is inside the clinical/PHI boundary. This component is independent from `apps/website`, every existing Worker, and root `worker/`. Never import from, proxy through, or share stores with those components.

The checked-in runtime is **synthetic only**. Use fictional aliases and generated values. Never add real names, dates of birth, MRNs, readings, credentials, tenant URLs, access tokens, screenshots, or production configuration. `PRACTICE_RUNTIME_MODE` accepts only `synthetic`; do not add a production value without an approved architecture, compliance, security, BAA, and release-gate change.

## Product invariants

Practice v1 exchanges immutable documents. It does not provide monitoring, alerts, diagnosis, recommendations, messaging, emergency response, a clinician-response SLA, inferred acknowledgment/review, or measurement-value editing. Keep `opened`, explicit `acknowledged`, and explicit `reviewed` distinct.

Do not add third-party analytics, session replay, remote fonts, public object URLs, remote clinical assets, unrestricted HTML/Markdown, PHI in URLs, wildcard CORS, or cacheable clinical responses. Client API calls are relative and same-origin. Resource selection must not add IDs to paths or query strings.

The referenced product protocol `1.0-draft.4` and common instructions `practice-bp-common/1.0-draft.1` are unapproved drafts. Do not present them or any practice-specific clinical value as accepted.

## Component workflow

This is an independent Node 24/npm component with its own lockfile and generated output.

```bash
npm ci
npm run check
npx playwright install chromium firefox webkit
npm run test:e2e
npm run check:qualification
npm start
npm run dry-run
```

`npm run check:ci` is the component-local full synthetic gate after browser binaries are installed. Real-browser evidence covers bundled Chromium, Firefox, and WebKit; it does not replace pending manual screen-reader, physical-device, external security, compliance, BAA, backend, or pilot approval.

`npm start` builds and starts the local synthetic Worker on `127.0.0.1:8787`. Generated `dist/` and `.wrangler/` content is never committed. CI qualifies a build but never deploys it.

Before finishing, run type checking, unit tests, the source/build/fixture scanner and canary, security/qualification verifiers, production build, real local-Wrangler browser projects where available, smoke, Wrangler dry-run, `npm audit --audit-level=moderate`, and `git diff --check`. Preserve strict no-store/security headers and the fail-closed runtime guard. Generated browser failure artifacts and `qualification/generated/` provenance are synthetic-only and ignored.
