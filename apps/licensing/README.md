# Clinic licensing

Independent Node 24+ service for manually sponsored clinic access. Licensing stores
clinic and installation membership metadata, token hashes and short-lived audit
metadata. It never receives health exports, patient names, email addresses, upload
credentials or health permissions. Keep it separate from Practice, Wake, analytics
and the static website. Billing stays manual, with no seats or billing provider.

The deployment package runs one writable SQLite instance behind Caddy HTTPS, with
private administration, rate limits, encrypted hourly backups and recovery tooling.
The Fly + Cloudflare service is deployed; native trust settings, recovery-key custody
and store-policy approval remain rollout work. Do not use real patients in local QA.

## Protocol and enrollment recovery

The phone generates a cryptographically random 32-byte enrollment secret and commits
it together with the invitation to secure storage **before** sending any request.
`POST /v2/invitations/redeem` accepts exactly `invitationCode`, `installationID` and
`enrollmentSecret` (43-character base64url, no padding). The secret becomes the refresh
credential; the reply contains the signed grant and sponsorship ID, never a new secret.
The server stores hashes, not plaintext invitations or credentials.

Redemption is transactional. Repeating the same invitation, installation and secret
returns the same membership for 24 hours after first redemption. A different proof,
revoked membership, suspended/expired clinic or elapsed recovery window is denied.
The deadline never extends on retry. Recovery can finish after the invitation's
original expiry if the first redemption succeeded within that expiry.

Both apps retain pending enrollment through a network failure, invalid response or
failed final secure write. Startup/foreground refresh and **Retry enrollment** resume
that same proof. Acceptance atomically replaces the pending record with the verified
grant and refresh credential. Recovery does not enable sharing or grant personal
access. A definitive denial clears pending enrollment; the patient can request a new
invitation. Losing secure storage or changing phones requires a new invitation.
Disconnect clears active and pending state and best-effort revokes both credentials.

The unpublished v1 redemption route is removed: upgrade both native clients with
this service. Existing v1 refresh credentials and signed grant format remain valid.
`/v1/sponsorship/refresh` and `/v1/sponsorship/disconnect` still accept `refreshToken`
and `installationID`. Issuance is backdated by up to 60 seconds for ordinary phone clock lag. Grants
expire at the earlier of seven days from that signed issuance or paid-through; the
backdate never extends access. Native future-issuance/expiry checks remain strict.
Revocation stops refresh immediately; already signed offline grants last until expiry.
See the [authorization contract](../../packages/contracts/clinic-sponsorship/v1/contract.md).

## Fly + Cloudflare production deployment

The production service is `https://licensing.healthmd.app/`, on the dedicated Fly
app `healthmd-licensing` in `iad`. Cloudflare DNS has a DNS-only CNAME to
`5yzx85w.healthmd-licensing.fly.dev`; Fly terminates HTTPS with managed certificates.
Keep this record DNS-only: the ingress uses Fly Proxy's `Fly-Client-IP` for abuse
limits. The existing website, Wake and analytics deployments are separate.

`deploy/fly.toml` selects one always-on 1 GiB Machine and the encrypted 1 GiB
`licensing_data` volume. Do not deploy a second writer or enable automatic HA.
The Fly image bootstrap initializes volume ownership, mounts a bounded 192 MiB
memory filesystem for temporary plaintext backup snapshots, and drops to UID/GID
1000 before loading secrets or opening network listeners. Only port 8080 is exposed.
The Fly adapter exposes the patient route allowlist and health checks; backend and
operator/admin listeners stay on loopback. A generic public `/ops/health` returns
only success/failure for maintenance, disk headroom and off-host backup freshness.

Fly stores separate base64 secret values named `LICENSING_SIGNING_KEY_B64`,
`LICENSING_OPERATOR_TOKENS_B64`, `LICENSING_INGRESS_KEY_B64`,
`LICENSING_BACKUP_KEY_B64` and `LICENSING_UPLOAD_TOKEN_B64`, plus the non-secret
`LICENSING_KEY_ID`. At boot they become mode-0600 files in private memory scratch;
the Node process removes the encoded secret variables from its own environment.
Fly administrators with SSH/deploy access remain privileged. The operator CLI can
run through `fly ssh console` on loopback; do not expose a public operator tunnel.

The isolated `ops-worker/wrangler.jsonc` deployment is `healthmd-licensing-ops`.
It receives only authenticated, pre-encrypted HMLB1 archives at `PUT /v1/backup`,
with a 64 MiB limit. Upload and operator credentials are separate. The application
has only the upload credential; the Worker does not receive the signing, database
backup or clinic-admin keys. No patient exports or plaintext database uploads enter
this Worker. R2 bucket `healthmd-licensing-backups` is private, with r2.dev disabled.
Its `archives/` lifecycle expires objects after seven days; `status/latest.json`
records only the latest object key and upload time. Backups run on startup and
hourly, with a two-hour freshness alarm. Fly snapshots are supplementary recovery
material and do not replace the off-host encrypted archive.

A five-minute Cron checks `https://licensing.healthmd.app/ops/health` and the latest
R2 object's presence/freshness. Two consecutive failed checks send an alert, repeated
after six hours while unresolved; recovery sends an email. Deduplication state is
isolated KV metadata. Mail goes to `bontecouc@gmail.com` from the already onboarded
`healthmd-alerts@isolated.tech`. No clinic identifiers, credentials or request contents
appear in alerts. Worker request observability is disabled; unexpected scheduled
failures emit only a fixed event name. This monitor does not independently detect
failure of its own Cloudflare cron/email platform.

The operations token authorizes `POST /v1/check`, `POST /v1/test-alert` and
`GET /v1/backup/latest` at the Worker URL. Supply it only as a bearer header from a
protected file. The last route downloads an encrypted archive for the existing
restore CLI. Never restore over the live Fly volume: perform a local isolated drill,
then follow the credential-invalidating disaster restore procedure below.

Rebuild/redeploy from the repository root:

```sh
node --test apps/licensing/test/*.test.mjs
fly config validate --config apps/licensing/deploy/fly.toml
fly deploy apps/licensing --config deploy/fly.toml --remote-only --ha=false --strategy immediate
wrangler deploy --config apps/licensing/ops-worker/wrangler.jsonc
wrangler types --config apps/licensing/ops-worker/wrangler.jsonc apps/licensing/ops-worker/worker-configuration.d.ts
fly checks list --app healthmd-licensing
fly certs check licensing.healthmd.app --app healthmd-licensing
```

Immediate single-writer deployment briefly interrupts service. The phone's saved
recovery proof permits enrollment retries; active offline grants retain their signed
expiry. Monitor health after every restart and restore-test a fresh R2 archive.
Keep a protected recovery copy of all generated keys outside Fly and R2, such as a
private Apple Passwords entry's Notes field. Preserve PEM newlines exactly, or use
base64 for transport. The local staging copy must remain until vault persistence and
retrieval have been verified. Never place the bundle in Git, screenshots or tickets.
Native builds use the reviewed production issuer and public signing key from
`deploy/NativeLicensing.xcconfig`. Store release qualification remains required before
patient rollout. SetClinic activation and receiver work
remain manual/deferred respectively.

## Deployment

Use a dedicated Linux host with Docker Engine and Compose v2, persistent encrypted
storage and restricted SSH access. Do not use shared ephemeral SQLite storage, NFS,
multiple writers, multiple replicas or an internet-accessible Docker daemon. Publish
only ports 80/443; port 8793 is loopback-only administration. The application public
port 8792 is not host-published. Caddy overwrites trusted ingress headers and only
proxies patient routes; operator and clinic-admin routes are absent publicly.
Do not place a CDN/proxy in front without reviewing client-IP attribution and limits.

From the repository root, prepare private directories on the host:

```sh
umask 077
node apps/licensing/src/init-secrets.mjs /srv/healthmd-licensing/secrets
sudo install -d -m 0700 -o 1000 -g 1000 /srv/healthmd-licensing/data /srv/healthmd-licensing/backups
sudo chown -R 1000:1000 /srv/healthmd-licensing/secrets
```

Create the parent directory first. Keep signing.pem, ingress-key, backup-key and
operator-tokens.json mode 0600 and the secret directory 0700. Compose file secrets
are host-mounted files, not an encrypted vault; secure the host and its backups.
Generated ingress-key has no trailing newline; preserve those exact bytes for Caddy.
Store the backup key and signing key in a separate, access-controlled recovery vault.
Copy only public-key.json/trusted-keys.json to the native build configuration.

Copy `deploy/production.env.example` to an untracked protected env file. Set the DNS
hostname, absolute directories, key ID from public-key.json, source revision, and
reviewed immutable Node/Caddy image digests. The example digests are the versions
used for this qualification; review security updates and requalify before rollout.
Point DNS at the host and allow Caddy's ACME HTTPS certificate issuance.

```sh
docker compose --env-file /srv/healthmd-licensing/production.env -f apps/licensing/deploy/compose.yaml config --quiet
docker compose --env-file /srv/healthmd-licensing/production.env -f apps/licensing/deploy/compose.yaml up -d --build --wait
```

Do not scale the licensing service. Pin releases to retained source revisions. Before
an upgrade, take and restore-test an encrypted backup, retain the prior image, stop
writes and inspect migrations. Schema v0 migrates transactionally to v1; future
versions fail closed. An old binary must not write a newer schema. Roll back only
with a compatible database; disaster restore deliberately invalidates credentials.

## Manual clinic operations

Run the operator CLI on the host with Node 24+, or inside the licensing container.
It reads request JSON from stdin and credentials from a protected file, keeping
secrets out of arguments and URLs. Control defaults to `http://127.0.0.1:8793/` and
rejects non-loopback addresses and redirects. For remote operators, use SSH to the
host or a loopback SSH tunnel. Do not expose administration through Caddy.

```sh
export LICENSING_CONTROL_TOKEN_FILE=/srv/healthmd-licensing/secrets/operator-tokens.json
node apps/licensing/src/operator.mjs provision < /secure/clinic-request.json > /secure/clinic-admin.json
```

Provision input: `{"name":"Example clinic","endpoint":"https://intake.clinic.example/upload","paidThroughMilliseconds":1893456000000}`.
The response contains clinic/destination IDs and a one-time admin token. Files
containing responses must be mode 0600 (`umask 077`); do not paste them into tickets,
logs or shell history. The saved admin response is accepted as a credential file.

- `activate`: operator input `clinicID`, `paidThroughMilliseconds`; manually extend
  after payment. This also lifts clinic suspension; it never unrevokes memberships.
- `suspend`: operator input `clinicID`; prevents enrollment/refresh immediately.
- `rotate-admin`: operator input `clinicID`; returns a new admin token and invalidates
  the previous token. Does not invalidate already issued invitations.
- `erase`: operator input `clinicID`; permanently deletes current clinic, invitation,
  membership and audit rows. Confirm identity independently before invoking it.
- `invite`: clinic admin credential, input `{}`; returns a single-use invitation
  expiring within one day. Issue additional invitations without seat accounting.
- `memberships`: clinic admin credential, input `{"after":""}`; returns up to 100
  opaque membership IDs with timestamps/status and a `nextCursor` cursor. Pass that cursor
  as `after` for the next page. No device identifier or patient identity is returned.
- `revoke`: clinic admin credential, input `sponsorshipID`; prevents refresh/recovery.

For example, switch `LICENSING_CONTROL_TOKEN_FILE` to the saved clinic-admin.json
before `invite`/`memberships`/`revoke`. Keep clinic tokens confined to their clinic.
Operator-token rotation supports a JSON array of one or two credentials: install
[new, old], recreate the service, migrate operators, remove old and recreate again.
File changes take effect only after recreation. Rotating the ingress secret requires
recreating Caddy and licensing together. Never log secret file contents.

## Backups, retention and disaster recovery

The network-isolated backup container makes a consistent SQLite online snapshot
hourly, AES-256-GCM encrypts it with a separate 32-byte key and keeps seven days.
Temporary plaintext snapshots live in a 128 MiB memory filesystem. Monitor database
size and increase this bounded allocation before approaching it. Archive filenames
and logs contain no clinic identities; backup contents still require strict custody.
Copy encrypted archives off-host to private storage with a defined retention policy
and alert on failure. On-host backups alone do not cover host loss. Back up signing
and operator credentials independently; they are not contained in database archives.

The backup healthcheck fails when no backup less than two hours old exists. Monitor
all container health externally and alert on this condition, failed hourly backups,
maintenanceFailed summaries, repeated 5xx, low disk space and certificate expiry.
One successful on-host backup gives an intended hourly recovery point; validate an
off-host restore and measure recovery time before onboarding real patients.

Manual commands (CLI runs with `LICENSING_BACKUP_KEY_FILE` pointing to the private key):

```sh
node apps/licensing/src/operator.mjs backup /data/licensing.sqlite /backups/manual.hmlb
node apps/licensing/src/operator.mjs restore /backups/manual.hmlb /data/recovered.sqlite
```

Stop licensing and backup containers before disaster restore. Restore requires a new
database path (including absent WAL/SHM files), authenticates the whole archive and
checks SQLite integrity/foreign keys/schema before publication. Never overlay a live
database. Retain the original separately; install the recovered database with owner
1000/mode 0600 and start exactly one instance. Verify readiness, clinic paid-through
and endpoint records against the operator's independent records before reactivation.

**Restore invalidates all membership refresh/recovery credentials, outstanding
invitations and clinic-admin tokens.** This prevents a stale backup resurrecting
previously revoked credentials. Rotate each clinic's admin token through the operator
CLI and issue fresh invitations. Existing offline signed grants retain their original
expiry; restore cannot instantly revoke those grants. Signing-key compromise requires
a native trust/configuration rollout, not just a database restore.

Hourly maintenance deletes expired invitations/recovery links, revoked memberships
after 30 days, memberships of clinics over 90 days past paid-through, and audit events
after 30 days. Clinic configuration persists until explicit erasure. Inactive
unrevoked memberships in a paid clinic remain available for administration. Erasure
cannot remove older encrypted archives immediately; expire them under the seven-day
and off-host retention policies. SQLite logical deletion is not forensic erasure;
use encrypted storage and retire its encryption keys when the storage is disposed.

## Operations and verification

Readiness checks SQLite connectivity; liveness/readiness return only `{ok:true}`.
Request bodies are limited to 16 KiB, headers 8 KiB and URLs 2 KiB. Requests have
bounded timeouts. Per process, patient and control planes each allow 600 requests
per minute globally and 60 per client address, with at most 4096 in-memory HMAC
address buckets. Limits reset each minute/restart and are not a distributed DDoS
service; shared NATs may reach per-address limits. Responses use no-store; no CORS
or browser-cookie authentication is enabled. Unknown fields, including health data,
are rejected. Do not enable request/access logging in a hosting dashboard or proxy.

The service emits minute aggregate status counts and a maintenance-failure flag;
backup logs contain completion/failure only. No request, credential, clinic, device,
IP address or exception text is logged. Review the protected SQLite audit table
locally for its limited lifecycle events; it is not an external audit export.

Run `npm test` in this directory, the root Swift host authorization test, Android
`Clinic*Test`/API upload boundary tests, contract checks and queued native builds.
Linux container qualification must also cover TLS ingress, private admin isolation,
restart/retry and encrypted restore. Use fictional clinics and reserved `.example`
receiver URLs only. Native UI/device and real receiver checks remain separate.

## Native pilot configuration

Production app builds consume the reviewed public defaults in
`deploy/NativeLicensing.xcconfig`: Xcode imports it in all project configurations,
and Gradle loads the same public fields. The production key is pinned; invitations
and network responses cannot replace it. Xcode command-line settings and Android
Gradle properties/environment can override defaults for isolated QA. No production
private keys are bundled. The Xcode `$()` URL separator is removed by Gradle.

Both platforms bake the same `CLINIC_LICENSING_URL` (canonical HTTPS root ending in `/`),
`CLINIC_LICENSING_ISSUER`, `CLINIC_LICENSING_KEY_ID` and
`CLINIC_LICENSING_PUBLIC_KEY_DER` (base64 SPKI P-256 public key) into both builds.
Android accepts Gradle properties or environment variables with these names.
Apple uses Xcode build settings expanded into `ClinicLicensing` in Info.plist.
Unconfigured builds hide enrollment and grant no sponsorship. Private signing keys
never belong in either app, an invitation, a profile, or the repository.

A patient opens **Clinic access**, accepts a single-use code, separately enables
sharing, and chooses **Use clinic destination**. An optional personal upload bearer
token goes into the dedicated secure clinic record. Selecting the destination
creates/selects an API profile with JSON output and daily-note injection off; it
does not enable scheduling. Existing personal profiles and purchase rights remain.
Patients still choose health metrics, date ranges and OS health permissions.

While sponsorship is active and there is no independent access, the export and
schedule destination controls show the approved clinic URL read-only. The API
settings editor does not offer a replacement URL or personal request headers.
Upload authorization still checks the actual frozen destination on every request;
profile imports or previously saved settings cannot grant another destination.
Managed clinic uploads keep their dedicated credential, redirect rejection and
response-body suppression even after the patient acquires independent access.

For signing-key overlap, set `CLINIC_LICENSING_TRUSTED_KEYS_JSON` to the generated
JSON map of key IDs to base64 SPKI values (one to four reviewed keys). This replaces
the single-key setting when present. Ship both old and new public keys in both native
apps before switching the server signing key; retain the old key until supported
clients have migrated. Neither key discovery nor trust is controlled by invitations.

The service binds membership to one installation. A replacement device or lost secure
record needs a fresh invitation. The administrator can issue additional invitations
without creating billable seats. Offline access lasts only until the signed expiry;
revocation becomes effective at the next successful refresh or that expiry. Failed
secure persistence is visible and blocks sponsorship in the current process.

Use fictional clinics and a reserved `.example` upload destination for device enrollment
QA. Do not export actual phone health data to a test receiver. Native configuration
and test keys are temporary build inputs, never production defaults. For local checks,
run `npm test` here, `python3 -m unittest scripts.tests.test_clinic_export_authorization`
from the root, and the owning Android `Clinic*Test`/API upload regressions. The portable
contracts CI group runs the service tests and shared fixture checks. Native build and
physical-device qualification follow the root repository verification policy.
The generic `make verify-native` iOS build is unsigned compilation evidence. For
Keychain enrollment QA, use a normal Xcode-signed simulator build (ad-hoc simulator
signing is sufficient); an unsigned app cannot establish its secure-storage identity.
Do not work around this by relaxing Keychain failures or storing credentials elsewhere.

## SetClinic integration boundary

SetClinic already operates its patient portal. This pilot uses phone-to-SetClinic
HTTP delivery and the separate licensing service; it does not require the
synthetic `apps/practice` portal or route health exports through Health.md servers.
Clinic-only access covers the approved destination, while independently acquired
access retains normal export rights. No blood-pressure-only or fixed-date pilot
scope is implied. Enrollment and sharing consent are separate, and patients keep
control of supported metric selections, date ranges and schedules.

The following receiver decisions require agreement with SetClinic's technical team:

- A test and production HTTPS endpoint using the restricted URL grammar in the
  [sponsorship contract](../../packages/contracts/clinic-sponsorship/v1/contract.md).
  Redirects, query tokens and arbitrary patient-edited destinations are unsupported.
- How an invitation/installation is associated with the correct patient in their
  system, and how a patient-specific revocable upload credential is issued,
  replaced and revoked. The current pilot accepts a manually entered bearer token;
  it does not implement their patient identity mapping or token provisioning.
- The accepted data contract. Both platforms use a `healthmd.api_export` JSON
  envelope, but current daily records differ: Apple `healthmd.health_data` v8 and
  Android frozen v4. Apple connected-provider exports can use envelope v2 and
  external records; Android compatibility API uses envelope v1. These are not one
  identical cross-platform record format. Agree whether their receiver supports
  both versioned profiles or requires a newly reviewed common representation.
  Preserve unsupported metrics and distinct OS statistics truthfully.
- Required metrics, supported history, timezones, capture completeness and provider
  data, plus the desired default delivery schedule. Compatibility API is the
  implemented sponsored delivery path. Android's separate raw-snapshot upload
  mode remains personal-only and needs receiver/transport work if requested.
- Maximum body size, batch handling and upsert/deduplication identity. Re-export
  sends replacement daily snapshots; delivery is not an exactly-once guarantee.
  Agree which 2xx responses mean durable acceptance and how authentication errors,
  429/5xx responses and a lost acknowledgment should be handled. A response body
  is not interpreted as a patient identity or application-level acceptance receipt.
- A synthetic test tenant and enrollment-to-receipt exercise, including repeated
  uploads, partial dates, timeouts, credential revocation and interrupted delivery.

Manual activation and invitation issuance are implemented; subscription checkout,
clinic admin web UI and patient invitation deep links remain outside this release.
SetClinic receiver implementation is deferred until their technical details arrive.
Native trust configuration and store-policy confirmation remain rollout prerequisites;
production infrastructure deployment does not activate a real clinic.
