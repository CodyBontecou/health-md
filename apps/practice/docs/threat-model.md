# Practice synthetic portal threat model

- **Status:** Initial draft; independent security/privacy review blocked
- **Applies to:** synthetic foundation only
- **Production/real-PHI authorization:** prohibited

## Data classification

| Data | Classification | Foundation handling |
| --- | --- | --- |
| Packet values, identity, DOB, MRN, health/request dates | Clinical/PHI boundary | fictional fixture content only; authorized content body only; never URL/title/log |
| Practice, relationship, request, packet and actor metadata | Clinical/PHI boundary | fictional opaque IDs; response bodies only |
| Invitation/session/CSRF/access tokens | Secret and PHI-capable | injected deterministic values in tests; Web Crypto values at HTTP runtime; response/cookie memory, consumed SHA-256 invitation/claimant state, expiry, and process-local reset |
| IP, user agent, request timing, errors | PHI-capable operational metadata | no application telemetry/logging; provider policy blocked for production |
| Audit/security incident evidence | Restricted, PHI-capable | not implemented; future minimum-necessary separate store |
| Synthetic aliases and generated readings | Test-only clinical-shaped data | deterministic committed catalog, persistent visible label |

## Trust boundaries and data flow

The current flow is browser -> same-origin Worker -> in-memory immutable synthetic catalog -> browser. Worker static assets traverse the same boundary. There is no identity provider, database, object store, queue, notification provider, backup, EHR, analytics, support console, or production network. Those future boundaries require a reviewed update before implementation.

## Threats and current mitigations

- **Mode/configuration confusion:** exact typed `synthetic` parser; missing/unknown/production fails closed; no production routes or deploy workflow.
- **Cross-origin exfiltration:** relative API constants, restrictive `connect-src 'self'`, no CORS, no remote assets, dependency and source scanner.
- **URL/history leakage:** fixed static path allowlist with no query/resource segments; tests reject parameter syntax.
- **Cache/back-forward leakage:** no-store on every response. Authenticated cache clearing and bfcache tests remain blocked on real sessions.
- **XSS/content injection:** React escaped text only, hostile fictional fixture, no raw HTML API, no inline/eval CSP allowance, nosniff.
- **Clickjacking/referrer/sensor leakage:** frame denial, no-referrer, restrictive permissions and cross-origin headers.
- **Tenant/IDOR/session/CSRF/replay/fixation:** the fake API exercises generic denial, server-derived memberships/capabilities, strict same-origin POST, synthetic secure-cookie/CSRF behavior, cookie-authenticated CSRF bootstrap rotation after refresh, expiring terminal MFA challenges, per-secret plus coarse bounded abuse state, consumed server-side step-up, role-change revocation, and replay/fixation tests. These are test-double semantics only; authoritative identity and persistence designs remain blocked.
- **Object-key/public URL exposure:** no object storage or artifact URL exists.
- **Unsafe logging/telemetry:** no analytics, session replay, request-body logger, metrics binding, or console logging in application source. Synthetic audit buffers and sequence spaces are tenant-partitioned, with unauthenticated/security events isolated so one partition cannot evict or create visible gaps in another.
- **Inferred clinical workflow:** explicit synthetic acknowledge and separately enabled review mutations bind the actor and exact packet revision. Load/download alone may establish `opened`; dwell, scroll, and print return negative-proof no-op receipts and never establish acknowledgment/review. Mutable availability/workflow is excluded from immutable canonical artifact download bytes. Only explicit acknowledgment changes the synthetic 30-day deletion schedule; open/review/passive actions do not.
- **Deletion/backup gaps and insider/support access:** no persistence exists; controls and residual risk must be designed before storage.

## Prohibited telemetry and log fields

Never collect names, DOB, MRN, email, relationship/request/packet IDs, health dates or values, source records, report bodies, invitation/session/CSRF tokens, QR/deep-link values, filter terms, downloaded filenames, page titles containing clinical values, or time-on-document as acknowledgment/review. No product analytics or engagement telemetry is approved. Security/audit events must later use reviewed stable PHI-free codes and minimum-necessary opaque references in a separately governed store.

## Required production follow-up

A reviewed end-to-end diagram must cover device, invitation, identity, API, portal, database, private object store, KMS, notification, audit, backup, support and EHR boundaries. It must map tenant isolation, IDOR, account takeover, replay, rate limiting, token leakage, redaction, cache, insider access, legal hold/deletion, pulse association, provider logs and incident artifacts to implementation/tests. Residual risks, named owners, independent penetration testing, BAA/subprocessor evidence, and explicit launch attestations are mandatory and currently blocked.
