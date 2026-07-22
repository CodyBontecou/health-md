# Authenticated local agent API

## Boundary

Health.md's generic agent routes live under `/v1/agent/` on the existing IPv4/IPv6 loopback listener. Loopback remains a network boundary, not caller identity. Every agent route requires:

```http
Authorization: Bearer <registration-uuid>.<one-time-random-secret>
X-HealthMd-Surface: local_control_api | command_line | mcp_stdio
```

Direct API clients may omit the surface header and default to `local_control_api`. The bundled CLI and MCP helper set their exact adapter surface. Unknown surfaces fail closed. The bearer remains the identity/authority; the surface selects only among surfaces already present in the pinned profile and cannot widen its metrics, providers, dates, detail, operations, destinations, or grant.

The registration UUID selects exactly one Keychain account. Health.md compares the 32-byte secret in constant time, rejects revoked registrations, and never scans or labels an unknown loopback process as an authenticated agent. Credentials are shown once by the Mac UI, rotate in Keychain, and never enter access/activity JSON.

Legacy `/v1/exports` routes remain honestly unattributed during migration. They cannot inspect, resume, or cancel jobs owned by registered agents. Authenticated job controls use `/v1/agent/jobs/{job_id}` and enforce exact registration ownership while the trusted Mac UI can still display the active job.

## Routes

| Route | Purpose |
|---|---|
| `GET /v1/agent/capabilities` | Versioned schemas, all-data/all-history support, and per-page safety bounds. |
| `GET /v1/agent/profiles` | Exact profiles plus copyable `profile_reference` revisions/digests granted to the authenticated client. |
| `POST /v1/agent/query` | Authorized cached query. |
| `POST /v1/agent/evidence` | Authorized factual evidence packet. |
| `POST /v1/agent/activity/query` | PHI-minimized activity pages for this registration only. |
| `POST /v1/agent/refresh` | Starts profile-synchronized, owner-bound acquisition on the connected open iPhone. |
| `/v1/agent/jobs/{id}` | Owner-checked status, resume, and cancel. |

A query body pins `grant_id`, the canonical profile reference (schema, version, profile ID, revision, policy digest), a `healthmd.query_request` v1, detail level, and optional UUID correlation ID. Health.md checks the exact request against both grant and canonical profile policy, records authorization activity, and only then accesses the encrypted Mac context store. Cached queries explicitly do not pretend that the Mac can inspect HealthKit authorization.

Responses use `healthmd.query_response`, `healthmd.evidence_packet`, or `healthmd.query_error` v1. A per-page item/byte bound is advertised, but complete cursor traversal reaches every authorized result. Unknown credentials, cross-client grants/jobs, stale profile revisions/digests, paused/expired/revoked grants, and unsupported profile mappings fail closed.

Fresh acquisition resolves and pins the exact profile revision, policy digest, runtime metric/provider catalog, detail level, and requested date policy before a durable job is created. It is encrypted query-context synchronization rather than a file export action, so it does not consume or mutate iPhone file-export quota/history; authorization and outcome are recorded in the separate agent activity ledger. Current peers capability-negotiate this behavior. The dedicated `encrypted_context` corpus mode is separate from file destinations: it writes no Markdown/JSON/CSV files and never inherits saved format or folder choices. The iPhone persists the policy in its recovery journal, derives request-scoped metric/detail settings without mutating saved export preferences, and includes every connected provider authorized by the dynamic source policy. When Apple Health is selected, it verifies that the user has made a HealthKit authorization decision for every current ordinary read type. All-history resolution combines the complete Apple Health catalog boundary with provider-native cursor discovery; provider-only profiles do not require or read HealthKit. Legacy peers fail with `unsupported_profile_scoped_export` rather than silently falling back to saved iPhone settings.

Agent jobs persist both registration and grant ownership. Another registration receives no status and cannot resume or cancel them. Resume additionally requires the owning grant to remain active; cancellation stays available to the owner for safe cleanup. Completed captured days are projected deterministically and committed to the Keychain-encrypted Mac context store before the transport partition receives its application-level acknowledgement.
