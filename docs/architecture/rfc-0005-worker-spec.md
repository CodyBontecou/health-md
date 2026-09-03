# RFC-0005 P2 worker specification: `healthmd-receipt-verifier` wake endpoints

- Status: **Deployed — dedicated `healthmd-wake` worker live at `healthmd-wake.costream.workers.dev` since 2026-09-03 (physical QA pending)**
- Owner: consumer notifications-worker owner (`healthmd-receipt-verifier`)
- Proposal date: 2026-09-02
- Parent: [RFC-0005: Direct CLI agent wake](rfc-0005-direct-cli-agent-wake.md)
- Scope: exactly the two wake endpoints, their verification, rate limits, storage, and
  notification delivery. Everything else the worker does today is untouched.

## Context

`healthmd-receipt-verifier` is the deployed consumer notifications worker
(`healthmd-receipt-verifier.costream.workers.dev`). It already holds the APNs credentials and the
device-token store populated by the Health.md iOS app through `PushRegistrationManager` /
`/devices/register`. RFC-0005 P2 reuses that infrastructure for agent wake: while the portable
CLI's P1 wake window is holding, the CLI asks the worker to send one visible push so the owner can
tap, unlock, and let the same in-flight request continue.

The worker never becomes a data path. All health data moves only over the authenticated
peer-to-peer direct channel; the worker is a doorbell.

## Endpoint 1: `POST /wake/register` (phone → worker)

Called by the iPhone when the owner enables **"Allow paired computers to send wake requests"**
under Sync → Direct CLI Access, and again on key rotation.

Request fields (JSON, camelCase):

| Field | Type | Notes |
|---|---|---|
| `userId` | string | Existing install identity, same key the device-token store already uses. |
| `deviceToken` | string | APNs token for this install (reuses the existing registration identity). |
| `wakeKeyVerificationHash` | string (hex) | SHA-256 over the raw 32-byte `wakeKey`. The raw key never crosses the wire. |
| `peerLabel` | string, optional | Paired computer display name recorded for notification copy, ≤ 128 bytes. |

Response:

```json
{ "wakeId": "<opaque server-assigned id>" }
```

- `wakeId` is opaque, unguessable (≥ 128 bits of entropy), and carries no pairing or health
  meaning. It is the only identifier the CLI ever learns.
- Re-registering an existing `wakeId` replaces its verification hash and token (rotation).
- `DELETE /wake/register` with `{ "userId", "wakeId" }` removes the row. Unpairing on the phone
  calls it; the phone also removes its local material in the same transaction boundary.

## Endpoint 2: `POST /wake/request` (CLI → worker)

Called by the CLI at the start of a P1 wake wait when a wake credential exists, and never more
often than the rate limits allow.

Request fields:

| Field | Type | Notes |
|---|---|---|
| `wakeId` | string | From enrollment. |
| `nonce` | string (hex, ≥ 128 bits) | Fresh per request. |
| `timestamp` | string (RFC 3339) | Reject outside a ±120 s window. |
| `hmac` | string (hex) | `HMAC-SHA256(SHA-256(wakeKey), "healthmd.wake.v1" ‖ nonce ‖ timestamp)`. The HMAC **key** is the verification hash — the registered `SHA-256(wakeKey)` — so the worker verifies requests without ever holding the raw key (see amendment). |
| `peerLabel` | string, optional | Computer display name for the notification body, ≤ 128 bytes. |

Processing order:

1. Look up `wakeId`; unknown → `404` with code `wake_unknown`.
2. Verify the HMAC: the key is the stored verification hash itself (`SHA-256(wakeKey)` raw bytes), and the message is the domain label, nonce hex, and timestamp concatenated as ASCII; compare constant-time, mismatch → `401` `wake_hmac_invalid`. (The hash-keyed HMAC proves the caller can derive the registered hash, i.e. holds the raw key, while the raw key itself never crosses the wire or rests in worker storage.)
3. Check the timestamp window; stale → `401` `wake_timestamp_stale`.
4. Dedupe: at most one delivered wake per `wakeId` per 30 s; a repeat inside the window returns
   `200` with `{"status":"deduplicated"}` (idempotent nudge, never a new authorization). A
   replayed **nonce** (any request reusing a burned nonce) is rejected with `401`
   `wake_nonce_replayed` before dedupe is considered.
5. Hourly budget: at most 6 delivered wakes per `wakeId`; beyond → `429` `wake_rate_limited`
   with `retryAfterSeconds`.
6. Send **one visible APNs push** to the stored token. Silent pushes are not used: they are
   budgeted and unreliable for suspended apps, and the tap is the deliberate consent gesture.

Notification payload:

```json
{
  "aps": {
    "alert": {
      "title": "Health.md",
      "body": "{peerLabel} is requesting data. Tap to continue."
    },
    "sound": "default",
    "category": "HEALTHMD_DIRECT_WAKE"
  },
  "healthmd": { "kind": "direct-cli-wake" }
}
```

- If `peerLabel` cannot be carried safely, fall back to `"A paired computer is requesting data.
  Tap to continue."` and record the fallback reason in an access log that contains no identity
  beyond `wakeId`.
- Tap routing (unlock → foreground → Direct CLI Access screen) is implemented by the iOS app's
  `UNUserNotificationCenterDelegate`; the worker only delivers the notification.

Response codes the CLI treats as graceful degradation (never an error surface): anything other
than a delivered/deduplicated wake simply means P1-only behavior for that wait.

## Storage sketch

KV or D1, one row per pairing:

```text
wake_id -> { user_id, wake_key_verification_hash, device_token, peer_label, created_at, rotated_at }
counters: wake_id -> { delivered_this_hour, hour_bucket, last_delivered_at }
```

Rows are keyed to the pairing, not the install; unpair removes the row regardless of token state.

## Privacy and security invariants

- The worker learns only: opaque `wakeId`, request timestamps, a coarse "a paired computer wants
  data" signal, and the paired computer's display name. It must never see dates, metric names,
  request types, or health content, and must not be able to trigger anything on the phone beyond
  the notification.
- No health payloads, request arguments, or tokens in logs, telemetry, or delivery receipts.
  No-PII assertions are part of the acceptance tests below.
- Unauthenticated wakes are impossible (per-pairing HMAC). Notification spam is bounded by the
  rate limits; revocation is immediate on unpair; rotation works without re-pairing.
- Plain HTTPS: the HMAC is the authenticator. APNs credentials stay in worker secrets and never
  appear in this repository or the CLI.

## Acceptance tests (worker scope)

- [ ] Valid HMAC delivers exactly one visible push; unknown `wakeId` → 404.
- [ ] Invalid HMAC, wrong domain string, and replayed nonce/timestamp → 401, no push.
- [ ] Timestamp outside ±120 s → 401.
- [ ] Second request within 30 s → 200 `deduplicated`, single push.
- [ ] Seventh request in an hour → 429 with `retryAfterSeconds`, six pushes total.
- [ ] Register-replace rotates the accepted key; delete removes the row and subsequent requests
      return 404.
- [ ] Body of every delivered notification and every log line matches the allowlist above
      (no metrics, dates, counts, or request contents).
- [ ] Rate-limit and dedupe counters are scoped per `wakeId`, never per IP.

## Explicitly out of scope

- The `wakeEnrollment` control message and hello capability bit (phone ↔ CLI, defined in
  [packages/contracts/direct-protocol/v1/protocol.md](../../packages/contracts/direct-protocol/v1/protocol.md),
  staged as planned).
- CLI-side credential storage and wake POST (in `apps/cli` once these endpoints exist).
- Android/FCM transport (P3; the row schema already accommodates a transport token).
- Any change to the existing `/devices/register` or scheduled-export paths.

## Amendment (2026-09-03): HMAC key and deployment topology

Two corrections, both forced by implementation reality and recorded in the RFC decision log
(entry 4):

1. **HMAC key.** The original text keyed the HMAC with the raw `wakeKey` while registration
   stores only its SHA-256 — a construction the worker cannot verify. The HMAC is now keyed by
   the registered verification hash itself (`SHA-256(wakeKey)` raw bytes). The CLI derives the
   key identically; the construction is pinned cross-language (Rust test in
   `apps/cli/crates/healthmd-client/src/wake.rs`, worker test in the `healthmd-wake` repository)
   with the shared vector raw key `[7;32]`, nonce `"aa"`, timestamp `2026-09-03T00:00:00Z` →
   `b7575fa94db932357824b886ac6b23d17eaed58048ee346622fa2add58d2138f`.
2. **Deployment.** The `healthmd-receipt-verifier` worker's source was lost with an old machine,
   and reconstructing a production paywall/scheduling worker blind was rejected. The wake
   endpoints ship as the dedicated `healthmd-wake` script (`healthmd-wake.costream.workers.dev`,
   own D1 `healthmd-wake` database, own APNs secret bindings); the receipt-verifier stays frozen
   and untouched. Supersedes the original "extends the existing worker" framing and RFC-0005
   decision 3.
