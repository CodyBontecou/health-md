# RFC-0005: Direct CLI agent wake — tap-to-unblock a locked phone

- Status: **Accepted for staged rollout — P1 implemented, with basic iPhone/Android connectivity owner-confirmed and the full wake matrix pending; P2 implemented in-repo with the `healthmd-wake` worker deployed and enabled in every current-main CLI build (end-to-end notification QA pending); P3 planned**
- Proposal date: 2026-09-02
- Owners required for acceptance: Apple, Android, CLI, contracts, shared core, security/privacy, product/support, and the consumer notifications-worker owner
- Related: [Cross-platform unification policy](cross-platform-unification-policy.md), [direct protocol contracts](../../packages/contracts/direct-protocol/README.md), [RFC-0004](rfc-0004-unified-health-data-v9.md)

## Problem

An agent or CLI user runs `healthmd` (typically `healthmd mcp serve` behind Codex/another MCP host) on a computer while the paired phone is locked or put away:

1. **iOS:** locking the phone moves the app to the background and iOS suspends it within seconds. The TCP listener on port 17647 stops executing, so new connections cannot be accepted at all. The service answers `appActive: false` only in the narrow window where it still has background execution time; a suspended app cannot answer anything. New work is rejected with "Reopen Health.md before starting another command" (`IPhoneDirectCLIService.swift`), and only an already-active export may continue on finite `beginBackgroundTask` time.
2. **Android:** `DirectCliForegroundService` keeps the listener alive while the device is locked, so an active direct session keeps working. The gaps are: the direct session/service is not running, the app process is gone, or Health Connect reads reject with `DEVICE_LOCKED` before the first unlock since boot (`DirectCliCoordinator.kt`).

Today the agent receives a deterministic guidance error ("Keep Health.md foreground with Direct CLI Access enabled") and the user must unlock the phone, open Health.md, and ask the agent to re-run. The re-run requirement is the friction this RFC removes.

**The hard constraint that shapes the design:** while an iOS app is suspended, nothing on the phone can observe that a request arrived. A request-triggered local notification is impossible without an external wake signal. Only APNs can deliver one.

## Goals

1. A paired CLI/MCP request that finds the phone unavailable holds open for a bounded window and proceeds automatically once the phone becomes available — no re-run needed.
2. While the phone is locked, the owner receives a health-free notification: *"a paired computer is requesting data"* — tapping it foregrounds/unlocks the phone and unblocks the waiting request.
3. The tap is the existing user-presence surface. Foreground-only new work, HealthKit/Health Connect permission ownership, peer-to-peer data flow, and pairing trust are unchanged.
4. Apple and Android expose the same user outcome per the unification policy, with platform differences recorded explicitly.

## Non-goals

- No background data capture. The phone still refuses new work unless foregrounded (iOS) or the direct foreground service is active (Android). The wake only restores the current consent model, never bypasses it.
- No change to direct application protocol v1/v2/query v3 packets, transfer framing, or pairing transcripts (selectors 1/2/3 bytes stay frozen).
- No new MCP tool surface, no shell/URL/file capabilities, no Mac-app dependency.
- No health data, metric names, dates, or request contents in the wake path, the worker, or any notification.
- No changes to `apps/practice` (consumer-only feature).

## Design overview

Three independently shippable phases:

| Phase | Scope | Infra |
|---|---|---|
| P1 — Wake window | Rust CLI/MCP holds a request and retries instead of failing fast | None |
| P2 — iOS wake notification | Opt-in APNs wake via the dedicated notification-only Worker; tap → foreground → P1 window completes | APNs + `apps/wake` |
| P3 — Android parity | FCM high-priority wake; tap → unlock → start direct session; F-Droid degradation documented | FCM |

P1 alone removes the re-run friction. P2/P3 add the notification so the user knows a request is waiting without watching the computer.

The `direct.cli_agent_push_wake` capability addition refreshes the internal shared metric-registry
identity and its registry-bound synthetic fixtures. It does **not** change Apple export schema v8,
Android frozen v4 or analytical v5, direct application protocols v1/v2, query protocol v3, secure
framing, or pairing selectors/transcripts.

## P1 — CLI/MCP wake window (shared, both platforms)

Behavior change in `apps/cli` (`healthmd-client/src/direct.rs`, MCP direct adapter in `healthmd-cli/src/mcp`):

- When a query/export/resume/cancel operation finds the source **unreachable** (connect timeout/refused) or answers `app_active: false`, enter a bounded wait instead of returning the guidance error immediately:
  - reuse the existing reconnect backoff (250 ms → 2 s) to re-attempt connection;
  - total window default **120 seconds**, overridable per command (`--wake-timeout <SECONDS>`, `0` disables) and for MCP via environment (`HEALTHMD_WAKE_TIMEOUT`);
  - the window is cancellable at every point; MCP cancellation requests interrupt the wait immediately (existing cancellation semantics are preserved — local interrupt ends the wait with a deterministic error, it is never confused with a terminal phone-side cancellation);
  - emit MCP `notifications/progress` at wait start and every ~10 s, so agents can relay status to the user; mention a notification only when the selected device has enrolled wake material, otherwise instruct the owner to open Health.md.
- On success: proceed exactly as if the phone had been available from the start. No behavioral difference in results, receipts, or errors.
- On expiry: return today's deterministic `healthmd.cli_guidance` / `direct_source_unavailable` outcome, unchanged bytes, plus `wake_window_seconds` as an additive guidance field.
- `healthmd status` output gains an additive `wake_window` object (enabled, timeout, enrollment state from P2/P3). The wake window and its state are implemented once in the CLI crates; the MCP server calls that same function and surfaces its output as an additive `wake` object in `healthmd.direct_readiness` plus the wait progress notifications. There is no parallel MCP-side wake implementation and no dedicated `healthmd_wake` tool.

Pure local change; no protocol or phone work required. Immediately useful even without push: the user sees "open Health.md", does so, and the in-flight tool call completes.

## P2 — iOS APNs wake

Resolved (amended 2026-09-03 and 2026-09-04, decisions 5–6): wake endpoints ship as the dedicated [`apps/wake`](../../apps/wake) Worker (`healthmd-wake.costream.workers.dev`, own D1, own APNs secret bindings) because the `healthmd-receipt-verifier` source was lost with an old machine and reconstructing a production paywall/scheduling worker blind was rejected. The Worker and its unsquashed history now live in the canonical monorepo; the receipt-verifier stays frozen and untouched. Rate limits are enforced per `wake_id` to isolate abuse. The full endpoint, verification, rate-limit, and notification contract is specified in [rfc-0005-worker-spec.md](rfc-0005-worker-spec.md).

### Enrollment (opt-in, from the phone)

- New user setting under Sync > Direct CLI Access: **"Allow paired computers to send wake requests"** (default off). Enabling it requests notification permission if not yet granted (`UNUserNotificationCenter.requestAuthorization`; today permission is only requested when scheduling is enabled).
- On a connected, authenticated v1 channel, the iPhone sends an additive, capability-gated control message (a `wakeEnrollment` message negotiated via a new hello-capabilities bit — the same pattern query v3 used on v1; no pairing transcript bytes change). The message carries:
  - `wake_id`: opaque server-assigned identifier (the worker already holds APNs device tokens keyed by install `userId` from `PushRegistrationManager`/`/devices/register`; wake registration extends this with a per-pairing row);
  - `wake_key`: fresh 256-bit random secret, domain-separated from all pairing/channel secrets (generated for this purpose only, never derived from the 32-byte pairing secret).
- The phone registers `wake_id`, the wake-key verification hash, and its APNs token with the worker (`/wake/register`). The CLI stores `wake_id` + `wake_key` in the native credential store (`healthmd-client/src/credentials.rs`: Keychain / Secret Service / Windows Credential Manager) next to the pairing trust, under the same peer binding. Unpairing deletes both sides' material; the phone also deletes the worker row. A manual "rotate wake key" re-runs enrollment.

### Wake flow

1. A P1 wait starts and a wake credential exists → CLI POSTs to the worker `/wake/request`: `{wake_id, nonce, timestamp, hmac_sha256(sha256(wake_key), domain || nonce || timestamp), peer_label}`. The HMAC key is `SHA-256(wakeKey)` — exactly the registered verification hash — so the worker never holds the raw key (2026-09-03 amendment; see decision 4). Plain HTTPS; no health data, no dates, no metric identity. `peer_label` is the computer's device name only (the same name already shown in the phone's pairing UI).
2. Worker verifies the HMAC (keyed by the registered verification hash), enforces a rate limit (e.g., ≤ 6 wake requests per `wake_id` per hour, deduplicated to ≤ 1 per 30 s), then sends a **visible** APNs push to the registered token. Visible, not silent: silent pushes to suspended apps are budgeted and unreliable, and a visible notification is the required UX anyway.
3. Notification: *"Health.md — {paired computer name} is requesting data. Tap to continue."* The requesting computer's device name is included (resolved decision); request contents, metrics, and dates never are. If the transport cannot carry a device name safely, fall back to generic copy and record the reason. Tapping authenticates the unlock (Face ID/passcode), foregrounds the app, and routes to the Direct CLI Access screen via `UNUserNotificationCenterDelegate`.
4. The app becoming active starts the listener/reconnect loop as it does today; the CLI's P1 retries connect within its window and the request proceeds. If the window expired first, the agent re-runs and the phone is already ready — still a strict improvement over today.
5. Degradation is graceful: no credential, no notification permission, no worker reachability, or opt-out (`--no-wake`) → P1-only behavior. The data path never depends on the worker.

### Invariants preserved

- The tap is user presence, not data authorization: the app enforces exactly the rules it enforces when opened manually. No new silent or background authorization path exists.
- All health data still moves only over the authenticated peer-to-peer channel. The worker sees an opaque `wake_id` and a timestamp — less metadata than the existing scheduled-export registration already carries.
- Wake keys never cross the wire unencrypted and are never reused for channel authentication (domain separation).

## P3 — Android parity

Same user outcome — *"a paired computer is requesting data; tap to unblock"* — mapped onto Android's different runtime reality:

- **Listener while locked:** an active `DirectCliForegroundService` already accepts new work while the device is locked, so P1 alone largely covers Android when a direct session is active. The wake notification covers the real gaps:
  1. the direct session/service is not running (process recycled or killed);
  2. `DEVICE_LOCKED` — Health Connect rejects reads before the first unlock since boot;
  3. the app process is gone entirely.
- **Wake channel:** FCM high-priority data message (needs Google Play services). Android 12+ foreground-service launch restrictions mean the receiver must not start the data-sync service directly from the background; instead it posts a heads-up/full-screen-intent notification with the same health-free copy. Tapping it shows the keyguard unlock prompt, opens the Direct CLI screen, and starts the session. The P1 window on the CLI then completes.
- **Force-stopped apps:** Android does not deliver FCM to force-stopped apps. This is a permanent platform limitation: record it as `unavailable` with the OS reason rather than fabricating parity. The persistent-direct-session notification remains the user's manual path.
- **F-Droid channel:** FCM is Google-proprietary and absent from F-Droid builds. Channel-gated behavior mirrors the existing `DistributionDirectRawRequestPolicy` split: Play builds get wake; F-Droid builds report wake unavailable and degrade to P1 plus the existing foreground-service notification. Classification must be recorded per channel, not silently omitted.
- **Enrollment/revocation:** same opt-in setting, same wake-key protocol and worker endpoints (the worker is platform-neutral; it only stores `wake_id`, verification hash, and a transport token — APNs or FCM). Storage uses the existing direct trust store (`DirectCliTrustStore`), never plaintext.

## Privacy and security review checklist

- Worker learns: `wake_id` (opaque), request timestamps, and a coarse "paired computer wants data" signal. It must not learn dates, metrics, request types, or health content, and must not be able to trigger anything on the phone beyond the notification.
- Spoofing/spam: unauthenticated wakes are impossible (HMAC with per-pairing key); rate limits bound notification spam; `wake_id` revocation on unpair; key rotation without re-pairing.
- Replay: timestamp window + per-`wake_id` dedupe; a repeated wake is an idempotent nudge, never a new authorization.
- Notification content rules: static copy plus the paired computer's device name (resolved decision), never request contents, metric names, dates, or counts. Lock-screen privacy is the default presentation.
- No health payloads in worker logs, telemetry, or notification delivery receipts (repo-wide invariant).
- The consumer worker remains outside the clinical boundary; `apps/practice` is untouched.

## Protocol and contract impact

- **No version bumps** to application v1/v2, query v3, pairing profile v3, or transfer framing. The wake enrollment is an additive, capability-gated control message on the connected authenticated channel; old peers simply never exchange it and fail closed to no-wake (P1 still works).
- Normative text and fixtures for the new control message and capability bit land in `packages/contracts/direct-protocol/` (additive sections; existing fixture bytes unchanged) **before** implementation, per the protocol-first workflow.
- Rust-side credential storage additions stay inside `healthmd-client`; no protocol-crate networking.
- Capability classification (per the unification policy): new entry `direct.cli_agent_wake`, classification `shared`, with platform states set per phase — P1 ships `shared` (CLI-side, both platforms benefit identically); P2 sets apple `available`; android stays `planned` with a concrete target until P3, then `available` with the F-Droid channel and force-stop limitations recorded as `unavailable` reasons in `packages/contracts/product-capabilities.json`.

## Alternatives considered

- **Local notification from the suspended app** — impossible; a suspended app cannot observe the request. Only viable inside the finite background-task window of an already-active export, which is not the scenario.
- **Silent push as primary mechanism** — throttled and unreliable for suspended apps; also removes the deliberate tap-to-consent gesture. Visible notification chosen.
- **Background keep-alive hacks (audio/VoIP/Location background modes)** — App Store policy violations, battery cost, and against the product's foreground-consent model. Rejected.
- **CLI sending APNs directly (embedded provider key)** — requires distributing the team's APNs private key with an open-source CLI. Non-starter.
- **Wait-only (P1) as the whole feature** — keeps friction of the user noticing; kept as the graceful degradation path.

## Test plan (summary)

- Rust: wake-window unit/integration tests against the fake peer (connect-refused, `app_active: false`, late success, expiry, cancellation mid-wait, `--wake-timeout 0`), MCP progress/cancel behavior, credential storage round-trip for wake material, guidance-error byte compatibility on expiry.
- Swift: enrollment control-message handling, capability gating, notification permission flow, delegate tap routing to Direct CLI Access, health-free notification copy assertions, unpair deletes wake material.
- Worker (`apps/wake`): HMAC verification, rate limit, dedupe, no-PII payload assertions, type-check, and a Wrangler dry-run bundle in component CI.
- Android: FCM receiver posts notification (not a direct FGS start), tap starts session, `DEVICE_LOCKED` recovery via tap, F-Droid channel reports unavailable, trust-store persistence.
- Physical QA: locked iPhone on LAN and Tailscale end-to-end (notification → tap → query completes inside the window); notification permission denied; unpair revocation; locked Android with/without active session; before-first-unlock-since-boot; force-stopped app documented limitation.

## Rollout

1. P1 (Rust only) + docs/skill updates — shipped in alpha.6; iPhone and Android pairing/connectivity physically confirmed, with the full retained release matrix still pending.
2. Contracts (additive sections) → worker endpoints → iOS enrollment/notification → CLI wake POST — implemented. Current `main` includes the worker client and canonical production URL in every CLI build; the next CLI release carries that default. iOS 3.3.0 is `READY_FOR_SALE`; end-to-end notification QA remains pending.
3. Android FCM + channel policy — planned P3; Play/F-Droid release notes and capability registry must update at that phase boundary.

## Decisions

1. **Default wake window: 120 seconds** (2026-09-02). Overridable via `--wake-timeout` and `HEALTHMD_WAKE_TIMEOUT`; `0` disables the wait.
2. **Wake exposure: readiness only, single implementation** (2026-09-02). The wake window and its state live once in the CLI crates; the MCP server calls that same function and surfaces an additive `wake` object in `healthmd.direct_readiness` plus wait progress notifications. No dedicated `healthmd_wake` tool, no parallel MCP implementation.
3. **Worker home: extend the existing consumer worker** (2026-09-02; superseded 2026-09-03 by decision 5). Wake endpoints live on `healthmd-receipt-verifier`, reusing its APNs credentials and device-token store; abuse is isolated by per-`wake_id` rate limits rather than a separate deployment.
4. **Notification names the requesting computer** (2026-09-02). Include the paired computer's device name when the transport can carry it; otherwise fall back to generic copy and record the reason.
5. **Wake ships as the dedicated `healthmd-wake` worker; HMAC keyed by the verification hash** (2026-09-03). The `healthmd-receipt-verifier` source was lost with an old machine and cannot be recovered; rather than reconstruct a production paywall/scheduling worker blind, the wake endpoints ship as a self-contained script with their own D1 database and APNs secret bindings, leaving the receipt-verifier frozen. Simultaneously, the wake HMAC's key was corrected to `SHA-256(wakeKey)` (the registered verification hash): the original "raw key" construction is unverifiable from a hash-only store, and the corrected key keeps the RFC invariant that the raw key never crosses the wire to the worker. The construction is pinned cross-language in the Rust client tests and the worker's test suite.
6. **Canonical source and default client activation** (2026-09-04). Preserve the Worker's four source commits through an unsquashed import under `apps/wake` so production source cannot be lost with a workstation. Compile the bounded worker client into every desktop `healthmd` build, use the production Worker URL by default, retain environment override and explicit opt-out, and keep every failure a silent degradation to P1. P2 remained source-feature-gated in alpha.6 and its official archives are wait-only; the next CLI release is the first to carry all-build activation.

## Open questions

1. Android 14 `dataSync` FGS restrictions: confirm at implementation time whether any tap-to-start path needs a user-initiated session type instead.
