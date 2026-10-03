# Mobile-initiated encrypted desktop context refresh

## Status and neutral outcome

Source implementation in the #173 draft; **unreleased and not device-qualified**.
A mobile personal automation requests a saved profile and exact frozen owner-date,
metric, source and detail scope on its authenticated paired desktop, without export
files or file quota. It receives a durable request identity and can recover a
request-bound receipt after an acknowledgement is lost or either app restarts.
This is not ordinary file export or computer-initiated MCP acquisition.

The existing seven export/summary/schedule actions are unchanged. The iOS provider
additionally registers `RefreshMacHealthContextIntent` and
`GetMacContextRefreshStatusIntent`, returning `MacContextRefreshEntity` with a
persisted request ID and a Status property. The selected hosted SDK is the Apple
CI `macos-26` / `latest-stable` Xcode image; only established public AppIntents
APIs already used by the existing entity-returning intents are used. No OS 27
all-history API, private API, flag enablement or deployment is involved.

## Initial adapter and availability

- Both updated Health.md apps must be open and connected through **authenticated
  Manual IP v2** pairing/reconnect. Nearby encryption and `hello.installationID`
  alone do not prove an installation identity, so Nearby is unavailable for this
  new family. Pairing proofs and their cryptographic transcripts are unchanged.
- Choose an existing Connected Mac profile in Export Profiles and explicitly use
  **Bind context automation to this authenticated Mac**. This is a separate local
  binding, not a change to the frozen export profile or Shared Setup grammar.
- Refresh accepts an optional saved profile name (empty selects the active saved
  profile) and required ordered inclusive start/end dates. Unknown, ineligible,
  rebind-required or unbound profiles fail without fallback. No profiles means
  unavailable, not live settings. Summary and Lossless profiles are supported;
  other detail policies are rejected, not approximated.
- Gregorian owner dates and the profile's explicit timezone, or the current
  timezone at admission, are frozen before any await. The initial source scope is
  explicitly `apple_health`, not all connected providers. Metrics and detail are
  canonical and immutable. Retry/status never resolves a changed profile.
- No host, destination, URL, shell, file mode, raw profile, object path or field
  pointer is accepted. Unknown request/selection fields fail decoding.
- No promise to wake a sleeping Mac, reconnect automatically, bypass protected
  health data, or obtain background execution. Physical after-wake automation,
  accessibility, old-peer and locked/session qualification remain release gates.

## Narrow contract/version decision

`SyncMessage.appleContext` contains an independently versioned Apple Sync
extension v1: refresh, status and receipt. Both peers must announce
`supportsPhoneContextAutomation`; absent/false legacy fields decode false.
Actual live transport authentication, opposite native roles, verified installation
matching, scoped acquisition and canonical-selection capabilities, and durable
corpus v2-or-newer negotiation must all pass **before dispatch and ingress**.
No new enum case is sent to an old or unnegotiated peer.

Affected producer/consumer: Apple iPhone and Mac SyncService, both app routers,
context coordinator and iOS App Intents. Android has comparable Health Connect
owner dates and explicit automation but no paired encrypted desktop-context
receiver; its concrete staged equivalent is recorded in the independently
versioned product-only `packages/contracts/product-automation-capabilities-v1.json`
ledger. This supplemental ledger is deliberately NOT an M3 metric authority or
input to the frozen native registry importer. Apple/Android governance tests read
it directly; aggregation into the existing product catalogue remains a separate
owner/design gate, not an excuse to repin the frozen registry. The original
`product-capabilities.json`, contract manifest, M3 registry, native pins and
semantic fixtures retain their admission bytes. Rust shared core, portable CLI/direct protocols, public Apple/Android
export schemas, external Obsidian files, canonical archives and frozen fixtures
are unchanged. No export-schema or direct-protocol bump is appropriate. The
existing `.contextStore` request, acquisition, partition bytes, strict checks and
encrypted commit path are reused without rewriting their deployed grammars.

## Durability and truthful receipts

1. Phone persists request ID, verified Mac/phone installations, saved profile ID,
   exact dates/timezone and canonical scope before send. A failed write means no
   send. The identity contains no health payload or credentials.
2. Mac validates the authenticated peer and entire immutable scope, persists the
   mapping, and starts acquisition in a separate MainActor task. The receive
   router does not await its response; acceptance/chunks/finalization can run
   while acquisition is suspended. The native context job must also be persisted
   before its pending acknowledgement is sent.
3. Duplicate refresh/status references the same job. Changed profile/peer/date/
   source/detail is rejected. Crash between mapping and native admission resumes
   that identity. Once admitted, a missing/expired native job is unavailable, not
   silently recreated. Existing seven-day native job retention is unchanged.
4. Completion comes only from the durable native job after actual encrypted
   corpus commit, never from a peer's claimed completion or waiter expiry. The
   result has zero export files. Timeout/disconnect remains pending/unavailable;
   status does not mean cancellation. Locked Keychain admission reports locked
   without requesting acquisition. Partial capture is partial, not complete.
5. Phone durably stores only authenticated peer/local-installation/request/scope-
   bound receipts. Monotonic revisions reject obsolete updates; terminal receipts
   cannot regress. A failed persistence operation cannot publish an ephemeral
   completion. Protected journals are retried after unlock. Status can recover
   the original request even if the first acknowledgement was lost.

Native synthetic tests exercise the production service gates, journals, phone
adapter, Mac coordinator, real public intent/registration surfaces, real encrypted
context store/corpus application and existing ordinary-export positive controls.
DEBUG transport state injection is **not** cryptographic hardware proof. Existing
pairing verifier tests remain part of the full native suites. Synthetic capture
and injected encryption keys are not real HealthKit permission, Keychain lock,
personal automation or device background proof. Exact-head hosted test receipts
and any failures belong in the additive implementation report, not a claim of
released availability or #173 completion.
