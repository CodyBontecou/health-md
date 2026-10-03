# Manual watch-origin snapshot and acknowledgement v1

**Draft, source implementation; not device-qualified or released.** Refs https://github.com/CodyBontecou/health-md/issues/171.

## Outcome and compatibility

A user explicitly uploads a bounded snapshot of locally readable wearable data to a trusted HTTPS backend without a phone app capture/relay at upload time. This is **not** a daily export, source archive, backup, or full public authorized corpus. The Watch producer uses `healthmd.watch_snapshot` v1. It must never use `healthmd.health_data` v8 or `healthmd.api_export` for this limited payload.

Apple daily v8, Android frozen v4/analytical v5, direct protocol v3, shared Rust, CLI, website readers, and the external Obsidian plugin remain unchanged. Those consumers must not be fed this new profile disguised as a supported daily record. Only an explicitly compatible user-configured backend consumes it. No daily schema bump/signature rewrite is appropriate. A future neutral wearable contract may add a reviewed Android producer; Apple Exercise Time is not an alias for Android exercise duration. Android's current Wear OS product renders phone-supplied aggregates only, with no local capture; see `apps/android/docs/features/wear-os.md`. Parity is staged as `planned`, not asserted.

## Capture

The v1 Apple scope deliberately includes **three cumulative quantity statistics only**:

| Metric ID | HealthKit selector | Unit | Reducer |
|---|---|---|---|
| `steps` | `HKQuantityTypeIdentifierStepCount` | `count` | `healthkit_cumulative_sum` |
| `active_energy_kcal` | `HKQuantityTypeIdentifierActiveEnergyBurned` | `kcal` | `healthkit_cumulative_sum` |
| `apple_exercise_minutes` | `HKQuantityTypeIdentifierAppleExerciseTime` | `min` | `healthkit_cumulative_sum` |

Capture queries run against the Watch's HealthKit store, **not just Watch-origin sensor samples**: HealthKit may have synchronized other-device samples into that store. `source: watch_local_healthkit` identifies the query authority, not each sample's sensor provenance. These are HealthKit statistics, not a raw-sample sum performed by Health.md.

The interval is frozen before capture: local calendar midnight (`interval_start`) through the instant Sync Now starts (`interval_end`, also `captured_at`). Each query selects samples starting in this half-open interval using strict start bounds and an explicit `startDate < interval_end` predicate. Statistics are not prorated or clipped for samples extending beyond the interval. This rule is independent of daily-v8 reducers. Timestamps use UTC RFC 3339 seconds; `calendar_timezone` records the captured IANA timezone. Three observations appear in the table's order.

Observation status:

- `value`: finite nonnegative numeric `value` is present, including an actual API-returned zero.
- `no_data_or_not_authorized`: `value` is omitted. Empty/denied reads cannot be distinguished reliably by HealthKit. Never infer authorization granted from request completion or infer a zero from nil.
- `query_failed`: `value` is omitted; sibling queries remain valid. No raw HealthKit error is serialized.
- `unsupported`: `value` is omitted; reserved for a producer with positive API-unavailability evidence.

`capture_status` is `partial` if any observation is `query_failed`/`unsupported`, otherwise `observed`. **Neither means complete history or permission.** `history_availability` is always `unknown_local_store_may_be_purged`. `earliest_permitted_sample_date` is Apple's system-wide permitted query boundary, **not** the date of the earliest stored/authorized record and not proof all later data exists. `workouts_status: not_requested` states that no workouts were queried. Sleep, stand, resting HR, HRV, oxygen, routes, source archives, and older dates are outside v1, despite being displayed elsewhere in the app.

The synthetic fixture `fixtures/watch-snapshot-v1.json` shows zero, missing, and failed observations. Maximum encoded snapshot size is 64 KiB. No backend identity, endpoint, credential, or raw SDK error belongs in the payload.

## Setup, transport, and acknowledgement

Setup happens on the Watch. The endpoint must be HTTPS with no userinfo, query, or fragment. The credential is a user-provisioned backend bearer token; this feature does not create accounts or implement an authentication challenge protocol. Use a least-privilege, revocable token scoped by the backend to this upload purpose/account; the Watch never logs credentials or response bodies. The endpoint, token, and at most one queued snapshot are stored together in a non-synchronizing `WhenUnlockedThisDeviceOnly` Keychain item, not app-group UserDefaults or a phone relay. No migration changes existing exports, widget caches, profiles, or HealthKit data.

A manual foreground ephemeral URLSession sends:

```http
POST <exact configured HTTPS URL>
Content-Type: application/json
Accept: application/json
Authorization: Bearer <backend token>
Idempotency-Key: <upload_id UUID>
```

No cookies, stored URL credentials, disk response cache, fallback endpoint, redirects (including same-origin), or background/autonomous retry. OS network routing may proxy through a reachable phone, use Wi-Fi, or use cellular; this does not introduce an iPhone Health.md capture dependency. Standard OS TLS validation is retained; non-TLS HTTP auth challenges are refused. Request/resource timeouts are 30/45 seconds; acknowledgement data is limited to 8192 bytes.

The backend must atomically persist or durably commit the snapshot before responding **200 or 201**, `Content-Type: application/json`, with:

```json
{"schema":"healthmd.watch_ack","schema_version":1,"upload_id":"00000000-0000-0000-0000-000000000171","accepted":true}
```

The UUID must match both the request header and body. Backend deduplication must be purpose/account-bound: repeated authenticated requests with the same UUID and bytes return the same acknowledgement without inserting duplicates; conflicting bytes/identity must be rejected. This source PR does not deploy a receiver. A generic backend accepting the phone's API envelope is not automatically compatible.

202/204, redirects, 4xx/5xx, oversized/invalid JSON, wrong schema/version/UUID, `accepted: false`, offline/timeout/TLS failures, and interruption are **not success**. Exact queued bytes and destination/token remain for an explicit Retry Pending Upload after relaunch. No recapture or rerouting on retry. Save/change/forget destination is blocked while an upload is queued/running. Explicit, confirmed Discard Pending removes only the Watch's queue, not any possibly accepted backend copy; after discard the user may change/revoke credentials. A matching ACK followed by failure to commit local queue removal is still uncertain locally; retry relies on backend idempotency.

## Independent setup/install is a separate decision

The current bundle remains companion-dependent (`WKRunsIndependentlyOfCompanionApp = false`, `WKWatchOnly = false` and companion bundle ID retained). This PR does **not** claim independent App Store installation. Once installed, authorization, endpoint entry, Keychain storage, capture, and HTTP upload are Watch-side; the iPhone Health.md app need not be open/reachable at runtime. Changing distribution independence requires its own product/entitlement/installation review and hardware tests; direct networking alone is not evidence for changing those flags.

## Evidence and open gates

The dependency-free `apps/apple/Packages/HealthMdWatchExport` suite behavior-tests capture, payload fixtures, validation, durable state transitions, offline/rejection/cancellation/retry, Keychain storage, request construction, URLSession responses, and redirect refusal. `.github/workflows/apple-watch-ci.yml` runs it and compiles the actual Watch scheme with its source registrations on a free hosted macOS runner. HealthKit queries/UI are compiled for Watch, not simulated as proof of permissions or on-device runtime behavior. Existing Apple/Android/contract consumer checks remain required for their inventory surface.

Required hardware matrix and receipt fields: `apps/apple/docs/features/watch-api-sync.md`. Until physical Wi-Fi/cellular evidence and a compatible backend idempotency receipt exist, keep the PR draft and #171 open.

## Public API references reviewed

- https://developer.apple.com/documentation/watchos-apps/keeping-your-watchos-app-s-content-up-to-date — foreground default/ephemeral URLSession, phone proxy vs Wi-Fi/cellular routes and testing all routes.
- https://developer.apple.com/documentation/healthkit/about-the-healthkit-framework — separate Watch store and periodic history purging.
- https://developer.apple.com/documentation/healthkit/hkhealthstore/requestauthorization(toshare:read:completion:) — Watch-side authorization since watchOS 6; completion success is not read permission.
- https://developer.apple.com/documentation/healthkit/hkhealthstore/earliestpermittedsampledate() — system-wide constraint, not earliest available record.
- https://developer.apple.com/documentation/healthkit/hkstatisticsquery — quantity statistics and cumulative sum.
- https://developer.apple.com/documentation/healthkit/hkquery/predicateforsamples(withstart:end:options:) — interval options.
- https://developer.apple.com/documentation/foundation/urlsession/bytes(for:delegate:) — available watchOS 8+, bounded streamed ACK.
- https://developer.apple.com/documentation/foundation/urlsessiontaskdelegate/urlsession(_:task:willperformhttpredirection:newrequest:completionhandler:) — returning nil refuses a redirect for ephemeral/default sessions.
- https://developer.apple.com/documentation/security/ksecattraccessiblewhenunlockedthisdeviceonly — foreground access, does not migrate to a new device.
