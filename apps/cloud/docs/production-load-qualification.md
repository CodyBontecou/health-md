# Production staging load and cost qualification

Status: executable source procedure only. It has **not** been run against Cloudflare or any approved staging resource and is not production evidence.

## Gate

Before the 1,000-user cohort, qualify the exact reviewed split-Worker revision at twice the provisional target:

- 500 simultaneous compatibility uploads;
- 50 launched uploads/second for 600 seconds;
- ten simultaneous exact 25 MiB compatibility envelopes;
- zero unexpected HTTP/transport failures;
- at least 98% of the planned launch rate; and
- measured Worker CPU/memory, D1 contention, R2 latency, Queue health, per-account admission, cost and health-free alert behavior within approved limits.

The source harness tests request-path capacity. It does not by itself prove Cloudflare quotas, cost acceptability, regional behavior, restoration, mobile behavior or security.

## Safety prerequisites

Obtain named operations, security and product authorization for a disposable **synthetic-only** staging environment. Record the exact 40-character deployed Git revision and verify its split-profile `/health` response. Never point this harness at the pilot or a production hostname; it refuses the known live hosts and requires a hostname containing a distinct `staging` or `synthetic` label.

Provision at least 639 disposable synthetic accounts, each with one distinct write-only ingest token. This count keeps the default run at no more than 50 requests/account: two concurrent-wave requests, at most 47 sustained requests and one large probe. Do not reuse a token/account or raise production abuse budgets merely to obtain a pass. Put one token per line in an owner-only file:

```bash
chmod 600 /owner-only/path/synthetic-ingest-tokens
```

The file must not enter the repository, shell history, CI artifacts, chat, logs or reports. The operator attests that every token belongs to a different disposable synthetic account. The harness validates file mode, syntax, uniqueness and count but cannot independently infer token ownership.

Budget approximately 30,510 requests and at least 281 MiB of plaintext input for the default run, plus encryption/storage/database/provider overhead. Confirm D1/R2/Analytics Engine/Queue quotas and an approved teardown plan before starting. Do not run concurrent drills.

## Execute

Set secrets through the operator's secret-injection mechanism rather than inline shell history. Required environment variables:

- `HEALTHMD_LOAD_ENDPOINT` — exact credential-free staging URL ending `/api/v1/exports`;
- `HEALTHMD_LOAD_EXPECTED_REVISION` — reviewed full lowercase 40-character SHA;
- `HEALTHMD_LOAD_TOKEN_FILE` — owner-only token file path;
- `HEALTHMD_LOAD_CONFIRM_SYNTHETIC_ONLY=SYNTHETIC_ONLY`;
- `HEALTHMD_LOAD_DISTINCT_ACCOUNTS=YES`.

Then run from `apps/cloud`:

```bash
npm run qualify:staging-load > staging-load-report.json
```

Defaults are the complete 2× gate. The bounded `HEALTHMD_LOAD_CONCURRENCY`, `HEALTHMD_LOAD_UPLOADS_PER_SECOND`, `HEALTHMD_LOAD_DURATION_SECONDS`, and `HEALTHMD_LOAD_LARGE_CONCURRENCY` overrides are for rehearsal only; a reduced run is not acceptance evidence.

Payloads are obvious synthetic Apple-v8 compatibility envelopes dated 2020-01-01, contain no person or real health value, and vary only by a synthetic marker/padding. The report contains the 12-character revision, account/request counts, fixed HTTP status classes, aggregate latency percentiles, launch rate and pass/fail. It never includes endpoint, token, payload, response body, export ID, account ID or object key.

## Observe and accept

During the run, capture provider-native evidence for:

1. Worker wall/CPU time, memory/exceptions and isolate pressure per split service;
2. D1 lock/error/latency behavior and durable upload-intent/account-quota invariants;
3. R2 write/delete latency, object count and cost projection at 1×/2×/10,000 accounts;
4. Analytics Engine availability and fixed-bucket alert delivery;
5. no logs containing authorization, URL, account/object/export IDs, dates, values or bodies;
6. no active reservation over two for any synthetic account and no leaked reservations after completion;
7. bounded orphan reconciliation after an approved fault-injection pass;
8. after the two-hour decision expiry horizon, provider-native proof that five-minute maintenance with the 50,000-row decision page reduces rather than accumulates the 2x rate-limit-attempt backlog, including D1 latency and cost; and
9. exact deployed revision and configuration snapshot.

A harness `pass` is necessary but not sufficient. Operations and security owners must sign the provider evidence and cost model. Any 401/403/408/429/5xx, transport timeout, revision mismatch, missing telemetry, quota violation, health-data-bearing log or unexplained object/intent discrepancy fails the gate.

## Teardown

Stop before cleanup if evidence is incomplete. Using reviewed account-deletion/provider procedures, disable the synthetic credentials, process ciphertext-first deletion, verify D1 metadata and R2 ciphertext removal/reconciliation, and delete only the disposable staging resources named in the authorization. Never use broad bucket/database deletion or prune pilot/production resources. Remove the local token file after verifying revocation; retain only the health-free aggregate report, provider metrics and signed decision in the approved evidence store.
