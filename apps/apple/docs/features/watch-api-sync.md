# Manual Apple Watch API Sync (draft)

This source feature is **not yet qualified on physical hardware or released**. It addresses part of https://github.com/CodyBontecou/health-md/issues/171; the issue remains open.

## Setup and manual delivery

1. Install the Watch app through the current companion-app route; independent installation is not introduced.
2. On Watch, open Health.md and use **Connect Health**. HealthKit authorization-request completion does not prove read access.
3. Open **API Sync / Sync Now**. Enter a trusted HTTPS endpoint and a backend-issued, least-privilege bearer token using Watch input. Save stores both locally in a protected, non-synchronizing Keychain item and does not send a test request. Do not put credentials in URL query parameters. You can forget the destination after resolving any pending upload.
4. The receiver must explicitly support **healthmd.watch_snapshot v1**, with a matching **healthmd.watch_ack v1** response and account-bound idempotency. This is not the iPhone's daily API envelope; an existing generic API Endpoint destination is not automatically compatible. The normative contract is `packages/contracts/watch-snapshot/v1/contract.md` at repository root.
5. **Sync Now** queries today-to-now locally available steps, active energy (kcal), and Apple Exercise Time (minutes). Keep the app open. It does not send dashboard placeholders, sleep, workouts, stand, HRV, archives, or complete history. Locally stored samples can include HealthKit-synchronized sources, not just Watch sensors.
6. Progress changes from capture to upload. Only a matching committed backend acknowledgement yields the success message. Missing/denied values remain unknown, not zero. A successful transfer is not proof of complete data or authorization.
7. Offline, rejected, cancelled, interrupted, or unacknowledged uploads remain pending. **Retry Pending Upload** sends the same bytes/UUID to the same endpoint using the same token without recapture. No automatic background retry, redirect, phone-app fallback, or destination substitution occurs.
8. While pending, destination/credential changes are blocked. **Discard Pending** requires confirmation and deletes only the Watch's pending copy; an uncertain delivery may already exist at the backend. After discard, replace/revoke a token or choose a different endpoint deliberately.

Snapshot/keychain data does not migrate to a different device. Existing phone exports, HealthKit records, and widget caches are not changed. The current Watch distribution flags remain companion-dependent; runtime direct networking is a separate claim from independent install/setup. The OS may proxy networking through a reachable phone; the feature does not invoke the phone Health.md app. With the phone unreachable it relies on the Watch's available Wi-Fi or cellular route, pending physical verification below.

## Physical verification matrix — all pending

No simulator or hosted build is evidence for the following. Run with synthetic/minimized data and a controlled, compatible backend; receipts must not contain tokens, health values, account identity, or credential-bearing URLs.

| Scenario | Required observation / safe receipt |
|---|---|
| Setup on installed Watch, no phone Health.md app reachable | Health authorization UI, endpoint/token input/save, locked-Keychain failure feedback; record install origin separately |
| iPhone powered off/out of range; known Wi-Fi | Sync Now → matching ACK, one backend commit; record route evidence from Watch control center, OS/model, UTC time, build SHA and sanitized UUID/hash/count receipt |
| Cellular model + plan; phone unavailable and Wi-Fi disabled | Same receipt; record cellular route evidence; GPS-only/no-plan devices must report not applicable, not a pass |
| Denied/revoked/limited/no-data Health access | No invented values; nil is `no_data_or_not_authorized`; request completion isn't read grant; compare only permitted local data |
| Local history purged / old data absent | No full-history claim; `earliest_permitted_sample_date` is not represented as earliest available record |
| Offline / network loss / timeout | No success; at most one pending snapshot survives relaunch; explicit retry uses exact UUID/hash |
| 401/403, 429, 5xx, 202/204, malformed/wrong-ID ACK | Rejected/uncertain feedback and retained pending snapshot |
| Same-origin and cross-origin redirect | Neither redirected receiver receives health data or authorization header; no success |
| App inactive, wrist down, navigation away, cancel, kill during upload | No false success; queued bytes survive; exact retry after unlock/reopen; receiver deduplicates possible prior commit |
| Backend committed but ACK lost or local ACK commit failed | Retry has same UUID/hash and exactly one purpose/account-bound backend commit |
| Change endpoint/token while pending | Blocked; explicit discard allows intentional replacement; no automatic reroute |
| VoiceOver, input on small Watch, progress/results, confirmation dialogs | Action/result accessible; secure token not redisplayed; no sensitive logs |
| Companion uninstall / independent Watch install | Record current dependent distribution behavior only; do not treat successful direct upload as independent-install proof |

Each receipt: PR head/build SHA, OS/model/network applicability, test timestamp, sanitized upload UUID/byte hash, request/ACK status and duplicate count, observed UI state, pass/fail/not applicable, and operator. Real account/token management and backend deployment are outside this source issue lane.

## Automated evidence

`Apple Watch CI` runs `swift test --package-path apps/apple/Packages/HealthMdWatchExport` (capture/payload/fixture, secure state, URLSession/ACK, redirect, retry/cancellation tests), contract inventory validation, and a code-signing-disabled build of the actual `HealthMdWatch` scheme. It does not execute the empty Watch scheme TestAction or claim HealthKit/device QA. Existing Apple CI remains separate for affected app/consumer inventory checks. Tests and builds run on GitHub-hosted runners only for this lane.
