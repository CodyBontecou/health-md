# healthmd-wake

RFC-0005 P2 wake doorbell for Health.md direct CLI access:
`https://healthmd-wake.costream.workers.dev`

While the portable CLI's P1 wake window is holding, the CLI asks this worker to
send **one visible push** so the owner can tap, unlock, and let the same
in-flight request continue. The worker never becomes a data path — all health
data moves only over the authenticated peer-to-peer direct channel.

An additive **Worker-only FCM HTTP-v1 v2 extension** is locally implemented and
tested. Android P3/B15 remains planned/incomplete: native/CLI integration,
security review, authorized configuration/deployment, and physical notification
QA have not been completed. APNs P2 remains the deployed default.

## Provenance

The wake endpoints were originally specified to extend the
`healthmd-receipt-verifier` worker ([decision 3, RFC-0005](../../docs/architecture/rfc-0005-direct-cli-agent-wake.md)).
That worker's source was lost with an old machine (2026-09-03), so rather than
reconstruct a production paywall/scheduling worker blind, wake ships as this
self-contained script. Its original four commits were imported unsquashed into
`apps/wake` on 2026-09-04, making this monorepo the canonical source. The
receipt-verifier keeps serving `/verify-legacy*`, `/devices/register`, and
`/schedules/upsert` untouched and frozen.

## Endpoints

Full contract: [`docs/architecture/rfc-0005-worker-spec.md`](../../docs/architecture/rfc-0005-worker-spec.md)
(with the 2026-09-03 HMAC-key amendment below).

| Route | Method | Purpose |
|---|---|---|
| `/health` | GET | Liveness: `{"ok":true,"service":"healthmd-wake"}` |
| `/wake/register` | POST | Phone enrolls (or rotates) wake material; returns `{"wakeId":...}` |
| `/wake/register` | DELETE | Unpair revoke; idempotent |
| `/wake/request` | POST | CLI's unchanged v1 HMAC-authenticated APNs ring |
| `/wake/v2/register` | POST | Explicit FCM enrollment/rotation with phone-only management proof |
| `/wake/v2/register` | DELETE | Cryptographically authenticated v2 revocation |
| `/wake/v2/request` | POST | V2 domain-separated FCM ring; fixed generic visible copy |

The Worker-local v2 contract, proof vectors, private configuration, bounds,
official sources, and remaining gates are in [`docs/fcm-v2.md`](docs/fcm-v2.md).
Legacy endpoints do not reinterpret APNs tokens or manage v2 resources.
Unapproved body fields are rejected; no health arguments or arbitrary provider
payloads are accepted.

**Legacy security:** initial registration is not account/install authentication.
V1 rotation/revocation use opaque identifiers, not a cryptographic owner proof;
`userId` alone is not authentication. The registered verification hash is itself
a bearer HMAC secret. V2 adds a separate phone-only management hash/proof without
altering v1 transcripts. See the extension document for the retained legacy
limitations and self-authenticated v2 bootstrap limitations.

### HMAC construction (2026-09-03 amendment)

`hmac = HMAC-SHA256(key = SHA-256(rawWakeKey), msg = "healthmd.wake.v1" ‖ nonce_hex ‖ timestamp_rfc3339)`

The HMAC key is the **verification hash** the phone registered — the raw wake
key never crosses the wire to the worker (RFC-0005 privacy invariant). The
original spec text said "over the raw 32-byte key", which is unverifiable from
a hash-only store; the amendment is pinned cross-language in:

- [`apps/cli/crates/healthmd-client/src/wake.rs`](../cli/crates/healthmd-client/src/wake.rs)
  (Rust, `hmac_is_domain_separated_and_deterministic`)
- `src/wake.test.ts` (this Worker, "pinned wake HMAC")

Shared vector: raw key `[7;32]`, nonce `"aa"`, timestamp `2026-09-03T00:00:00Z`
→ `b7575fa94db932357824b886ac6b23d17eaed58048ee346622fa2add58d2138f`.

## Policy

- Unknown `wakeId` → `404 wake_unknown`; bad HMAC → `401 wake_hmac_invalid`;
  stale timestamp (±120 s) → `401 wake_timestamp_stale`; replayed nonce →
  `401 wake_nonce_replayed`.
- ≤ 1 delivered wake per `wakeId` per 30 s (repeats return `200 deduplicated`);
  ≤ 6 delivered per hour (`429 wake_rate_limited` with `retryAfterSeconds`).
  Counters are scoped per `wakeId`, never per IP.
- Visible alert push (category `HEALTHMD_DIRECT_WAKE`), 5-minute expiration.
  Only delivered pushes consume budget; APNs failures return `200 undeliverable`.
- Storage: D1 (`healthmd-wake`) — registrations, counters, replay nonces.
  No health payloads, request arguments, or tokens in logs.

## FCM extension staging

New migration `0002_fcm_v2.sql` is forward-only. Existing registrations and legacy
inserts keep APNs/v1 defaults. The optional private `FCM_SERVICE_ACCOUNT_JSON`
binding is not provisioned here: absent/malformed FCM configuration contacts no
provider and leaves APNs functional. OAuth and notification state are
request-local; provider responses/exceptions and tokens are never logged.

FCM sends only a fixed visible notification, not a data message. It uses a normal
tap-to-open action, no full-screen intent, hidden service start, silent capture,
or lifecycle bypass. "Delivered" means provider acceptance, not device display.
Native channel/action creation, consent/permission/services gating, protected
credentials, CLI v2 signing, and Play/F-Droid degradation are still later gates.
Do not deploy this extension or claim Android push availability from this slice.

## Deploy

Deploy only committed and pushed `origin/main` source from `apps/wake`. The D1 database already
exists; creation is a one-time disaster-recovery operation, not a normal release step.

```sh
npm ci
npm test
npm run check
wrangler d1 migrations apply healthmd-wake --remote
wrangler secret put APNS_AUTH_KEY           # .p8 PEM body — user sets, never committed
wrangler secret put APNS_KEY_ID
wrangler secret put APNS_TEAM_ID
wrangler deploy
```

`APNS_HOST` defaults to production (`api.push.apple.com`). Flip to
`api.sandbox.push.apple.com` (var in `wrangler.toml`) when testing against a
development-signed build, and back before TestFlight/App Store QA.

## Tests

```sh
npm ci
npm test        # legacy vectors/HTTP compatibility; mocked FCM/OAuth;
                # v2 management, replay, rate/dedupe/concurrency, privacy/bounds;
                # local workerd/D1 with all outbound traffic intercepted
npm run check
npm exec -- wrangler deploy --dry-run --outdir .wrangler/dry-run
```
