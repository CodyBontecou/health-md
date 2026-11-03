# Clinic-sponsored export authorization v1

Status: unpublished manually activated implementation with production deployment package and recoverable enrollment v2; disabled without reviewed native trust configuration. The isolated service is deployed; native store-policy/release qualification remains pending.

## Outcome and authority

An independently entitled patient retains normal Health.md export destinations. A patient
with only clinic sponsorship may release data only through phone-to-clinic delivery to
the destination named by an authenticated licensing grant. Clinic membership does not
authorize health reads or sharing. Flat clinic billing does not depend on patient counts.

The deterministic policy consumes verified licensing evidence, not an invitation string,
editable profile, unsigned server JSON, or persisted purchase flag. The licensing adapter
must verify signature, issuer/audience, installation binding, policy version, and grant
lifetime before constructing evidence. Unknown or malformed evidence fails closed.

Independent access includes existing purchased, grandfathered, and included-channel rights.
Sponsorship never populates lifetime flags. Expiry or revocation cannot remove independently
acquired rights. Personal licensing admission does not bypass health consent or permit
clinic-scoped credentials to be used at a personal destination.

## Export admission

`allowed_personal` permits existing personal export paths, subject to their existing consent
and destination checks. Otherwise a grant must be unrevoked, already issued, not expired,
and valid for at most seven days. Request clinic ID, destination ID, policy version, and
canonical endpoint must match, and sharing must be separately authorized. Only direct
phone delivery is admitted. Raw/file downloads, CLI/MCP results, Mac transfer, share
sheets, report exports and arbitrary local destinations do not qualify as clinic delivery.

Result identities and cross-platform examples live in `authorization-fixtures.json`.
The fixture uses fictional identities and endpoints only. No public health schema or
direct-protocol wire format is changed by this policy.

## Endpoint and job binding

Clinic endpoints use HTTPS and an ASCII DNS hostname with at least two labels. URL userinfo,
query strings, fragments, percent escapes, dot segments, repeated path slashes, backslashes,
numeric IP literals and control/whitespace characters are rejected. Hostname and scheme are
case insensitive; port 443 is canonicalized away. Missing path becomes `/`. Other ports and
path case/trailing slashes remain significant. Credentials belong in protected request
headers, never URLs. The shared restricted grammar deliberately avoids parser-dependent
normalization. Configuration requiring another grammar needs a reviewed contract revision.

Uploads must reject redirects and bind patient-specific credentials to the approved endpoint.
Existing job/profile snapshots freeze the destination URL and export selection. Execution,
retry, resume and each network transmission reauthorize against the current verified grant
and current sharing choice. A historical job never restores an earlier consent or grant. A malformed managed profile must never fall
back to legacy settings. Destination changes require patient reconfirmation. Policy denial
pauses work without silently rerouting data, deleting patient files, or granting personal access.

## Pilot flow and lifecycle

The operator manually creates a clinic with its endpoint and paid-through date. A clinic
administrator creates single-use invitations valid for at most one day. Patients type a
code in Clinic access on either phone platform. The native client verifies an installation-bound
P-256 grant using a reviewed build-pinned SPKI key, then stores one secure session record.
Invitations cannot override service URLs or trust roots. Manual activation has no billing
provider, per-doctor fee or billable seat counter. Installation memberships exist for authority
and revocation, independently of clinic pricing.

Before first redemption, the native client securely persists the invitation and a random
32-byte base64url enrollment secret. `/v2/invitations/redeem` requires invitation,
installation ID and that secret. Its hash becomes the membership refresh credential;
no replacement credential is returned. Transactional retries recover the same membership
only for the identical proof within 24 hours of first redemption. Recovery never extends
the window or bypasses membership revocation or clinic suspension/expiry. Secure acceptance
atomically replaces pending enrollment with the verified grant; failed responses or writes
retain pending proof for restart/retry. Definitive denial clears pending proof. Disconnect
clears pending and active state and best-effort revokes both. Secure-store loss or recovery
expiry requires a fresh invitation. The unpublished v1 redemption route is retired; existing
v1 refresh and signed grant formats remain compatible. This HTTP enrollment revision does
not change export policy v1 or any health-data wire format.

Enrollment admits app navigation. Sharing starts off and requires an explicit patient choice.
“Use clinic destination” creates or selects an API export profile; it does not schedule uploads
or request new health permissions. Patient-specific upload tokens are optional, kept in secure
storage and applied only to that approved endpoint while sharing is authorized. They are never
copied into portable profiles. Other destinations require independent access. Disconnect clears
local sponsorship and consent immediately when secure persistence succeeds; network notification
is best effort. A storage failure is reported and blocks sponsorship in that running process.

Each upload rechecks access and consent. Sponsored and managed clinic uploads reject redirects
and suppress response-body previews. Refresh denial removes sponsorship; a network outage retains
only the unexpired signed grant. The service backdates issuance by up to 60 seconds for ordinary phone clock lag.
Expiry remains capped by seven days measured from that signed issuance time and clinic
paid-through; verifiers retain their strict future-issuance and expiry checks.
Offline revocation is bounded by this signed expiry, rather than instantaneous. A persisted clock
high-water mark prevents an observed expiry from being reversed by setting the device clock back.
Foreground refresh, periodic status evaluation and secure-store recovery update native access.
Clinics cannot silently change an endpoint through the pilot API; a changed clinic/destination/policy
binding requires fresh sharing consent and clears the prior upload credential.

## Clinic sync requests (delegated doorbell)

A patient may separately allow the clinic to request a sync. The toggle starts off, requires
active sponsorship and authorized sharing, and asks for notification permission. Enabling it
creates a random 32-byte doorbell key on the phone and registers only its SHA-256 with the
RFC-0005 wake service as a `delegated-sync` doorbell (APNs on iPhone, FCM on Android). The wake
service receives an opaque install identifier, the push token and the key hash; it never
receives clinic, sponsorship, destination, endpoint or patient metadata. Only then does the phone
deliver the doorbell to the approved clinic endpoint, with the same endpoint binding, upload
credential and redirect rejection as clinic uploads:

```http
POST <approved clinic endpoint>
Content-Type: application/json
X-HealthMd-Message: clinic-sync-doorbell.v1

{"type":"healthmd.clinic_sync_doorbell","version":1,"action":"enroll",
 "wakeService":"https://healthmd-wake.costream.workers.dev",
 "wakeId":"<opaque>","wakeKey":"<base64url 32 bytes, no padding>"}
```

Clinics distinguish this message by the header or `type`; it carries no health data. A clinic
rings the doorbell with `POST <wakeService>/wake/request` and the RFC-0005 HMAC (key
`SHA-256(wakeKey)`, message `"healthmd.wake.v1" ‖ nonce ‖ timestamp`); see
`sync-doorbell-fixtures.json`. `peerLabel` is ignored: notification copy is fixed and localized
on the phone, so a clinic cannot put text in front of the patient. Dedupe (30 s) and the hourly
budget (6) apply per doorbell. `404 wake_unknown` means the patient revoked it; discard it.

Turning the toggle off, revoking sharing, disconnecting, or any change of clinic, destination,
policy or endpoint binding unregisters the doorbell at the wake service before local state is
cleared, and best-effort sends `{"type":"healthmd.clinic_sync_doorbell","version":1,"action":"revoke","wakeId":"<opaque>"}`.
A new binding requires the patient to enable it again.

Tapping the notification foregrounds Health.md. The phone accepts only a doorbell it currently
holds, then exports yesterday and today through the clinic profile, re-authorizing the grant and
sharing choice exactly like any other clinic upload. A ring never grants access, changes
settings, or uploads without that tap. Silent background execution is not part of v1.

## Qualification and service boundary

Clinic membership metadata requires an independently reviewed service boundary. It must not
enter analytics, the notification-only wake service, or the synthetic-only Practice runtime;
delegated doorbells give the wake service no clinic metadata.
The service receives no health exports. The production package separates patient HTTPS ingress
from host-loopback operator/admin control, with bounded requests/rates, file-mounted secrets,
aggregate-only logs, SQLite integrity checks and encrypted hourly backups. A disaster restore
invalidates all refresh/recovery credentials, outstanding invitations and clinic-admin tokens
to prevent stale backups resurrecting revocations. Original offline signed grants still expire
normally. The [service runbook](../../../../apps/licensing/README.md) owns deployment, retention,
key rotation and restore operations. Host/DNS/secret custody, off-host backup/alert setup,
restore drills and store-policy confirmation remain rollout prerequisites. Device enrollment checks use fictional clinic metadata. Native store
purchases, real endpoint delivery and background OS scheduling require release qualification.

No health export schema, shared Rust representation, Direct protocol, CLI/MCP wire format or
external Obsidian parser changes in this contract. Those consumers retain personal-access gates.
Invitation links/deep links and a clinic administration UI are outside this typed-code pilot.
