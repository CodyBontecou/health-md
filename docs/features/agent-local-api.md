# Authenticated local agent API

## Boundary

Health.md's generic agent routes live under `/v1/agent/` on the existing IPv4/IPv6 loopback listener. Loopback remains a network boundary, not caller identity. Every agent route requires:

```http
Authorization: Bearer <registration-uuid>.<one-time-random-secret>
```

The registration UUID selects exactly one Keychain account. Health.md compares the 32-byte secret in constant time, rejects revoked registrations, and never scans or labels an unknown loopback process as an authenticated agent. Credentials are shown once by the Mac UI, rotate in Keychain, and never enter access/activity JSON.

Legacy `/v1/exports` routes remain honestly unattributed during migration. They cannot inspect, resume, or cancel jobs owned by registered agents. Authenticated job controls use `/v1/agent/jobs/{job_id}` and enforce exact registration ownership while the trusted Mac UI can still display the active job.

## Routes

| Route | Purpose |
|---|---|
| `GET /v1/agent/capabilities` | Versioned schemas, all-data/all-history support, and per-page safety bounds. |
| `GET /v1/agent/profiles` | Exact profile revisions/digests granted to the authenticated client. |
| `POST /v1/agent/query` | Authorized cached query. |
| `POST /v1/agent/evidence` | Authorized factual evidence packet. |
| `POST /v1/agent/activity/query` | PHI-minimized activity pages for this registration only. |
| `POST /v1/agent/refresh` | Reserved for profile-synchronized iPhone acquisition. It currently fails closed rather than widening to iPhone settings. |
| `/v1/agent/jobs/{id}` | Owner-checked status, resume, and cancel. |

A query body pins `grant_id`, the canonical profile reference (schema, version, profile ID, revision, policy digest), a `healthmd.query_request` v1, detail level, and optional UUID correlation ID. Health.md checks the exact request against both grant and canonical profile policy, records authorization activity, and only then accesses the encrypted Mac context store. Cached queries explicitly do not pretend that the Mac can inspect HealthKit authorization.

Responses use `healthmd.query_response`, `healthmd.evidence_packet`, or `healthmd.query_error` v1. A per-page item/byte bound is advertised, but complete cursor traversal reaches every authorized result. Unknown credentials, cross-client grants/jobs, stale profile revisions/digests, paused/expired/revoked grants, and unsupported profile mappings fail closed.

Fresh acquisition remains disabled on this route until the exact profile scope can be validated and synchronized on iPhone. Returning `fresh_acquisition_requires_profile_sync` is intentional; silently using current iPhone metric settings could omit authorized data while claiming complete profile coverage.
