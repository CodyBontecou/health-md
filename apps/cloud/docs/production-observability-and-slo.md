# Production observability and SLO contract

Status: source-ready, not deployed. This contract applies only to future split-profile production resources. It does not authorize a rollout or change the live VM pilot.

## Health-data-free telemetry schema

Each Worker writes an optional Analytics Engine data point with exactly:

| Field | Allowed values |
|---|---|
| `index1` | `ingest`, `account`, or `maintenance` |
| `blob1` | fixed route class, reviewed account-security event, or maintenance event |
| `blob2` | HTTP status class (`2xx`–`5xx`) or maintenance outcome (`ok`, `retry`, `failed`) |
| `blob3` | fixed latency bucket: `<50 ms`, `50–249 ms`, `250–999 ms`, `1–4 s`, `5–14 s`, or `>=15 s` |
| `blob4` | fixed ingest `Content-Length` bucket, `unknown`, or `not_applicable` |
| `double1` | constant `1` |

No URL, query string, account/session/token/export ID, IP, email, user agent, cookie, authorization value, object key, owner date, metric name/value, request/response body, exception text, exact byte count, or exact duration is permitted. Route classes are static and discard path parameters. Telemetry failures are swallowed without logging and never change a health-data request result. The production profiles set `HEALTH_FREE_METRICS_REQUIRED=1`; startup validation fails closed if the dataset binding is absent. Dataset access is limited to the operations deployment identity. Retention must be set to the shortest provider-supported period consistent with incident response and approved before provisioning.

Cloudflare request/security logs, Trace Events, Logpush, Workers Logs and third-party alert payloads are separate disclosure surfaces. Leave request-body logging off. Do not enable sampled invocation logs until a privacy review proves that headers, URLs and exceptions are redacted. Alerts may contain only service, fixed route class, status/outcome, threshold and time window.

## Provisional SLOs for the 100-user beta

These targets are provisional until the product and operations owners approve them and staging load evidence exists.

| Signal | Objective over rolling 30 days | Alert |
|---|---|---|
| Authenticated ingest availability | >=99.9% non-5xx responses for `export_ingest`; client 4xx excluded | page at >=2% 5xx for 5 min with >=20 events; ticket at >=0.2% for 1 h |
| Account API availability | >=99.9% non-5xx API responses; static assets and client 4xx excluded | page at >=2% 5xx for 5 min with >=20 events |
| Ingest admission pressure | <1% 429 responses outside an announced load test | page at >=5% for 5 min; ticket at >=1% for 30 min |
| Ingest latency | >=95% below 5 s and >=99% below 15 s, evaluated from buckets | page when `gte_15s` >=1% for 10 min with >=20 successes |
| Eligible-email send budget | no exhaustion outside a declared abuse/load exercise | ticket on any `email_budget_exhausted`; page if repeated in three 5-min windows |
| Magic-link persistence | no failed durable-link postcondition | page on any `magic_link_persistence_failed`; investigate D1 without inspecting identities |
| Lifecycle queue | no `failed`; retry returns to zero within 15 min | page on any `failed` or retries in three consecutive 5-min windows |
| Scheduled maintenance | one `ok` each scheduled interval; deletion jobs and independent credential/audit/revision/deletion-receipt expiry, reconciliation and rotation phases continue through peer failure; auth cleanup pages are capped at 500 links, 500 sessions, 50,000 decisions and 5,000 buckets/run; one identifier-free aggregate `failed` follows all eligible work | page after two missed/failed intervals; page on provider evidence that expiry backlog cannot catch up at 2x load |

A 429 caused by the documented two-active-upload account limit is correct load shedding, but sustained aggregate 429 rates still require investigation. Never relax quota/concurrency safety solely to clear an alert.

## Dashboards and queries

Build aggregate panels grouped only by `index1`, `blob1`, `blob2`, `blob3`, `blob4`, and time bucket. Do not join telemetry to D1, R2, authentication, billing or edge request datasets. Required panels:

1. request count and status class by profile/route class;
2. ingest latency and coarse size buckets;
3. ingest 429 and 5xx ratios;
4. account API 5xx ratio and fixed email-budget/persistence events;
5. maintenance outcomes;
6. provider-native D1 latency/error, R2 error, Queue backlog/DLQ and Worker CPU/subrequest limits, with no request dimensions.

Each alert needs a primary and backup on-call owner, a tested notification channel, an acknowledgement target, and the linked runbook. Deployment and rollback checks must record that all served `/health` responses report the expected 12-character revision; the full 40-character SHA remains in deployment evidence and runtime configuration. Do not put tokens or customer information in ticket/chat systems.

## Health-free incident procedure

1. Declare severity from aggregate impact; do not inspect payloads.
2. Check deployment revision, Worker/provider status, D1/R2/Queue aggregate health, quota pressure and the fixed telemetry panels.
3. Stop a rollout or disable new invitations before increasing limits. Keep authenticated reads, deletion and token revocation available when safe.
4. If ciphertext or account-specific diagnosis is unavoidable, use the separately approved audited break-glass procedure; this source milestone does not define or authorize one.
5. Record only times, aggregate counts, fixed error classes, mitigations and code/config revisions.
6. Verify recovery against synthetic accounts, replay idempotency, unauthenticated denial and queue reconciliation.
7. Complete a health-data-free incident review and track corrective tests.

## Staging qualification gate

Use only clearly synthetic accounts and reserved-domain identities. Before each cohort increase:

- exercise 2x the cohort's forecast peak for 30 minutes and the expected sustained rate for 2 hours;
- include concurrent same-account uploads, cross-account uploads, retries, disconnects, 25 MiB boundary rejection, D1/R2 transient faults, Queue retry/DLQ, deletion during upload and expired-intent reconciliation;
- verify no successful upload exceeds account quota, no account exceeds two active intents, no plaintext reaches D1/logs/telemetry, and all accepted receipts are readable byte-for-byte;
- save only aggregate test reports and infrastructure revision IDs;
- confirm alert delivery and operator acknowledgement; and
- stop if 5xx, latency, quota-ledger drift, orphan ciphertext, or provider-limit evidence misses the targets above.

Production load testing, real-account synthetic probes, broad tracing, and any telemetry retention change require separate approval.
