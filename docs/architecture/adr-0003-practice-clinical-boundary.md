# ADR-0003: Isolate Health.md Practice in a clinical component

- **Status:** Proposed — synthetic implementation may proceed; production approval blocked
- **Date:** 2026-08-06
- **Decision owners:** Practice application, security, privacy, compliance, and operations owners (production owners unassigned)
- **Scope:** Practice clinician portal and future clinical API/infrastructure

## Context

Health.md Practice will process patient identity, request metadata, immutable health-document packets, access events, and retention state. Those values and their metadata are inside a clinical/PHI boundary. The static website and existing analytics, attribution, and OAuth Workers were not designed or governed for that boundary. The Practice pilot protocol is still `1.0-draft.4`; founder and practice approvals, compliance/BAA evidence, backend services, and launch gates remain incomplete.

## Decision

Practice is an independently built and governed component under `apps/practice`. It owns its source, npm lockfile, tests, build output, runtime configuration, future infrastructure, and release evidence. It must not import from, proxy through, or share clinical stores with `apps/website`, `apps/apple/worker`, or root `worker` services.

The portal and API use one dedicated same-origin clinical runtime. Browser paths are fixed and contain no patient, relationship, request, packet, date, cursor, sort, or filter value. Authenticated HTML, API responses, and assets default to `Cache-Control: no-store`; assets and network requests are same-origin; CSP and related headers prohibit third-party execution and exfiltration. No analytics, session replay, remote font, public object URL, or unrestricted HTML rendering is permitted.

The checked-in first milestone is synthetic-only. Its environment parser accepts exactly `synthetic`, has no production mode, route, credential, persistence binding, deployment workflow, or public Worker hostname. It uses deterministic fictional fixtures and cannot establish production readiness. A production design requires a separately reviewed identity/MFA boundary, tenant-isolated persistence, private storage, audit, retention/purge, observability, infrastructure, recovery, compliance/BAA, security-review, and release-gate decision.

Apple and Android receive dormant additive Practice policies. Packaging future code is necessary but insufficient: an exact, separately governed qualification attestation is also required. No attestation is supplied today, so personal export remains local-first and account-free.

## Ownership boundary

- `packages/contracts` will own reviewed language-neutral Practice request, packet, and delivery-manifest schemas and fixtures.
- Shared Rust will own deterministic validation, normalization, schedule/pulse semantics, and canonical rendering only after those contracts are approved.
- Native Apple/Android code will own platform health-source capture, consent, patient UI, local protection, and qualified submission clients.
- `apps/practice` owns clinician UI, its same-origin adapter, clinical deployment configuration, and portal qualification evidence.
- The authoritative backend will own identity/session enforcement, tenant/role authorization, immutable persistence, audit, retention, purge, and private artifact delivery; the synthetic fake API is not that backend.

## Consequences

Practice gains a clear build, CI, licensing, runtime, and review boundary. It duplicates some web infrastructure rather than inheriting unsafe marketing assumptions. Production remains intentionally unavailable until external and backend gates are complete. Changes to Practice contracts must trigger all producers and consumers, while purely synthetic portal changes remain component-scoped.

## Approval gate

This ADR does not become accepted for real PHI until named owners approve the architecture and exact service/vendor configuration, the threat model and compliance/BAA launch checklist are complete, independent security review is dispositioned, and production configuration proves every mandatory gate. Until then, only synthetic development is authorized.
